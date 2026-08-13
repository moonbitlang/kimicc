///|
/// Specialized scalar kernels for ds4's quantized dot products, generated
/// for one fixed model's dimensions.
///
/// ds4 (antirez's DeepSeek-V4 engine) funnels CPU decode through a small
/// set of row-dot kernels over quantized blocks. The three formats the
/// DeepSeek-V4-Flash checkpoint actually uses are generated here:
///
///   q8_0     34-byte blocks: f16 scale + 32 int8 quants
///            (attention projections, shared experts, output head)
///   Q2_K     84-byte super-blocks of 256 values: 16 scale nibbles,
///            64 packed 2-bit quant bytes, f16 d and dmin
///            (routed-expert down projections)
///   IQ2_XXS  66-byte super-blocks of 256 values: f16 d + 32 u16 of
///            codebook indices and sign words (routed-expert gate/up)
///
/// Every loop bound, byte offset, and group shift below is a
/// generation-time constant, and the IQ2_XXS sign table -- which ds4
/// expands at runtime under `pthread_once` -- is baked as a literal
/// static array: generation-time folding of exactly the work a generic
/// engine repeats at startup.
///
/// The arithmetic mirrors ds4's scalar kernels expression by expression,
/// because the referee test compares results bit for bit against ds4's
/// own functions compiled in the same translation unit. Integer index
/// math may be restructured freely (equal values are equal), but the
/// floating-point operation tree of each accumulation is kept identical:
/// float addition is not associative, and any reordering would turn a
/// bit-exact referee into a tolerance argument.
///
/// The signatures use plain pointers; ds4 writes `const` here, which the
/// type model does not carry yet (tracked in the plan doc, deliberately
/// deferred -- it changes nothing about codegen for these kernels).
pub(all) struct Config {
  /// One q8_0 row-dot kernel per entry; any positive row width, a final
  /// short block is emitted for widths not divisible by 32.
  q8_dims : Array[Int]
  /// One Q2_K kernel per entry; widths must be positive multiples of 256.
  q2k_dims : Array[Int]
  /// One IQ2_XXS kernel per entry; widths must be positive multiples of
  /// 256. Non-empty means the sign table is emitted.
  iq2_dims : Array[Int]
}

///|
fn lit(n : Int) -> @parser.Expr {
  @parser.int_literal(n.to_int64(), SInt)
}

///|
fn flit(x : Double) -> @parser.Expr {
  @parser.float_literal(Float::from_double(x))
}

///|
/// A possibly-negative literal in canonical form: the parser never
/// produces a negative `int_literal`, it produces negation applied to a
/// positive one.
fn slit(n : Int) -> @parser.Expr {
  if n < 0 {
    Unary("-", lit(-n))
  } else {
    lit(n)
  }
}

///|
fn shr(a : @parser.Expr, n : Int) -> @parser.Expr {
  Binary(">>", a, lit(n))
}

///|
fn band(a : @parser.Expr, n : Int) -> @parser.Expr {
  Binary("&", a, lit(n))
}

///|
fn bor(a : @parser.Expr, b : @parser.Expr) -> @parser.Expr {
  Binary("|", a, b)
}

///|
/// `memcpy(&name, src, sizeof(ty))` -- the strict-aliasing-safe unaligned
/// load ds4 uses for every f16 scale and sign word.
fn load_into(
  name : String,
  src : @parser.Expr,
  ty : @ctype.Type,
) -> @parser.Stmt {
  ExprStmt(@build.call("memcpy", [AddrOf(@build.v(name)), src, Sizeof(ty)]))
}

