///|
/// A specialized transformer forward pass, generated for one fixed model.
///
/// This is the experiment the construction API exists for: every dimension,
/// loop bound, and weight offset below is a generation-time constant, the
/// layer stack is fully unrolled, and the RoPE tables are baked as literal
/// arrays -- the specializations a hand-written engine applies at a few hot
/// call sites, applied everywhere, regenerable when the model changes. The
/// driver stays hand-written; the seam is one C function:
///
///   void forward(float *w, int token, int pos, float *logits);
///
/// (`w` would be `const float *` if the type model carried qualifiers; the
/// plan tracks `const`/`restrict` as an open gap, and this signature follows
/// what can be emitted today.)
///
/// KV cache and scratch live as statics inside the generated file, since a
/// fixed model has fixed sizes.
pub(all) struct Config {
  dim : Int
  hidden : Int
  n_layers : Int
  n_heads : Int
  // Grouped-query attention is not generated yet. The field exists so a
  // real checkpoint's value is stated and checked: a GQA model has smaller
  // `wk`/`wv` tensors, and reading it with full-width offsets would fetch
  // wrong weights silently. `generate_forward` aborts unless it equals
  // `n_heads`.
  n_kv_heads : Int
  vocab : Int
  seq : Int
}

///|
fn lit(n : Int) -> @parser.Expr {
  @parser.int_literal(n.to_int64(), SInt)
}

///|
/// Weight offsets are 64-bit: a 7B-class configuration crosses `INT_MAX`
/// partway through the layer stack, and a wrapped offset reads the wrong
/// weights silently.
fn lit64(n : Int64) -> @parser.Expr {
  @parser.int_literal(n, SLong)
}

///|
fn flit(x : Double) -> @parser.Expr {
  @parser.float_literal(Float::from_double(x))
}

///|
/// `o[i] = w[i] * (x[i] * rsqrt(mean(x^2) + eps))`, bound `n` constant.
fn rmsnorm_fn(name : String, n : Int) -> @parser.FuncDecl {
  let fptr : @ctype.Type = Pointer(Float)
  let o = @build.v("o")
  let x = @build.v("x")
  let w = @build.v("w")
  let i = @build.v("i")
  let ss = @build.v("ss")
  @build.func(
    Void,
    name,
    [@build.param(fptr, "o"), @build.param(fptr, "x"), @build.param(fptr, "w")],
    [
      @build.decl(Float, "ss", init=flit(0.0)),
      @build.for_range("i", lit(n), [@build.add_assign(ss, x[i] * x[i])]),
      @build.assign(
        ss,
        flit(1.0) /
        @build.call("sqrtf", [ss / flit(n.to_double()) + flit(1.0e-5)]),
      ),
      @build.for_range("i", lit(n), [@build.assign(o[i], w[i] * (x[i] * ss))]),
    ],
    is_static=true,
  )
}

///|
/// `o = W x` with `W` row-major `rows x cols`, both bounds constant.
fn matmul_fn(name : String, rows : Int, cols : Int) -> @parser.FuncDecl {
  let fptr : @ctype.Type = Pointer(Float)
  let o = @build.v("o")
  let x = @build.v("x")
  let w = @build.v("w")
  let i = @build.v("i")
  let j = @build.v("j")
  let acc = @build.v("acc")
  @build.func(
    Void,
    name,
    [@build.param(fptr, "o"), @build.param(fptr, "x"), @build.param(fptr, "w")],
    [
      @build.for_range("i", lit(rows), [
        @build.decl(Float, "acc", init=flit(0.0)),
        @build.for_range("j", lit(cols), [
          // The flattened index is long arithmetic: a matrix past INT_MAX
          // elements would overflow C int before indexing.
          @build.add_assign(
            acc,
            w[@build.cast(SLong, i) * lit64(cols.to_int64()) + j] * x[j],
          ),
        ]),
        @build.assign(o[i], acc),
      ]),
    ],
    is_static=true,
  )
}

///|
/// The RoPE tables for every position and frequency, baked as literals.
fn rope_tables(cfg : Config) -> Array[@parser.GlobalDecl] {
  let head = cfg.dim / cfg.n_heads
  let half = head / 2
  let cos_values : Array[@parser.Expr] = []
  let sin_values : Array[@parser.Expr] = []
  for pos in 0..<cfg.seq {
    for k in 0..<half {
      let freq = 1.0 /
        @math.pow(10000.0, (2 * k).to_double() / head.to_double())
      let angle = pos.to_double() * freq
      cos_values.push(flit(@math.cos(angle)))
      sin_values.push(flit(@math.sin(angle)))
    }
  }
  [
    @build.global(
      Array(Float, cfg.seq * half),
      "rope_cos",
      init=Array(cos_values),
      is_static=true,
    ),
    @build.global(
      Array(Float, cfg.seq * half),
      "rope_sin",
      init=Array(sin_values),
      is_static=true,
    ),
  ]
}

