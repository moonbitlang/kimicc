///|
/// The IQ2_XXS paired gate/up matvec, generated as Metal for one fixed
/// model.
///
/// This is the kernel both backends' profiles named: on Metal it is the
/// `gate_up` stage at roughly 40% of routed-MoE time, and on CPU its
/// analogue `ds4_vec_dot_iq2_xxs_pair_q8_K` is 44% of decode compute. It
/// multiplies one activation vector by two weight rows at once -- the
/// gate and up projections of a routed expert -- which halves weight
/// traffic per unit of work against running them separately.
///
/// The goal here is *parity*, not a win. ds4's version reads its
/// dimensions from a uniform block at runtime; this one bakes them, so
/// the block count, row stride, and main-loop trip count are literals.
/// Everything else -- the cooperative codebook staging, the accumulation
/// order, the simdgroup reduction, the final 0.25 scale -- mirrors ds4
/// statement for statement, because a parity claim is only meaningful if
/// the algorithm is held fixed.
///
/// What baking buys, and why it is not obviously free: ds4's `nb32`
/// derives from `args.ne00`, a runtime buffer field, so its compiler
/// cannot know the main loop runs exactly four times. Ours can. Whether
/// that helps or hurts is an empirical question -- unrolling a large body
/// raises register pressure and can cost occupancy -- which is why the
/// first deliverable is a correct kernel and a harness to measure it,
/// not a claim.
pub(all) struct Config {
  /// Input width, `ne00`. Must be a positive multiple of 256 (QK_K).
  in_dim : Int
  /// Output rows per expert, `ne0` -- the expert FFN width.
  out_rows : Int
  /// Weight rows each thread accumulates; ds4 hardcodes 4.
  nr0 : Int
  /// Simdgroups per threadgroup. ds4 supplies this as a Metal function
  /// constant; a generated kernel bakes it, which is the same
  /// information reaching the compiler by a different route.
  nsg : Int
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
/// An MSL type spelled verbatim: address-space qualifiers are part of a
/// Metal type's spelling and have no C equivalent, so they ride in the
/// name. This is what `Named` is for.
fn msl(spelling : String) -> @ctype.Type {
  Named(spelling)
}

///|
fn v(name : String) -> @parser.Expr {
  @build.v(name)
}

///|
/// `constant uint64_t gen_iq2xxs_grid[256]` -- the codebook, emitted as
/// a literal table rather than loaded. Shared with the scalar C
/// generator, which bakes the same 256 entries.
fn grid_table() -> @parser.GlobalDecl {
  let values : Array[@parser.Expr] = []
  for entry in @ds4_kernels.iq2xxs_grid {
    // MSL has no unsigned-long-long suffix conventions worth relying on;
    // the values are emitted as plain integers and the array's element
    // type carries the width.
    values.push(@parser.int_literal(entry.reinterpret_as_int64(), SLong))
  }
  @build.global(
    Array(msl("constant uint64_t"), 256),
    "gen_iq2xxs_grid",
    init=Array(values),
  )
}

///|
/// `constant uint8_t gen_ksigns[128]` -- the sign selector table,
/// reconstructed from the parity structure rather than transcribed.
fn ksigns_table() -> @parser.GlobalDecl {
  let values : Array[@parser.Expr] = []
  for s in 0..<128 {
    values.push(lit(@ds4_kernels.ksigns(s)))
  }
  @build.global(
    Array(msl("constant uint8_t"), 128),
    "gen_ksigns",
    init=Array(values),
  )
}

///|
/// `constant uint8_t gen_kmask[8]` -- the per-lane sign bit masks.
fn kmask_table() -> @parser.GlobalDecl {
  let values : Array[@parser.Expr] = []
  for j in 0..<8 {
    values.push(lit(1 << j))
  }
  @build.global(
    Array(msl("constant uint8_t"), 8),
    "gen_kmask",
    init=Array(values),
  )
}

///|
/// The cooperative staging prologue: every thread copies its slice of
/// the codebook and sign table into threadgroup memory, then barriers.
/// ds4 does this once per dispatch; mirroring it keeps the parity
/// comparison honest, and moving it to `constant` space is one of the
/// variants to try afterwards.
fn staging_stmts(cfg : Config) -> Array[@parser.Stmt] {
  let svalues = v("svalues")
  let ssigns = v("ssigns")
  let idx = v("idx")
  // ds4 hardcodes four grid entries per thread, which covers the
  // 256-entry table only when there are exactly two simdgroups; at any
  // other width its threads run off both tables. A strided loop is
  // correct for every `nsg`, and since `nsg` is baked the bounds are
  // still constants to the compiler.
  let stride = 32 * cfg.nsg
  fn copy_loop(dst : @parser.Expr, src : String, count : Int) -> @parser.Stmt {
    For(
      [
        VarDecl(
          SInt,
          "idx",
          Some(lit(32) * v("sgitg") + @build.cast(SInt, v("tiisg"))),
        ),
      ],
      idx.lt(lit(count)),
      Some(CompoundAssign("+", idx, lit(stride))),
      Compound([@build.assign(dst[idx], v(src)[idx])]),
    )
  }

  [
    @build.decl(
      msl("threadgroup uint64_t *"),
      "svalues",
      init=@build.cast(msl("threadgroup uint64_t *"), v("shmem")),
    ),
    @build.decl(
      msl("threadgroup uint8_t *"),
      "ssigns",
      init=@build.cast(msl("threadgroup uint8_t *"), svalues + lit(256)),
    ),
    copy_loop(svalues, "gen_iq2xxs_grid", 256),
    copy_loop(ssigns, "gen_ksigns", 128),
    ExprStmt(
      @build.call("threadgroup_barrier", [v("mem_flags::mem_threadgroup")]),
    ),
  ]
}

///|
/// The innermost work for one weight row: unpack the two 32-bit aux
/// words, derive the block scale, and accumulate eight signed codebook
/// entries against the staged activations for each of four lanes.
///
/// The float accumulation order is ds4's exactly -- `v * grid * sign`
/// summed lane by lane into a scalar, then scaled and added to the row
/// accumulator -- because reassociation here would forfeit the ability
/// to compare against ds4 at anything tighter than a tolerance.
fn row_body(suffix : String, acc : String) -> Array[@parser.Stmt] {
  let q = v("q" + suffix)
  let aux8 = v("aux8" + suffix)
  let aux32 = v("aux32" + suffix)
  let dh = v("dh" + suffix)
  let s = v("s" + suffix)
  let l = v("l")
  let j = v("j")
  let grid = v("grid" + suffix)
  let sign = v("sign" + suffix)
  [
    @build.decl(
      msl("device const uint8_t *"),
      "aux8" + suffix,
      init=@build.cast(msl("device const uint8_t *"), q),
    ),
    @build.decl(
      msl("uint32_t"),
      "aux32" + suffix,
      init=Binary("|", q[lit(2)], Binary("<<", q[lit(3)], lit(16))),
    ),
    @build.decl(
      Float,
      "d" + suffix,
      init=@build.cast(Float, dh[lit(0)]) *
        (flit(0.5) + @build.cast(Float, Binary(">>", aux32, lit(28)))),
    ),
    @build.decl(Float, "s" + suffix, init=flit(0.0)),
    @build.for_range(
      "l",
      lit(4),
      [
        @build.decl(
          msl("const threadgroup uint8_t *"),
          "grid" + suffix,
          init=@build.cast(
            msl("const threadgroup uint8_t *"),
            v("svalues") + aux8[l],
          ),
        ),
        @build.decl(
          msl("uint8_t"),
          "sign" + suffix,
          init=v("ssigns")[Binary(
              "&",
              Binary(">>", aux32, Binary("*", lit(7), l)),
              lit(127),
            )],
        ),
        @build.for_range(
          "j",
          lit(8),
          [
            @build.decl(Float, "y" + suffix, init=v("yl")[lit(8) * l + j]),
            @build.add_assign(
              s,
              v("y" + suffix) *
              @build.cast(Float, grid[j]) *
              Ternary(
                Binary("&", sign, v("gen_kmask")[j]),
                Unary("-", flit(1.0)),
                flit(1.0),
              ),
            ),
          ],
          ty=SShort,
        ),
      ],
      ty=SShort,
    ),
    @build.add_assign(v(acc)[v("row")], v("d" + suffix) * s),
  ]
}

///|
/// The generated kernel. The signature is what a standalone harness can
/// bind directly; ds4's expert-address indirection is a separate wrapper
/// concern, orthogonal to whether the compute is right.
fn kernel(cfg : Config) -> @msl.Kernel {
  let nb = cfg.in_dim / 256
  let nb32 = nb * 8
  // One 66-byte super-block per 256 values, so the stride between weight
  // rows is a literal here where ds4 reads `args.nb01` at runtime. Both
  // pointers walk in 2-byte units, matching ds4's `nb01/2`.
  let row_stride = nb * 66 / 2
  let body : Array[@parser.Stmt] = []
  for stmt in staging_stmts(cfg) {
    body.push(stmt)
  }
  let first_row = v("first_row")
  let ib32 = v("ib32")
  let row = v("row")
  body.push(
    @build.decl(
      SInt,
      "first_row",
      init=(MemberAccess(v("tgpig"), "x") * lit(cfg.nsg) + v("sgitg")) *
        lit(cfg.nr0),
    ),
  )
  // Weight rows for this thread, addressed in bytes then reinterpreted;
  // `first_row * row_bytes` is the baked equivalent of ds4's `offset0`.
  for side in ["g", "u"] {
    let src = if side == "g" { "src0_gate" } else { "src0_up" }
    body.push(
      @build.decl(
        msl("device const uint8_t *"),
        "base" + side,
        init=@build.cast(msl("device const uint8_t *"), v(src)) +
          first_row * lit(nb * 66),
      ),
    )
  }
  body.push(@build.decl(Array(Float, 32), "yl"))
  let zeros : Array[@parser.Expr] = []
  for _ in 0..<cfg.nr0 {
    zeros.push(flit(0.0))
  }
  body.push(@build.decl(Array(Float, cfg.nr0), "sumg", init=Array(zeros)))
  body.push(@build.decl(Array(Float, cfg.nr0), "sumu", init=Array(zeros)))
  body.push(
    @build.decl(
      msl("device const float *"),
      "y4",
      init=v("src1") + lit(32) * v("tiisg"),
    ),
  )
  // The main loop: exactly `nb32 / 32` trips, a literal here and a
  // runtime quantity in ds4, which is the specialization this kernel
  // exists to test.
  let loop_body : Array[@parser.Stmt] = [
    @build.for_range(
      "i",
      lit(32),
      [@build.assign(v("yl")[v("i")], v("y4")[v("i")])],
      ty=SShort,
    ),
    @build.decl(SInt, "ibl", init=Binary("/", ib32, lit(8))),
    @build.decl(SInt, "ib", init=Binary("%", ib32, lit(8))),
  ]
  for side in ["g", "u"] {
    loop_body.push(
      @build.decl(
        msl("device const uint16_t *"),
        "q" + side,
        init=@build.cast(
            msl("device const uint16_t *"),
            v("base" + side) + v("ibl") * lit(66) + lit(2),
          ) +
          lit(4) * v("ib"),
      ),
    )
    loop_body.push(
      @build.decl(
        msl("device const half *"),
        "dh" + side,
        init=@build.cast(
          msl("device const half *"),
          v("base" + side) + v("ibl") * lit(66),
        ),
      ),
    )
  }
  let per_row : Array[@parser.Stmt] = []
  for stmt in row_body("g", "sumg") {
    per_row.push(stmt)
  }
  for stmt in row_body("u", "sumu") {
    per_row.push(stmt)
  }
  // Advance to the next weight row, in 2-byte units as ds4 does.
  for side in ["g", "u"] {
    per_row.push(
      @build.assign(v("dh" + side), v("dh" + side) + lit(row_stride)),
    )
    per_row.push(@build.assign(v("q" + side), v("q" + side) + lit(row_stride)))
  }
  loop_body.push(@build.for_range("row", lit(cfg.nr0), per_row, ty=SShort))
  loop_body.push(@build.assign(v("y4"), v("y4") + lit(32 * 32)))
  body.push(
    For(
      [VarDecl(SInt, "ib32", Some(@build.cast(SInt, v("tiisg"))))],
      ib32.lt(lit(nb32)),
      Some(CompoundAssign("+", ib32, lit(32))),
      Compound(loop_body),
    ),
  )
  // Epilogue: one simdgroup reduction per row, lane 0 stores. The 0.25
  // is IQ2_XXS's fixed scale, folded the same way ds4 folds it.
  let epilogue : Array[@parser.Stmt] = [
    @build.decl(
      Float,
      "sum_gate",
      init=@build.call("simd_sum", [v("sumg")[row]]),
    ),
    @build.decl(Float, "sum_up", init=@build.call("simd_sum", [v("sumu")[row]])),
    If(
      v("tiisg").eq_expr(lit(0)),
      Compound([
        @build.assign(
          v("dst_gate")[first_row + row],
          v("sum_gate") * flit(0.25),
        ),
        @build.assign(v("dst_up")[first_row + row], v("sum_up") * flit(0.25)),
      ]),
      None,
    ),
  ]
  body.push(
    For(
      [VarDecl(SInt, "row", Some(lit(0)))],
      Binary(
        "&&",
        row.lt(lit(cfg.nr0)),
        (first_row + row).lt(lit(cfg.out_rows)),
      ),
      Some(PrefixInc(row)),
      Compound(epilogue),
    ),
  )
  {
    qualifier: "kernel",
    decl: @build.func(
      Void,
      "gen_iq2_xxs_pair_" + cfg.in_dim.to_string(),
      [
        @build.param(msl("device const char *"), "src0_gate"),
        @build.param(msl("device const char *"), "src0_up"),
        @build.param(msl("device const float *"), "src1"),
        @build.param(msl("device float *"), "dst_gate"),
        @build.param(msl("device float *"), "dst_up"),
        @build.param(msl("threadgroup char *"), "shmem"),
        @build.param(msl("uint3"), "tgpig"),
        @build.param(msl("ushort"), "tiisg"),
        @build.param(msl("ushort"), "sgitg"),
      ],
      body,
    ),
    decor: [
      @msl.plain(),
      @msl.plain(),
      @msl.plain(),
      @msl.plain(),
      @msl.plain(),
      @msl.decor("", attr="[[threadgroup(0)]]"),
      @msl.decor("", attr="[[threadgroup_position_in_grid]]"),
      @msl.decor("", attr="[[thread_index_in_simdgroup]]"),
      @msl.decor("", attr="[[simdgroup_index_in_threadgroup]]"),
    ],
  }
}

///|
/// Emits the translation unit: codebook tables then the kernel.
pub fn generate(cfg : Config) -> String {
  if cfg.in_dim <= 0 || cfg.in_dim % 256 != 0 {
    abort(
      "generate: in_dim must be a positive multiple of 256; got " +
      cfg.in_dim.to_string(),
    )
  }
  if cfg.out_rows <= 0 || cfg.nr0 <= 0 || cfg.nsg <= 0 {
    abort("generate: out_rows, nr0 and nsg must all be positive")
  }
  // Every simdgroup reads `nr0` weight rows unconditionally, so a
  // trailing threadgroup that runs past the tensor would read out of
  // bounds -- the epilogue guard only stops the stores. Rather than pay
  // for a bounds check in the inner loop, the shape is required to
  // divide evenly; the real expert widths do.
  if cfg.out_rows % (cfg.nsg * cfg.nr0) != 0 {
    abort(
      "generate: out_rows (" +
      cfg.out_rows.to_string() +
      ") must be a multiple of nsg*nr0 (" +
      (cfg.nsg * cfg.nr0).to_string() +
      "), or trailing simdgroups read past the weights",
    )
  }
  // ds4 prepends this to every shader it compiles; a standalone unit has
  // to carry it, or `simd_sum` and `mem_flags` resolve to nothing.
  let prelude =
    #|#include <metal_stdlib>
    #|using namespace metal;
    #|
  let tables = @printer.print_program(
    @build.program(globals=[grid_table(), ksigns_table(), kmask_table()]),
  )
  prelude + "\n" + tables + "\n" + @msl.print_kernel(kernel(cfg))
}