///|
/// The scalar half-to-float conversion, ported from ds4's fallback branch
/// (ds4 itself uses a NEON `vcvt` on ARM; for finite inputs the two are
/// the same bits, and the referee constrains scales to finite values).
fn f16_to_f32_fn() -> @parser.FuncDecl {
  let h = @build.v("h")
  let sign = @build.v("sign")
  let exp = @build.v("exp")
  let mant = @build.v("mant")
  let bits = @build.v("bits")
  let f = @build.v("f")
  // ds4 writes `(exp + 127 - 15) << 23`; the exponent shift is applied to
  // `exp` first here so the printed form needs no precedence parentheses
  // (clang warns on `a + b << c`). Integer restructuring is free -- only
  // the float trees are order-locked.
  let rebias = @build.assign(exp, Binary("+", exp, lit(112)))
  let normal_bits = bor(
    bor(sign, Binary("<<", exp, lit(23))),
    Binary("<<", mant, lit(13)),
  )
  @build.func(
    Float,
    "gen_f16_to_f32",
    [@build.param(UShort, "h")],
    [
      @build.decl(
        UInt,
        "sign",
        init=Binary("<<", @build.cast(UInt, band(h, 32768)), lit(16)),
      ),
      @build.decl(UInt, "exp", init=band(shr(h, 10), 31)),
      @build.decl(UInt, "mant", init=band(h, 1023)),
      @build.decl(UInt, "bits"),
      If(
        exp.eq_expr(lit(0)),
        Compound([
          If(
            mant.eq_expr(lit(0)),
            Compound([@build.assign(bits, sign)]),
            Some(
              Compound([
                @build.assign(exp, lit(1)),
                While(
                  band(mant, 1024).eq_expr(lit(0)),
                  Compound([
                    ExprStmt(CompoundAssign("<<", mant, lit(1))),
                    ExprStmt(PostfixDec(exp)),
                  ]),
                ),
                @build.assign(mant, band(mant, 1023)),
                rebias,
                @build.assign(bits, normal_bits),
              ]),
            ),
          ),
        ]),
        Some(
          If(
            exp.eq_expr(lit(31)),
            Compound([
              @build.assign(
                bits,
                bor(bor(sign, lit(2139095040)), Binary("<<", mant, lit(13))),
              ),
            ]),
            Some(Compound([rebias, @build.assign(bits, normal_bits)])),
          ),
        ),
      ),
      @build.decl(Float, "f"),
      ExprStmt(@build.call("memcpy", [AddrOf(f), AddrOf(bits), Sizeof(Float)])),
      @build.ret(value=f),
    ],
    is_static=true,
  )
}

///|
/// One q8_0 block: load the f16 scale, integer-dot `n` quants against the
/// activation quants, accumulate scale * xscale[b] * dot. `b` is either
/// the loop counter (full blocks) or a folded constant (the tail block).
fn q8_block_stmts(b : @parser.Expr, n : Int) -> Array[@parser.Stmt] {
  let row = @build.v("row")
  let xq = @build.v("xq")
  let xscale = @build.v("xscale")
  let qs = @build.v("qs")
  let sum = @build.v("sum")
  let acc = @build.v("acc")
  let i = @build.v("i")
  [
    @build.decl(UShort, "scale_bits"),
    load_into("scale_bits", row + b * lit(34), UShort),
    @build.decl(
      Pointer(SChar),
      "qs",
      init=@build.cast(Pointer(SChar), row + b * lit(34) + lit(2)),
    ),
    @build.decl(SInt, "sum", init=lit(0)),
    @build.for_range("i", lit(n), [
      @build.add_assign(
        sum,
        @build.cast(SInt, qs[i]) * @build.cast(SInt, xq[b * lit(32) + i]),
      ),
    ]),
    @build.add_assign(
      acc,
      @build.call("gen_f16_to_f32", [@build.v("scale_bits")]) *
      xscale[b] *
      @build.cast(Float, sum),
    ),
  ]
}

///|
/// `float gen_dot_q8_0_row_<d>(unsigned char *row, char *xq,
/// float *xscale)` -- one weight row of `d` values in ceil(d/32) blocks
/// against pre-quantized activations, ds4's `dot_q8_0_row` with the row
/// width and block count baked. (`char` is the toolkit's canonical
/// spelling of SChar; the referee's function-pointer types match it.)
fn dot_q8_0_row_fn(d : Int) -> @parser.FuncDecl {
  let full = d / 32
  let rem = d % 32
  let body : Array[@parser.Stmt] = [@build.decl(Float, "acc", init=flit(0.0))]
  if full > 0 {
    body.push(
      @build.for_range("b", lit(full), q8_block_stmts(@build.v("b"), 32)),
    )
  }
  if rem > 0 {
    body.push(Compound(q8_block_stmts(lit(full), rem)))
  }
  body.push(@build.ret(value=@build.v("acc")))
  @build.func(
    Float,
    "gen_dot_q8_0_row_" + d.to_string(),
    [
      @build.param(Pointer(UChar), "row"),
      @build.param(Pointer(SChar), "xq"),
      @build.param(Pointer(Float), "xscale"),
    ],
    body,
    is_static=true,
  )
}