///|
/// The forward pass, layers unrolled, offsets baked.
pub fn generate_forward(cfg : Config) -> String {
  if cfg.dim <= 0 ||
    cfg.hidden <= 0 ||
    cfg.n_layers <= 0 ||
    cfg.vocab <= 0 ||
    cfg.seq <= 0 {
    abort("generate_forward: every model dimension must be positive")
  }
  if cfg.n_heads <= 0 ||
    cfg.dim % cfg.n_heads != 0 ||
    cfg.dim / cfg.n_heads % 2 != 0 {
    abort(
      "generate_forward: dim must split into a positive even head width; " +
      "got dim " +
      cfg.dim.to_string() +
      ", n_heads " +
      cfg.n_heads.to_string(),
    )
  }
  if cfg.n_kv_heads != cfg.n_heads {
    abort(
      "generate_forward: grouped-query attention (n_kv_heads " +
      cfg.n_kv_heads.to_string() +
      " != n_heads " +
      cfg.n_heads.to_string() +
      ") is not generated yet",
    )
  }
  let dim = cfg.dim
  let hidden = cfg.hidden
  let head = dim / cfg.n_heads
  let half = head / 2
  // Weight blob layout: llama2.c's, tensors grouped by type across layers,
  // with the legacy RoPE region after the final norm and a tied classifier.
  // All offset arithmetic is 64-bit -- model-scale configurations overflow
  // Int -- and the static caches carry an explicit representability guard.
  let dim64 = dim.to_int64()
  let hidden64 = hidden.to_int64()
  let layers64 = cfg.n_layers.to_int64()
  let mut off : Int64 = 0
  let embedding = off
  off += cfg.vocab.to_int64() * dim64
  let rms_att0 = off
  off += layers64 * dim64
  let wq0 = off
  off += layers64 * dim64 * dim64
  let wk0 = off
  off += layers64 * dim64 * dim64
  let wv0 = off
  off += layers64 * dim64 * dim64
  let wo0 = off
  off += layers64 * dim64 * dim64
  let rms_ffn0 = off
  off += layers64 * dim64
  let w1_0 = off
  off += layers64 * dim64 * hidden64
  let w2_0 = off
  off += layers64 * hidden64 * dim64
  let w3_0 = off
  off += layers64 * dim64 * hidden64
  let rms_final = off
  off += dim64
  // Legacy freq_cis region, skipped by readers, part of the file size.
  off += 2L * cfg.seq.to_int64() * (head / 2).to_int64()
  let _total = off
  let kv_elems : Int64 = layers64 * cfg.seq.to_int64() * dim64
  if kv_elems > 2147483647L {
    abort(
      "generate_forward: KV cache of " +
      kv_elems.to_string() +
      " floats exceeds a static array; this generator's cache is static",
    )
  }
  let kv_size = kv_elems.to_int()
  let fptr : @ctype.Type = Pointer(Float)
  let w = @build.v("w")
  let x = @build.v("x")
  let token = @build.v("token")
  let pos = @build.v("pos")
  let logits = @build.v("logits")
  let i = @build.v("i")

  // Static state: activation scratch and the KV cache.
  let state : Array[@parser.GlobalDecl] = [
    @build.global(Array(Float, dim), "x", is_static=true),
    @build.global(Array(Float, dim), "xb", is_static=true),
    @build.global(Array(Float, dim), "xb2", is_static=true),
    @build.global(Array(Float, hidden), "hb", is_static=true),
    @build.global(Array(Float, hidden), "hb2", is_static=true),
    @build.global(Array(Float, dim), "q", is_static=true),
    @build.global(Array(Float, kv_size), "kc", is_static=true),
    @build.global(Array(Float, kv_size), "vc", is_static=true),
    @build.global(Array(Float, cfg.seq), "att", is_static=true),
  ]
  let body : Array[@parser.Stmt] = []
  // x = embedding[token]
  body.push(
    @build.for_range("i", lit(dim), [
      @build.assign(
        x[i],
        w[lit64(embedding) + @build.cast(SLong, token) * lit64(dim64) + i],
      ),
    ]),
  )
  for l in 0..<cfg.n_layers {
    let l64 = l.to_int64()
    let rms_att = rms_att0 + l64 * dim64
    let wq = wq0 + l64 * dim64 * dim64
    let wk = wk0 + l64 * dim64 * dim64
    let wv = wv0 + l64 * dim64 * dim64
    let wo = wo0 + l64 * dim64 * dim64
    let rms_ffn = rms_ffn0 + l64 * dim64
    let w1 = w1_0 + l64 * dim64 * hidden64
    let w2 = w2_0 + l64 * hidden64 * dim64
    let w3 = w3_0 + l64 * dim64 * hidden64
    let kbase = @build.v("kc")[lit64(l.to_int64() * cfg.seq.to_int64() * dim64) +
      pos * lit(dim)]
    // Attention rmsnorm and QKV. K and V go straight into the cache row.
    body.push(
      ExprStmt(
        @build.call("rmsnorm_d", [
          @build.v("xb"),
          @build.v("x"),
          AddrOf(w[lit64(rms_att)]),
        ]),
      ),
    )
    body.push(
      ExprStmt(
        @build.call("matmul_dd", [
          @build.v("q"),
          @build.v("xb"),
          AddrOf(w[lit64(wq)]),
        ]),
      ),
    )
    body.push(
      ExprStmt(
        @build.call("matmul_dd", [
          AddrOf(kbase),
          @build.v("xb"),
          AddrOf(w[lit64(wk)]),
        ]),
      ),
    )
    body.push(
      ExprStmt(
        @build.call("matmul_dd", [
          AddrOf(
            @build.v("vc")[lit64(l.to_int64() * cfg.seq.to_int64() * dim64) +
            pos * lit(dim)],
          ),
          @build.v("xb"),
          AddrOf(w[lit64(wv)]),
        ]),
      ),
    )
    // RoPE on q and cached k, heads unrolled by constant bounds.
    let h = @build.v("h")
    let k = @build.v("k")
    body.push(
      @build.for_range("h", lit(cfg.n_heads), [
        @build.for_range("k", lit(half), [
          @build.decl(SInt, "b", init=h * lit(head) + k * lit(2)),
          @build.decl(
            Float,
            "c",
            init=@build.v("rope_cos")[pos * lit(half) + k],
          ),
          @build.decl(
            Float,
            "s",
            init=@build.v("rope_sin")[pos * lit(half) + k],
          ),
          @build.decl(Float, "q0", init=@build.v("q")[@build.v("b")]),
          @build.decl(Float, "q1", init=@build.v("q")[@build.v("b") + lit(1)]),
          @build.assign(
            @build.v("q")[@build.v("b")],
            @build.v("q0") * @build.v("c") - @build.v("q1") * @build.v("s"),
          ),
          @build.assign(
            @build.v("q")[@build.v("b") + lit(1)],
            @build.v("q0") * @build.v("s") + @build.v("q1") * @build.v("c"),
          ),
          @build.decl(
            SInt,
            "kb",
            init=lit64(l.to_int64() * cfg.seq.to_int64() * dim64) +
              pos * lit(dim) +
              @build.v("b"),
          ),
          @build.decl(Float, "k0", init=@build.v("kc")[@build.v("kb")]),
          @build.decl(Float, "k1", init=@build.v("kc")[@build.v("kb") + lit(1)]),
          @build.assign(
            @build.v("kc")[@build.v("kb")],
            @build.v("k0") * @build.v("c") - @build.v("k1") * @build.v("s"),
          ),
          @build.assign(
            @build.v("kc")[@build.v("kb") + lit(1)],
            @build.v("k0") * @build.v("s") + @build.v("k1") * @build.v("c"),
          ),
        ]),
      ]),
    )
    // Attention per head: scores over cached keys, softmax, weighted V.
    let p = @build.v("p")
    let t = @build.v("t")
    body.push(
      @build.for_range("h", lit(cfg.n_heads), [
        // Scores for positions 0..=pos (runtime bound).
        For(
          [VarDecl(SInt, "p", Some(lit(0)))],
          p.le(pos),
          Some(PostfixInc(p)),
          Compound([
            @build.decl(Float, "score", init=flit(0.0)),
            @build.for_range("t", lit(head), [
              @build.add_assign(
                @build.v("score"),
                @build.v("q")[h * lit(head) + t] *
                @build.v("kc")[lit64(l.to_int64() * cfg.seq.to_int64() * dim64) +
                p * lit(dim) +
                h * lit(head) +
                t],
              ),
            ]),
            @build.assign(
              @build.v("att")[p],
              @build.v("score") / flit(head.to_double().sqrt()),
            ),
          ]),
        ),
        // Softmax over att[0..=pos].
        @build.decl(Float, "mx", init=@build.v("att")[lit(0)]),
        For(
          [VarDecl(SInt, "p", Some(lit(1)))],
          p.le(pos),
          Some(PostfixInc(p)),
          Compound([
            If(
              @build.v("att")[p].gt(@build.v("mx")),
              Compound([@build.assign(@build.v("mx"), @build.v("att")[p])]),
              None,
            ),
          ]),
        ),
        @build.decl(Float, "sum", init=flit(0.0)),
        For(
          [VarDecl(SInt, "p", Some(lit(0)))],
          p.le(pos),
          Some(PostfixInc(p)),
          Compound([
            @build.assign(
              @build.v("att")[p],
              @build.call("expf", [@build.v("att")[p] - @build.v("mx")]),
            ),
            @build.add_assign(@build.v("sum"), @build.v("att")[p]),
          ]),
        ),
        // Weighted sum of V into xb.
        @build.for_range("t", lit(head), [
          @build.decl(Float, "val", init=flit(0.0)),
          For(
            [VarDecl(SInt, "p", Some(lit(0)))],
            p.le(pos),
            Some(PostfixInc(p)),
            Compound([
              @build.add_assign(
                @build.v("val"),
                @build.v("att")[p] /
                @build.v("sum") *
                @build.v("vc")[lit64(l.to_int64() * cfg.seq.to_int64() * dim64) +
                p * lit(dim) +
                h * lit(head) +
                t],
              ),
            ]),
          ),
          @build.assign(@build.v("xb")[h * lit(head) + t], @build.v("val")),
        ]),
      ]),
    )
    // Output projection and residual.
    body.push(
      ExprStmt(
        @build.call("matmul_dd", [
          @build.v("xb2"),
          @build.v("xb"),
          AddrOf(w[lit64(wo)]),
        ]),
      ),
    )
    body.push(
      @build.for_range("i", lit(dim), [
        @build.add_assign(x[i], @build.v("xb2")[i]),
      ]),
    )
    // FFN: rmsnorm, w1/w3, silu, w2, residual.
    body.push(
      ExprStmt(
        @build.call("rmsnorm_d", [
          @build.v("xb"),
          @build.v("x"),
          AddrOf(w[lit64(rms_ffn)]),
        ]),
      ),
    )
    body.push(
      ExprStmt(
        @build.call("matmul_hd", [
          @build.v("hb"),
          @build.v("xb"),
          AddrOf(w[lit64(w1)]),
        ]),
      ),
    )
    body.push(
      ExprStmt(
        @build.call("matmul_hd", [
          @build.v("hb2"),
          @build.v("xb"),
          AddrOf(w[lit64(w3)]),
        ]),
      ),
    )
    body.push(
      @build.for_range("i", lit(hidden), [
        @build.assign(
          @build.v("hb")[i],
          @build.v("hb")[i] /
          (flit(1.0) + @build.call("expf", [-@build.v("hb")[i]])) *
          @build.v("hb2")[i],
        ),
      ]),
    )
    body.push(
      ExprStmt(
        @build.call("matmul_dh", [
          @build.v("xb2"),
          @build.v("hb"),
          AddrOf(w[lit64(w2)]),
        ]),
      ),
    )
    body.push(
      @build.for_range("i", lit(dim), [
        @build.add_assign(x[i], @build.v("xb2")[i]),
      ]),
    )
  }
  // Final norm and tied classifier.
  body.push(
    ExprStmt(
      @build.call("rmsnorm_d", [
        @build.v("x"),
        @build.v("x"),
        AddrOf(w[lit64(rms_final)]),
      ]),
    ),
  )
  body.push(
    ExprStmt(
      @build.call("matmul_vd", [
        logits,
        @build.v("x"),
        AddrOf(w[lit64(embedding)]),
      ]),
    ),
  )
  let tables = rope_tables(cfg)
  let program = @build.ordered_program(
    [Global(tables[0]), Global(tables[1])] +
    state.map(s => Global(s)) +
    [
      Func(rmsnorm_fn("rmsnorm_d", dim)),
      Func(matmul_fn("matmul_dd", dim, dim)),
      Func(matmul_fn("matmul_hd", hidden, dim)),
      Func(matmul_fn("matmul_dh", dim, hidden)),
      Func(matmul_fn("matmul_vd", cfg.vocab, dim)),
      Func(
        @build.func(
          Void,
          "forward",
          [
            @build.param(fptr, "w"),
            @build.param(SInt, "token"),
            @build.param(SInt, "pos"),
            @build.param(fptr, "logits"),
          ],
          body,
        ),
      ),
    ],
  )
  @printer.print_program(program)
}
