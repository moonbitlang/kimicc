///|
/// The ds4 referee: generated scalar kernels against ds4's own kernels,
/// bit for bit, in one translation unit -- ds4.c is included directly so
/// its static functions are callable, the pattern the llama2.c referee
/// established. Three layers:
///
///   - the baked IQ2_XXS sign table must memcmp-equal the table ds4
///     expands at runtime under pthread_once;
///   - random blocks: every generated kernel must return the identical
///     bit pattern to ds4's scalar kernel on the same bytes;
///   - real rows: weight rows mmap'd straight out of the 81GB
///     DeepSeek-V4-Flash GGUF, located by ds4's own loader, dotted
///     against random activations -- the layer that catches a layout
///     misread that self-generated random blocks structurally cannot.
///
/// Two builds of the same driver referee two different claims:
///
///   - strict (`-O1 -ffp-contract=off -U__ARM_FEATURE_DOTPROD`): the
///     generated arithmetic IS ds4's, bit for bit -- ds4's q8_0 fast
///     path steps aside for its own scalar fallback, no FMA contraction
///     on either side, so any deviation in layout or operation order
///     fails loudly;
///   - production (`-O3 -ffast-math -mcpu=native`, dotprod live): under
///     ds4's real flags the compiler reassociates float reductions and
///     bit-determinism is waived by definition, so the generated kernels
///     must agree within reassociation-level relative error (1e-4, two
///     orders above observed drift, four below a layout misread).
///
/// f16 scales are constrained finite: ds4 converts through hardware
/// vcvt, the generated code through the ported bit algorithm, and they
/// agree on every finite value.
///
/// The checkout and checkpoint are machine-local (~/git/ds4); the test
/// skips wherever they are absent, CI included.
async test "generated ds4 kernels match ds4 bit for bit" {
  // One command, so the redirect covers the whole probe: a && chain
  // would bind the capture to its last link only.
  // DS4_HOME overrides the checkout root's parent, for machines that keep
  // it elsewhere -- and it lets the skip branch itself be exercised
  // (DS4_HOME=/nonexistent) without disturbing $HOME, which moon needs.
  let have = run_command_capture(
    "ls \"${DS4_HOME:-$HOME}/git/ds4/ds4.c\" " +
    "\"${DS4_HOME:-$HOME}/git/ds4/ds4flash.gguf\" " +
    "\"${DS4_HOME:-$HOME}/git/ds4/ds4_distributed.o\" " +
    "\"${DS4_HOME:-$HOME}/git/ds4/ds4_tp.o\" " +
    "\"${DS4_HOME:-$HOME}/git/ds4/ds4_ssd.o\" " +
    "\"${DS4_HOME:-$HOME}/git/ds4/ds4_layer_pack.o\"",
    "ds4_present",
  )
  if have.code != 0 {
    println(
      "skipped: ~/git/ds4 checkout, its built objects, or ds4flash.gguf not present",
    )
    return
  }
  let home = run_command_capture("printf %s \"${DS4_HOME:-$HOME}\"", "home_dir")
  assert_eq(home.code, 0)
  let ds4_dir = home.output + "/git/ds4"
  // Widths from the real checkpoint: n_embd 4096 (q8_0 attention
  // projections and output head, IQ2_XXS gate/up experts), expert FFN
  // width 2048 (Q2_K down experts). 500 exercises the q8_0 short tail
  // block, 256 the minimal super-block kernels.
  let cfg : @ds4_kernels.Config = {
    q8_dims: [4096, 500],
    q2k_dims: [2048, 256],
    iq2_dims: [4096, 256],
  }
  let generated = @ds4_kernels.generate_kernels(cfg)
  let neon = @ds4_kernels.generate_q8_neon_kernels([4096, 256])
  let driver =
    #|
    #|/* ---- referee driver (hand-written) ---- */
    #|static uint64_t drv_state = 0x9E3779B97F4A7C15ull;
    #|static uint64_t drv_next(void) {
    #|    drv_state ^= drv_state << 13;
    #|    drv_state ^= drv_state >> 7;
    #|    drv_state ^= drv_state << 17;
    #|    return drv_state;
    #|}
    #|static float drv_float(void) {
    #|    return (float)((int64_t)(drv_next() & 0xFFFFFF) - 0x800000) / 8388608.0f;
    #|}
    #|static uint16_t drv_f16(void) {
    #|    uint16_t h = (uint16_t)drv_next();
    #|    if (((h >> 10) & 0x1F) == 0x1F) h ^= 0x0400; /* exponent 31 -> 30 */
    #|    return h;
    #|}
    #|/* DRV_TOL=0 compares bit patterns; a positive DRV_TOL accepts a
    #| * relative error up to that bound instead. The strict build proves
    #| * the generated arithmetic is ds4's exactly; the tolerance build
    #| * runs under ds4's own -O3 -ffast-math flags, where the compiler
    #| * reassociates float reductions and bit-determinism is waived by
    #| * definition, so agreement within reassociation-level error is the
    #| * strongest property that exists there. */
    #|#ifndef DRV_TOL
    #|#define DRV_TOL 0.0
    #|#define DRV_TOLERANT 0
    #|#else
    #|#define DRV_TOLERANT 1
    #|#endif
    #|static int drv_fails = 0;
    #|static void drv_check(const char *what, int trial, float got, float want) {
    #|    if (DRV_TOL > 0.0) {
    #|        double diff = fabs((double)got - (double)want);
    #|        if (diff / (fabs((double)want) + 1.0) > DRV_TOL) {
    #|            drv_fails++;
    #|            if (drv_fails <= 10)
    #|                printf("MISMATCH %s trial %d: got %.9g want %.9g rel %.3g\n",
    #|                       what, trial, (double)got, (double)want,
    #|                       diff / (fabs((double)want) + 1.0));
    #|        }
    #|        return;
    #|    }
    #|    uint32_t gb, wb;
    #|    memcpy(&gb, &got, 4);
    #|    memcpy(&wb, &want, 4);
    #|    if (gb != wb) {
    #|        drv_fails++;
    #|        if (drv_fails <= 10)
    #|            printf("MISMATCH %s trial %d: got %.9g (0x%08x) want %.9g (0x%08x)\n",
    #|                   what, trial, (double)got, gb, (double)want, wb);
    #|    }
    #|}
    #|static void drv_fill_q8_row(uint8_t *row, uint64_t blocks) {
    #|    for (uint64_t b = 0; b < blocks; b++) {
    #|        uint16_t s = drv_f16();
    #|        memcpy(row + b * 34, &s, 2);
    #|        for (int i = 0; i < 32; i++) row[b * 34 + 2 + i] = (uint8_t)drv_next();
    #|    }
    #|}
    #|static void drv_fill_q8_x(int8_t *xq, float *xscale, uint64_t blocks) {
    #|    for (uint64_t i = 0; i < blocks * 32; i++) xq[i] = (int8_t)drv_next();
    #|    for (uint64_t b = 0; b < blocks; b++) xscale[b] = drv_float();
    #|}
    #|/* The generated q8 kernels take `char *` quants -- the toolkit's
    #| * canonical spelling of SChar -- which is signed on this target. */
    #|typedef float (*drv_q8_fn)(unsigned char *, char *, float *);
    #|typedef float (*drv_f32_fn)(unsigned char *, float *);
    #|static void drv_test_q8(const char *what, uint64_t dim, drv_q8_fn gen) {
    #|    uint64_t blocks = (dim + 31) / 32;
    #|    uint8_t *row = malloc(blocks * 34);
    #|    int8_t *xq = malloc(blocks * 32);
    #|    float *xscale = malloc(blocks * sizeof(float));
    #|    for (int t = 0; t < 200; t++) {
    #|        drv_fill_q8_row(row, blocks);
    #|        drv_fill_q8_x(xq, xscale, blocks);
    #|        drv_check(what, t, gen(row, (char *)xq, xscale),
    #|                  dot_q8_0_row(row, xq, xscale, dim, blocks));
    #|    }
    #|    free(row); free(xq); free(xscale);
    #|}
    #|static void drv_fill_q2k(uint8_t *buf, uint64_t nb) {
    #|    for (uint64_t i = 0; i < nb * 84; i++) buf[i] = (uint8_t)drv_next();
    #|    for (uint64_t b = 0; b < nb; b++) {
    #|        uint16_t d = drv_f16(), m = drv_f16();
    #|        memcpy(buf + b * 84 + 80, &d, 2);
    #|        memcpy(buf + b * 84 + 82, &m, 2);
    #|    }
    #|}
    #|static void drv_test_q2k(const char *what, uint64_t dim, drv_f32_fn gen) {
    #|    uint64_t nb = dim / 256;
    #|    uint8_t *buf = malloc(nb * 84);
    #|    float *y = malloc(dim * sizeof(float));
    #|    for (int t = 0; t < 100; t++) {
    #|        drv_fill_q2k(buf, nb);
    #|        for (uint64_t i = 0; i < dim; i++) y[i] = drv_float();
    #|        drv_check(what, t, gen(buf, y),
    #|                  ds4_vec_dot_q2_K_f32((int)dim, (const block_q2_K *)buf, y));
    #|    }
    #|    free(buf); free(y);
    #|}
    #|static void drv_fill_iq2(uint8_t *buf, uint64_t nb) {
    #|    for (uint64_t i = 0; i < nb * 66; i++) buf[i] = (uint8_t)drv_next();
    #|    for (uint64_t b = 0; b < nb; b++) {
    #|        uint16_t d = drv_f16();
    #|        memcpy(buf + b * 66, &d, 2);
    #|    }
    #|}
    #|#if defined(__ARM_FEATURE_DOTPROD)
    #|/* The NEON kernels take int8_t quants and exist only when dotprod is
    #| * compiled in; ds4's dot_q8_0_row takes its own NEON path for widths
    #| * divisible by 32 under the same flags, so this comparison is
    #| * NEON-vs-NEON. */
    #|typedef float (*drv_q8n_fn)(unsigned char *, int8_t *, float *);
    #|static void drv_test_q8_neon(const char *what, uint64_t dim, drv_q8n_fn gen) {
    #|    uint64_t blocks = dim / 32;
    #|    uint8_t *row = malloc(blocks * 34);
    #|    int8_t *xq = malloc(blocks * 32);
    #|    float *xscale = malloc(blocks * sizeof(float));
    #|    for (int t = 0; t < 200; t++) {
    #|        drv_fill_q8_row(row, blocks);
    #|        drv_fill_q8_x(xq, xscale, blocks);
    #|        drv_check(what, t, gen(row, xq, xscale),
    #|                  dot_q8_0_row(row, xq, xscale, dim, blocks));
    #|    }
    #|    free(row); free(xq); free(xscale);
    #|}
    #|static void drv_real_rows_neon(ds4_model *m, const char *name,
    #|                               uint64_t want_dim, drv_q8n_fn gen) {
    #|    ds4_tensor *t = model_find_tensor(m, name);
    #|    if (!t || t->type != DS4_TENSOR_Q8_0 || t->dim[0] != want_dim) {
    #|        printf("UNEXPECTED tensor for neon rows: %s\n", name);
    #|        drv_fails++;
    #|        return;
    #|    }
    #|    uint64_t blocks = want_dim / 32;
    #|    uint64_t row_bytes = blocks * 34;
    #|    uint64_t rows = t->bytes / row_bytes;
    #|    int8_t *xq = malloc(blocks * 32);
    #|    float *xscale = malloc(blocks * sizeof(float));
    #|    for (int i = 0; i < 8; i++) {
    #|        uint64_t r = drv_next() % rows;
    #|        const uint8_t *row = m->map + t->abs_offset + r * row_bytes;
    #|        drv_fill_q8_x(xq, xscale, blocks);
    #|        drv_check(name, (int)r, gen((unsigned char *)row, xq, xscale),
    #|                  dot_q8_0_row(row, xq, xscale, want_dim, blocks));
    #|    }
    #|    free(xq); free(xscale);
    #|    printf("%s: neon, %llu rows, 8 sampled\n", name,
    #|           (unsigned long long)rows);
    #|}
    #|#if DRV_TOLERANT
    #|static double drv_now(void) {
    #|    struct timespec ts;
    #|    clock_gettime(CLOCK_MONOTONIC, &ts);
    #|    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
    #|}
    #|/* Cache-hot single-row bench: measures kernel compute, not memory
    #| * bandwidth. Informational only; the referee's pass/fail never
    #| * depends on it. */
    #|static void drv_bench(void) {
    #|    enum { DIM = 4096, BLOCKS = 128, ITERS = 200000 };
    #|    uint8_t *row = malloc(BLOCKS * 34);
    #|    int8_t *xq = malloc(BLOCKS * 32);
    #|    float *xscale = malloc(BLOCKS * sizeof(float));
    #|    drv_fill_q8_row(row, BLOCKS);
    #|    drv_fill_q8_x(xq, xscale, BLOCKS);
    #|    /* The row mutates every iteration: the calls are pure over their
    #|     * inputs, and with -O3 an invariant call is hoisted out of the
    #|     * loop, timing nothing. The XOR touches a quant byte, never the
    #|     * f16 scales, and costs the same in all three loops. */
    #|    volatile float sink = 0;
    #|    for (int i = 0; i < 20000; i++) {
    #|        row[2 + (uint64_t)i % 32] ^= 1;
    #|        sink += dot_q8_0_row(row, xq, xscale, DIM, BLOCKS);
    #|    }
    #|    double t0 = drv_now();
    #|    for (int i = 0; i < ITERS; i++) {
    #|        row[2 + (uint64_t)i % 32] ^= 1;
    #|        sink += dot_q8_0_row(row, xq, xscale, DIM, BLOCKS);
    #|    }
    #|    double t1 = drv_now();
    #|    for (int i = 0; i < ITERS; i++) {
    #|        row[2 + (uint64_t)i % 32] ^= 1;
    #|        sink += gen_dot_q8_0_row_4096(row, (char *)xq, xscale);
    #|    }
    #|    double t2 = drv_now();
    #|    for (int i = 0; i < ITERS; i++) {
    #|        row[2 + (uint64_t)i % 32] ^= 1;
    #|        sink += gen_dot_q8_0_row_neon_4096(row, xq, xscale);
    #|    }
    #|    double t3 = drv_now();
    #|    printf("bench dim=4096 cache-hot ns/call: ds4=%.1f gen_scalar=%.1f gen_neon=%.1f (sink=%g)\n",
    #|           (t1 - t0) / ITERS * 1e9, (t2 - t1) / ITERS * 1e9,
    #|           (t3 - t2) / ITERS * 1e9, (double)sink);
    #|    free(row); free(xq); free(xscale);
    #|}
    #|#endif
    #|#endif
    #|static void drv_test_iq2(const char *what, uint64_t dim, drv_f32_fn gen) {
    #|    uint64_t nb = dim / 256;
    #|    uint8_t *buf = malloc(nb * 66);
    #|    float *y = malloc(dim * sizeof(float));
    #|    for (int t = 0; t < 100; t++) {
    #|        drv_fill_iq2(buf, nb);
    #|        for (uint64_t i = 0; i < dim; i++) y[i] = drv_float();
    #|        drv_check(what, t, gen(buf, y),
    #|                  ds4_vec_dot_iq2_xxs_f32((int)dim, (const block_iq2_xxs *)buf, y));
    #|    }
    #|    free(buf); free(y);
    #|}
    #|static void drv_real_rows(ds4_model *m, const char *name, uint32_t want_type,
    #|                          uint64_t want_dim, int kind, drv_q8_fn genq8,
    #|                          drv_f32_fn genf) {
    #|    ds4_tensor *t = model_find_tensor(m, name);
    #|    if (!t) { printf("MISSING tensor %s\n", name); drv_fails++; return; }
    #|    if (t->type != want_type || t->dim[0] != want_dim) {
    #|        printf("UNEXPECTED %s: type %u dim0 %llu\n", name,
    #|               (unsigned)t->type, (unsigned long long)t->dim[0]);
    #|        drv_fails++;
    #|        return;
    #|    }
    #|    uint64_t row_bytes = kind == 0 ? want_dim / 32 * 34
    #|                       : kind == 1 ? want_dim / 256 * 84
    #|                                   : want_dim / 256 * 66;
    #|    if (t->bytes % row_bytes) {
    #|        printf("ODD byte count for %s\n", name);
    #|        drv_fails++;
    #|        return;
    #|    }
    #|    uint64_t rows = t->bytes / row_bytes;
    #|    uint64_t blocks = (want_dim + 31) / 32;
    #|    int8_t *xq = malloc(blocks * 32);
    #|    float *xscale = malloc(blocks * sizeof(float));
    #|    float *y = malloc(want_dim * sizeof(float));
    #|    for (int i = 0; i < 8; i++) {
    #|        uint64_t r = drv_next() % rows;
    #|        const uint8_t *row = m->map + t->abs_offset + r * row_bytes;
    #|        if (kind == 0) {
    #|            drv_fill_q8_x(xq, xscale, blocks);
    #|            drv_check(name, (int)r, genq8((unsigned char *)row, (char *)xq, xscale),
    #|                      dot_q8_0_row(row, xq, xscale, want_dim, blocks));
    #|        } else {
    #|            for (uint64_t k = 0; k < want_dim; k++) y[k] = drv_float();
    #|            if (kind == 1)
    #|                drv_check(name, (int)r, genf((unsigned char *)row, y),
    #|                          ds4_vec_dot_q2_K_f32((int)want_dim, (const block_q2_K *)row, y));
    #|            else
    #|                drv_check(name, (int)r, genf((unsigned char *)row, y),
    #|                          ds4_vec_dot_iq2_xxs_f32((int)want_dim, (const block_iq2_xxs *)row, y));
    #|        }
    #|    }
    #|    free(xq); free(xscale); free(y);
    #|    printf("%s: %llu rows, 8 sampled\n", name, (unsigned long long)rows);
    #|}
    #|int main(int argc, char **argv) {
    #|    if (DRV_TOL > 0.0) printf("mode: tolerance %g\n", (double)DRV_TOL);
    #|    else printf("mode: bit-exact\n");
    #|    iq2xxs_signed_grid_init();
    #|    if (memcmp(gen_iq2xxs_signed_grid, iq2xxs_signed_grid,
    #|               sizeof(iq2xxs_signed_grid)) != 0) {
    #|        printf("MISMATCH baked sign table\n");
    #|        drv_fails++;
    #|    } else {
    #|        printf("sign table: identical (%zu bytes)\n",
    #|               sizeof(iq2xxs_signed_grid));
    #|    }
    #|#ifndef DRV_SKIP_SCALAR
    #|    drv_test_q8("q8/4096", 4096, gen_dot_q8_0_row_4096);
    #|    drv_test_q8("q8/500", 500, gen_dot_q8_0_row_500);
    #|    drv_test_q2k("q2k/2048", 2048, gen_dot_q2_K_2048);
    #|    drv_test_q2k("q2k/256", 256, gen_dot_q2_K_256);
    #|    drv_test_iq2("iq2/4096", 4096, gen_dot_iq2_xxs_4096);
    #|    drv_test_iq2("iq2/256", 256, gen_dot_iq2_xxs_256);
    #|#endif
    #|#if defined(__ARM_FEATURE_DOTPROD)
    #|    drv_test_q8_neon("q8neon/4096", 4096, gen_dot_q8_0_row_neon_4096);
    #|    drv_test_q8_neon("q8neon/256", 256, gen_dot_q8_0_row_neon_256);
    #|#endif
    #|    if (argc > 1) {
    #|        ds4_model model;
    #|        model_open(&model, argv[1], false, false);
    #|#ifndef DRV_SKIP_SCALAR
    #|        drv_real_rows(&model, "output.weight", DS4_TENSOR_Q8_0, 4096, 0,
    #|                      gen_dot_q8_0_row_4096, 0);
    #|        drv_real_rows(&model, "blk.10.ffn_down_exps.weight", DS4_TENSOR_Q2_K,
    #|                      2048, 1, 0, gen_dot_q2_K_2048);
    #|        drv_real_rows(&model, "blk.10.ffn_gate_exps.weight", DS4_TENSOR_IQ2_XXS,
    #|                      4096, 2, 0, gen_dot_iq2_xxs_4096);
    #|#endif
    #|#if defined(__ARM_FEATURE_DOTPROD)
    #|        drv_real_rows_neon(&model, "output.weight", 4096,
    #|                           gen_dot_q8_0_row_neon_4096);
    #|#endif
    #|    } else {
    #|        printf("no model path: real-row layer skipped\n");
    #|    }
    #|#if defined(__ARM_FEATURE_DOTPROD) && DRV_TOLERANT
    #|    drv_bench();
    #|#endif
    #|    printf("failures=%d\n", drv_fails);
    #|    return drv_fails ? 1 : 0;
    #|}
  let source = "#include \"ds4.c\"\n" + generated + "\n" + driver
  let source_path = temp_file_path("ds4_referee", source, ".c")
  let bin_path = temp_file_path("ds4_referee_bin", source, "")
  write_text_file(source_path, source)
  // The NEON referee's source carries the intrinsics kernels as well; it
  // is compiled only with dotprod available, where ds4's own fast path
  // is also live.
  let source_neon = "#include \"ds4.c\"\n" +
    generated +
    "\n" +
    neon +
    "\n" +
    driver
  let source_neon_path = temp_file_path("ds4_referee_neon", source_neon, ".c")
  let bin_neon_path = temp_file_path("ds4_referee_neon_bin", source_neon, "")
  write_text_file(source_neon_path, source_neon)
  // ds4.c's session layer references its sibling translation units; the
  // checkout's own objects satisfy them, the same four ds4's CPU
  // test-hooks target links. None of the compared kernels live there.
  let siblings = [
      "ds4_distributed.o", "ds4_tp.o", "ds4_ssd.o", "ds4_layer_pack.o",
    ]
    .map(o => shell_quote(ds4_dir + "/" + o))
    .join(" ")
  run_command_checked(
    "clang -O1 -ffp-contract=off -U__ARM_FEATURE_DOTPROD -D_GNU_SOURCE " +
    "-DDS4_NO_GPU -DDS4_TEST_HOOKS -I " +
    shell_quote(ds4_dir) +
    " -o " +
    bin_path +
    " " +
    source_path +
    " " +
    siblings +
    " -lm -lpthread",
    "compile ds4 referee",
  )
  let result = run_command_capture(
    bin_path + " " + shell_quote(ds4_dir + "/ds4flash.gguf"),
    "ds4_referee_run",
  )
  println(result.output)
  assert_eq(result.code, 0)
  assert_true(result.output.contains("failures=0"))
  // NEON referee, native strict flags: dotprod live on both sides, no
  // fast-math and no contraction, so generated-NEON vs ds4-NEON is held
  // to bit equality -- the same standard the scalar referee sets, one
  // instruction set up. Scalar comparisons are skipped in this binary:
  // ds4's q8 dot takes its NEON path here, which is not the scalar
  // kernels' tree.
  run_command_checked(
    "clang -O2 -ffp-contract=off -mcpu=native -D_GNU_SOURCE " +
    "-DDS4_NO_GPU -DDS4_TEST_HOOKS -DDRV_SKIP_SCALAR -I " +
    shell_quote(ds4_dir) +
    " -o " +
    bin_neon_path +
    " " +
    source_neon_path +
    " " +
    siblings +
    " -lm -lpthread",
    "compile ds4 NEON referee",
  )
  let neon_result = run_command_capture(
    bin_neon_path + " " + shell_quote(ds4_dir + "/ds4flash.gguf"),
    "ds4_referee_neon_run",
  )
  println(neon_result.output)
  assert_eq(neon_result.code, 0)
  assert_true(neon_result.output.contains("failures=0"))
  // Second referee, ds4's own production flags: -O3 -ffast-math with the
  // NEON dotprod fast paths live. Fast-math licenses the compiler to
  // reassociate float reductions, so no C source is bit-deterministic
  // there -- the same driver compares within reassociation-level relative
  // error instead (codex measured 369 bit mismatches when this build was
  // held to bit equality; observed drift is ~1e-6, the bound is 1e-4,
  // and a layout misread is O(1)). This is the numeric standard the L3
  // drop-in referee inherits: tolerance plus token agreement, not bits.
  let bin_fast_path = temp_file_path("ds4_referee_fast_bin", source_neon, "")
  run_command_checked(
    "clang -O3 -ffast-math -fno-finite-math-only -mcpu=native -D_GNU_SOURCE " +
    "-DDS4_NO_GPU -DDS4_TEST_HOOKS -DDRV_TOL=1e-4 -I " +
    shell_quote(ds4_dir) +
    " -o " +
    bin_fast_path +
    " " +
    source_neon_path +
    " " +
    siblings +
    " -lm -lpthread",
    "compile ds4 production-flags referee",
  )
  let fast_result = run_command_capture(
    bin_fast_path + " " + shell_quote(ds4_dir + "/ds4flash.gguf"),
    "ds4_referee_fast_run",
  )
  println(fast_result.output)
  assert_eq(fast_result.code, 0)
  assert_true(fast_result.output.contains("failures=0"))
}