///|
/// `float gen_dot_q2_K_<d>(unsigned char *x, float *y)` -- ds4's
/// `ds4_vec_dot_q2_K_f32` with the super-block count baked and the
/// 16-group inner structure unrolled: each group's quant-byte base and
/// crumb shift are generation-time constants, and the per-group scale
/// products hoist out of the 16-element loop. The per-element float tree
/// `(d*sc_lo)*q - dmin*sc_hi`, times `y[k]`, summed in k order, is ds4's
/// exactly.
fn dot_q2_k_fn(d : Int) -> @parser.FuncDecl {
  let nb = d / 256
  let x = @build.v("x")
  let y = @build.v("y")
  let blk = @build.v("blk")
  let sum = @build.v("sum")
  let l = @build.v("l")
  let block_base = blk * lit(84)
  let block_stmts : Array[@parser.Stmt] = [
    @build.decl(UShort, "dbits"),
    load_into("dbits", x + block_base + lit(80), UShort),
    @build.decl(UShort, "dminbits"),
    load_into("dminbits", x + block_base + lit(82), UShort),
    @build.decl(
      Float,
      "d",
      init=@build.call("gen_f16_to_f32", [@build.v("dbits")]),
    ),
    @build.decl(
      Float,
      "dmin",
      init=@build.call("gen_f16_to_f32", [@build.v("dminbits")]),
    ),
  ]
  for group in 0..<16 {
    let q_base = 32 * (group / 8) + 16 * (group % 2)
    let shift = group / 2 % 4 * 2
    let sc = @build.v("sc")
    let ds = @build.v("ds")
    let dm = @build.v("dm")
    let quant_byte = @build.cast(SInt, x[block_base + lit(16 + q_base) + l])
    let q = if shift == 0 {
      band(quant_byte, 3)
    } else {
      band(shr(quant_byte, shift), 3)
    }
    block_stmts.push(
      Compound([
        @build.decl(
          SInt,
          "sc",
          init=@build.cast(SInt, x[block_base + lit(group)]),
        ),
        @build.decl(
          Float,
          "ds",
          init=@build.v("d") * @build.cast(Float, band(sc, 15)),
        ),
        @build.decl(
          Float,
          "dm",
          init=@build.v("dmin") * @build.cast(Float, shr(sc, 4)),
        ),
        @build.for_range("l", lit(16), [
          @build.decl(SInt, "q", init=q),
          @build.add_assign(
            sum,
            (ds * @build.cast(Float, @build.v("q")) - dm) *
            y[blk * lit(256) + lit(group * 16) + l],
          ),
        ]),
      ]),
    )
  }
  @build.func(
    Float,
    "gen_dot_q2_K_" + d.to_string(),
    [@build.param(Pointer(UChar), "x"), @build.param(Pointer(Float), "y")],
    [
      @build.decl(Float, "sum", init=flit(0.0)),
      @build.for_range("blk", lit(nb), block_stmts),
      @build.ret(value=sum),
    ],
    is_static=true,
  )
}

///|
/// `float gen_dot_iq2_xxs_<d>(unsigned char *x, float *y)` -- ds4's
/// `ds4_vec_dot_iq2_xxs_f32` with super-block count baked, the eight
/// 32-value groups and four 8-value lanes unrolled (their byte offsets
/// and sign-word shifts fold to constants), and the codebook lookup
/// aimed at the baked sign table instead of the runtime-built one.
fn dot_iq2_xxs_fn(d : Int) -> @parser.FuncDecl {
  let nb = d / 256
  let x = @build.v("x")
  let y = @build.v("y")
  let blk = @build.v("blk")
  let sumf = @build.v("sumf")
  let j = @build.v("j")
  let block_base = blk * lit(66)
  let block_stmts : Array[@parser.Stmt] = [
    @build.decl(UShort, "dbits"),
    load_into("dbits", x + block_base, UShort),
    @build.decl(
      Float,
      "d",
      init=@build.call("gen_f16_to_f32", [@build.v("dbits")]),
    ),
  ]
  for ib32 in 0..<8 {
    let group_stmts : Array[@parser.Stmt] = [
      @build.decl(UInt, "aux0"),
      load_into("aux0", x + block_base + lit(2 + ib32 * 8), UInt),
      @build.decl(UInt, "aux1"),
      load_into("aux1", x + block_base + lit(6 + ib32 * 8), UInt),
      @build.decl(
        Float,
        "scale",
        init=flit(0.125) *
          @build.v("d") *
          @build.cast(
            Float,
            Binary("+", Binary("*", lit(2), shr(@build.v("aux1"), 28)), lit(1)),
          ),
      ),
    ]
    for lane in 0..<4 {
      let aux0 = @build.v("aux0")
      let aux1 = @build.v("aux1")
      let g = @build.v("g")
      let sign_idx = @build.v("sign_idx")
      let sign_word = if lane == 0 { aux1 } else { shr(aux1, 7 * lane) }
      let grid_byte = if lane == 0 { aux0 } else { shr(aux0, 8 * lane) }
      group_stmts.push(
        Compound([
          @build.decl(UInt, "sign_idx", init=band(sign_word, 127)),
          @build.decl(UInt, "g", init=band(grid_byte, 255)),
          @build.for_range("j", lit(8), [
            @build.add_assign(
              sumf,
              @build.v("scale") *
              @build.cast(
                Float,
                @build.v("gen_iq2xxs_signed_grid")[(g * lit(128) + sign_idx) *
                lit(8) +
                j],
              ) *
              y[blk * lit(256) + lit(ib32 * 32 + lane * 8) + j],
            ),
          ]),
        ]),
      )
    }
    block_stmts.push(Compound(group_stmts))
  }
  @build.func(
    Float,
    "gen_dot_iq2_xxs_" + d.to_string(),
    [@build.param(Pointer(UChar), "x"), @build.param(Pointer(Float), "y")],
    [
      @build.decl(Float, "sumf", init=flit(0.0)),
      @build.for_range("blk", lit(nb), block_stmts),
      @build.ret(value=sumf),
    ],
    is_static=true,
  )
}

