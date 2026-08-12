///|
/// The real-model referee: the generated engine against llama2.c's own
/// `forward` on the stories15M checkpoint. Both run in one binary -- run.c
/// is included with its entry points renamed -- and greedy decoding from BOS
/// must produce the identical token sequence, with a logit bound on every
/// step. This is the check the synthetic differential cannot be: the
/// reference here is an independent implementation on real weights.
///
/// The checkpoint is 60MB and not fetched by CI; the test skips when
/// `.repos/stories15M.bin` is absent and runs wherever it exists.
async test "generated engine matches llama2.c on stories15M" {
  // A single command, so the capture's output redirect applies to it as a
  // whole: a `&&` chain would bind the redirect to its last link only, and
  // the absent case would produce no output file at all.
  let have = run_command_capture(
    "ls .repos/stories15M.bin .repos/llama2.c/run.c",
    "real_model_present",
  )
  if have.code != 0 {
    println("skipped: .repos/stories15M.bin or llama2.c not present")
    return
  }
  let cfg : @llama_forward.Config = {
    dim: 288,
    hidden: 768,
    n_layers: 6,
    n_heads: 6,
    n_kv_heads: 6,
    vocab: 32000,
    seq: 256,
  }
  let forward = @llama_forward.generate_forward(cfg)
  let driver =
    #|// llama2.c, single-TU, entry points renamed out of the way.
    #|#define main ref_main
    #|#define forward ref_forward
    #|#include "run.c"
    #|#undef forward
    #|#undef main
    #|extern void forward(float *w, int token, int pos, float *logits);
    #|static int argmax_v(const float *v, int n) {
    #|  int best = 0;
    #|  for (int i = 1; i < n; i++) if (v[i] > v[best]) best = i;
    #|  return best;
    #|}
    #|int main(void) {
    #|  Transformer t;
    #|  build_transformer(&t, ".repos/stories15M.bin");
    #|  // Weights begin after the seven-int header.
    #|  float *w = (float *)t.data + 7;
    #|  static float mine[32000];
    #|  int token = 1; // BOS
    #|  double worst = 0.0;
    #|  int mismatches = 0;
    #|  for (int pos = 0; pos < 64; pos++) {
    #|    float *ref = ref_forward(&t, token, pos);
    #|    forward(w, token, pos, mine);
    #|    for (int i = 0; i < 32000; i++) {
    #|      if (!isfinite(mine[i]) || !isfinite(ref[i])) {
    #|        printf("nonfinite at pos=%d i=%d\n", pos, i);
    #|        return 2;
    #|      }
    #|      double d = fabs((double)mine[i] - (double)ref[i]);
    #|      if (d > worst) worst = d;
    #|    }
    #|    int a = argmax_v(mine, 32000), b = argmax_v(ref, 32000);
    #|    if (a != b) {
    #|      mismatches++;
    #|      printf("argmax mismatch at pos=%d: %d vs %d\n", pos, a, b);
    #|    }
    #|    token = b;
    #|  }
    #|  printf("worst=%g mismatches=%d\n", worst, mismatches);
    #|  return mismatches == 0 && worst < 1e-3 ? 0 : 1;
    #|}
  let source = "#include <math.h>\n" + forward + "\n" + driver
  let source_path = temp_file_path("real_forward", source, ".c")
  let bin_path = temp_file_path("real_forward_bin", source, "")
  write_text_file(source_path, source)
  run_command_checked(
    "clang -O2 -I .repos/llama2.c -o " + bin_path + " " + source_path + " -lm",
    "compile real-model referee",
  )
  let result = run_command_capture(bin_path, "real_forward_run")
  println(result.output)
  assert_eq(result.code, 0)
  assert_true(result.output.contains("mismatches=0"))
}
