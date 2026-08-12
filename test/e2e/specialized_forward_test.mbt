///|
/// The specialization experiment, end to end: a MoonBit generator emits a
/// transformer forward pass for one fixed configuration -- layers unrolled,
/// bounds literal, weight offsets baked, RoPE tables embedded -- and a
/// hand-written driver compiles it beside a generic runtime-dimension
/// reference, runs both over the same synthetic weights, and compares
/// logits position by position. The driver also times both; the ratio is
/// reported, not asserted, since CI machines vary.
async test "specialized forward pass matches the generic reference" {
  let cfg : @llama_forward.Config = {
    dim: 64,
    hidden: 176,
    n_layers: 2,
    n_heads: 4,
    n_kv_heads: 4,
    vocab: 256,
    seq: 64,
  }
  let forward = @llama_forward.generate_forward(cfg)
  let driver =
    #|#include <stdio.h>
    #|#include <stdlib.h>
    #|#include <math.h>
    #|#include <time.h>
    #|#define DIM 64
    #|#define HIDDEN 176
    #|#define LAYERS 2
    #|#define HEADS 4
    #|#define VOCAB 256
    #|#define SEQ 64
    #|#define HEAD (DIM / HEADS)
    #|static float gx[DIM], gxb[DIM], gxb2[DIM], ghb[HIDDEN], ghb2[HIDDEN];
    #|static float gq[DIM], gkc[LAYERS*SEQ*DIM], gvc[LAYERS*SEQ*DIM], gatt[SEQ];
    #|static void g_rmsnorm(float *o, const float *x, const float *w, int n) {
    #|  float ss = 0.0f;
    #|  for (int i = 0; i < n; i++) ss += x[i] * x[i];
    #|  ss = 1.0f / sqrtf(ss / (float)n + 1e-5f);
    #|  for (int i = 0; i < n; i++) o[i] = w[i] * (x[i] * ss);
    #|}
    #|static void g_matmul(float *o, const float *x, const float *w, int r, int c) {
    #|  for (int i = 0; i < r; i++) {
    #|    float acc = 0.0f;
    #|    for (int j = 0; j < c; j++) acc += w[i*c + j] * x[j];
    #|    o[i] = acc;
    #|  }
    #|}
    #|// Runtime dimensions, as a checkpoint-loading engine has them: assigned
    #|// in main from values clang cannot fold, so the generic path is honest.
    #|static int rdim, rhidden, rheads, rlayers, rvocab;
    #|static void g_forward(const float *w, int token, int pos, float *logits) {
    #|  const int dim = rdim, hidden = rhidden, head = rdim / rheads, half = head/2;
    #|  const long emb = 0;
    #|  const long L = rlayers, D = dim, H = hidden;
    #|  const long rms_att0 = (long)rvocab*D, wq0 = rms_att0 + L*D;
    #|  const long wk0 = wq0 + L*D*D, wv0 = wk0 + L*D*D, wo0 = wv0 + L*D*D;
    #|  const long rms_ffn0 = wo0 + L*D*D, w1_0 = rms_ffn0 + L*D;
    #|  const long w2_0 = w1_0 + L*D*H, w3_0 = w2_0 + L*H*D;
    #|  for (int i = 0; i < dim; i++) gx[i] = w[emb + (long)token*dim + i];
    #|  for (int l = 0; l < rlayers; l++) {
    #|    long rms_att = rms_att0 + l*D, wq = wq0 + (long)l*D*D;
    #|    long wk = wk0 + (long)l*D*D, wv = wv0 + (long)l*D*D;
    #|    long wo = wo0 + (long)l*D*D, rms_ffn = rms_ffn0 + l*D;
    #|    long w1 = w1_0 + (long)l*D*H, w2 = w2_0 + (long)l*H*D;
    #|    long w3 = w3_0 + (long)l*D*H;
    #|    g_rmsnorm(gxb, gx, w + rms_att, dim);
    #|    g_matmul(gq, gxb, w + wq, dim, dim);
    #|    g_matmul(gkc + l*SEQ*DIM + pos*dim, gxb, w + wk, dim, dim);
    #|    g_matmul(gvc + l*SEQ*DIM + pos*dim, gxb, w + wv, dim, dim);
    #|    for (int h = 0; h < rheads; h++) {
    #|      for (int k = 0; k < half; k++) {
    #|        int b = h*head + k*2;
    #|        float freq = 1.0f / powf(10000.0f, (float)(2*k) / (float)head);
    #|        float c = cosf(pos * freq), s = sinf(pos * freq);
    #|        float q0 = gq[b], q1 = gq[b+1];
    #|        gq[b] = q0*c - q1*s; gq[b+1] = q0*s + q1*c;
    #|        long kb = l*SEQ*DIM + pos*dim + b;
    #|        float k0 = gkc[kb], k1 = gkc[kb+1];
    #|        gkc[kb] = k0*c - k1*s; gkc[kb+1] = k0*s + k1*c;
    #|      }
    #|    }
    #|    for (int h = 0; h < rheads; h++) {
    #|      for (int p = 0; p <= pos; p++) {
    #|        float score = 0.0f;
    #|        for (int t = 0; t < head; t++)
    #|          score += gq[h*head + t] * gkc[l*SEQ*DIM + p*dim + h*head + t];
    #|        gatt[p] = score / sqrtf((float)head);
    #|      }
    #|      float mx = gatt[0];
    #|      for (int p = 1; p <= pos; p++) if (gatt[p] > mx) mx = gatt[p];
    #|      float sum = 0.0f;
    #|      for (int p = 0; p <= pos; p++) { gatt[p] = expf(gatt[p] - mx); sum += gatt[p]; }
    #|      for (int t = 0; t < head; t++) {
    #|        float val = 0.0f;
    #|        for (int p = 0; p <= pos; p++)
    #|          val += (gatt[p] / sum) * gvc[l*SEQ*DIM + p*dim + h*head + t];
    #|        gxb[h*head + t] = val;
    #|      }
    #|    }
    #|    g_matmul(gxb2, gxb, w + wo, dim, dim);
    #|    for (int i = 0; i < dim; i++) gx[i] += gxb2[i];
    #|    g_rmsnorm(gxb, gx, w + rms_ffn, dim);
    #|    g_matmul(ghb, gxb, w + w1, hidden, dim);
    #|    g_matmul(ghb2, gxb, w + w3, hidden, dim);
    #|    for (int i = 0; i < hidden; i++)
    #|      ghb[i] = ghb[i] / (1.0f + expf(-ghb[i])) * ghb2[i];
    #|    g_matmul(gxb2, ghb, w + w2, dim, hidden);
    #|    for (int i = 0; i < dim; i++) gx[i] += gxb2[i];
    #|  }
    #|  long rms_final = w3_0 + (long)rlayers*D*H;
    #|  g_rmsnorm(gx, gx, w + rms_final, dim);
    #|  g_matmul(logits, gx, w + emb, rvocab, dim);
    #|}
    #|int main(int argc, char **argv) {
    #|  (void)argv;
    #|  // argc is 1, but clang cannot prove it, so these stay runtime values.
    #|  rdim = DIM + (argc - 1);
    #|  rhidden = HIDDEN + (argc - 1);
    #|  rheads = HEADS + (argc - 1);
    #|  rlayers = LAYERS + (argc - 1);
    #|  rvocab = VOCAB + (argc - 1);
    #|  long total = (long)VOCAB*DIM + (long)LAYERS*DIM + 4L*LAYERS*DIM*DIM +
    #|    (long)LAYERS*DIM + 3L*LAYERS*DIM*HIDDEN + DIM + (long)SEQ*HEAD;
    #|  float *w = malloc(total * sizeof(float));
    #|  unsigned long long st = 42;
    #|  for (long i = 0; i < total; i++) {
    #|    st = st * 6364136223846793005ULL + 1442695040888963407ULL;
    #|    w[i] = ((float)((st >> 33) & 0xFFFF) / 65536.0f - 0.5f) * 0.2f;
    #|  }
    #|  float la[VOCAB], lb[VOCAB];
    #|  double worst = 0.0;
    #|  int token = 7;
    #|  for (int pos = 0; pos < 32; pos++) {
    #|    forward(w, token, pos, la);
    #|    g_forward(w, token, pos, lb);
    #|    for (int i = 0; i < VOCAB; i++) {
    #|      if (!isfinite(la[i]) || !isfinite(lb[i])) {
    #|        printf("nonfinite at pos=%d i=%d\n", pos, i);
    #|        return 2;
    #|      }
    #|      double d = fabs((double)la[i] - (double)lb[i]);
    #|      if (d > worst) worst = d;
    #|    }
    #|    token = (token * 31 + pos) % VOCAB;
    #|  }
    #|  printf("worst=%g\n", worst);
    #|  // Benchmark both over fresh positions.
    #|  struct timespec t0, t1;
    #|  clock_gettime(CLOCK_MONOTONIC, &t0);
    #|  for (int r = 0; r < 200; r++)
    #|    for (int pos = 0; pos < 32; pos++) forward(w, 7, pos, la);
    #|  clock_gettime(CLOCK_MONOTONIC, &t1);
    #|  double spec = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
    #|  clock_gettime(CLOCK_MONOTONIC, &t0);
    #|  for (int r = 0; r < 200; r++)
    #|    for (int pos = 0; pos < 32; pos++) g_forward(w, 7, pos, lb);
    #|  clock_gettime(CLOCK_MONOTONIC, &t1);
    #|  double gen = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
    #|  printf("specialized=%.3fs generic=%.3fs ratio=%.2fx\n", spec, gen, gen / spec);
    #|  free(w);
    #|  return worst < 1e-4 ? 0 : 1;
    #|}
  // The generated code calls libm, so its declarations come first.
  let source = "#include <math.h>\n" + forward + "\n" + driver
  let source_path = temp_file_path("specfwd", source, ".c")
  let bin_path = temp_file_path("specfwd_bin", source, "")
  write_text_file(source_path, source)
  run_command_checked(
    "clang -O2 -o " +
    shell_quote(bin_path) +
    " " +
    shell_quote(source_path) +
    " -lm",
    "compile specialized forward",
  )
  let result = run_command_capture(shell_quote(bin_path), "specfwd_run")
  println(result.output)
  assert_eq(result.code, 0)
  assert_true(result.output.contains("worst="))
}