///|
/// ksigns_iq2xs reconstructed: entry `s` is `s` with the parity of its
/// low seven bits in bit 7, so bit `j` of the entry is the sign for lane
/// `j` (ds4 stores the same 128 bytes as a literal table). The referee
/// memcmp against ds4's expansion is what makes this reconstruction safe
/// to rely on.
fn ksigns(s : Int) -> Int {
  let mut parity = 0
  for j in 0..<7 {
    parity = parity ^ ((s >> j) & 1)
  }
  s | (parity << 7)
}

///|
/// The expanded sign table ds4 builds at startup: entry [g][s][j] is
/// grid byte j of codebook entry g, negated when sign word s has bit j
/// set. Flattened to one dimension; the layout matches ds4's
/// `int8_t [256][128][8]` byte for byte.
fn signed_grid_values() -> Array[@parser.Expr] {
  let out : Array[@parser.Expr] = Array::new(capacity=256 * 128 * 8)
  for g in 0..<256 {
    let entry = iq2xxs_grid[g]
    for s in 0..<128 {
      let signs = ksigns(s)
      for j in 0..<8 {
        let byte = ((entry >> (8 * j)) & 0xff).to_int()
        let value = if (signs & (1 << j)) != 0 { -byte } else { byte }
        out.push(slit(value))
      }
    }
  }
  out
}

///|
/// The full generated translation unit: sign table (when any IQ2_XXS
/// kernel needs it), the f16 helper, then one kernel per configured
/// width. The caller prepends `#include <string.h>` for memcpy; the
/// program itself is preprocessor-free.
pub fn generate_kernels(cfg : Config) -> String {
  for d in cfg.q8_dims {
    if d <= 0 {
      abort(
        "generate_kernels: q8_0 width must be positive; got " + d.to_string(),
      )
    }
  }
  for d in cfg.q2k_dims {
    if d <= 0 || d % 256 != 0 {
      abort(
        "generate_kernels: Q2_K width must be a positive multiple of 256; got " +
        d.to_string(),
      )
    }
  }
  for d in cfg.iq2_dims {
    if d <= 0 || d % 256 != 0 {
      abort(
        "generate_kernels: IQ2_XXS width must be a positive multiple of 256; got " +
        d.to_string(),
      )
    }
  }
  fn require_distinct(dims : Array[Int], kind : String) {
    for i in 0..<dims.length() {
      for k in 0..<i {
        if dims[i] == dims[k] {
          abort(
            "generate_kernels: duplicate " +
            kind +
            " width " +
            dims[i].to_string(),
          )
        }
      }
    }
  }
  require_distinct(cfg.q8_dims, "q8_0")
  require_distinct(cfg.q2k_dims, "Q2_K")
  require_distinct(cfg.iq2_dims, "IQ2_XXS")
  let items : Array[@build.Item] = []
  if cfg.iq2_dims.length() > 0 {
    items.push(
      Global(
        @build.global(
          Array(SChar, 256 * 128 * 8),
          "gen_iq2xxs_signed_grid",
          init=Array(signed_grid_values()),
          is_static=true,
        ),
      ),
    )
  }
  items.push(Func(f16_to_f32_fn()))
  for d in cfg.q8_dims {
    items.push(Func(dot_q8_0_row_fn(d)))
  }
  for d in cfg.q2k_dims {
    items.push(Func(dot_q2_k_fn(d)))
  }
  for d in cfg.iq2_dims {
    items.push(Func(dot_iq2_xxs_fn(d)))
  }
  @printer.print_program(@build.ordered_program(items))
}
