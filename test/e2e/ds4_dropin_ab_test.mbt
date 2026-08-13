///|
/// The L3 referee: generated NEON q8_0 kernels dropped into ds4's own
/// engine, A/B'd with ds4-bench on the real 81GB checkpoint. Two source
/// trees are built identically -- stock, and patched so `dot_q8_0_row`
/// dispatches the model's four q8_0 widths (1024/2048/4096/8192: q/kv
/// projections, shared experts, output head) to the generated kernels,
/// everything else falling through to ds4's original body. The seam is
/// the function boundary; ds4's callers, threading, and layout are
/// untouched.
///
/// The numeric referee is the frontier-logits dump on an identical
/// 256-token prefix: every logit over the 129,280-token vocabulary must
/// agree within 0.5 absolute and the argmax must match. The dump lands
/// after prefill, whose q8 traffic is mostly width 4096 -- so this
/// comparison proves integration, not per-width numerics. Width
/// attribution is the job of `ds4_kernels_real_test.mbt`, which holds
/// every dispatched width (1024/2048/4096/8192) to bit equality against
/// ds4's own kernel individually; the coverage counters below then prove
/// each width actually routes through the generated code in this
/// workload. When this test
/// first ran (2026-08-13) the logits were bit-identical -- the intrinsic
/// sequence pins the arithmetic even under ds4's -ffast-math -- and a
/// canary build with a deliberately broken width-4096 kernel moved the
/// argmax and 39 logit units, proving the dispatch executes. The
/// tolerance exists so a future compiler that schedules the two builds
/// differently reports drift instead of a false alarm.
///
/// Throughput from the same runs prints for the record; decode here is
/// dominated by the IQ2_XXS/Q2_K expert matvecs the generator does not
/// cover yet, so parity -- not speedup -- is the expected honest result
/// for the q8_0 slice.
///
/// Runs only where the ds4 checkout and checkpoint live; skips in CI.
async test "generated kernels drop into ds4-bench and agree on real logits" {
  let have = run_command_capture(
    "ls \"${DS4_HOME:-$HOME}/git/ds4/ds4.c\" " +
    "\"${DS4_HOME:-$HOME}/git/ds4/ds4flash.gguf\" " +
    "\"${DS4_HOME:-$HOME}/git/ds4/Makefile\" " +
    "\"${DS4_HOME:-$HOME}/git/ds4/tests/long_context_story_prompt.txt\"",
    "ds4_ab_present",
  )
  if have.code != 0 {
    println("skipped: ~/git/ds4 checkout or ds4flash.gguf not present")
    return
  }
  let home = run_command_capture("printf %s \"${DS4_HOME:-$HOME}\"", "ab_home")
  assert_eq(home.code, 0)
  let ds4_dir = home.output + "/git/ds4"
  let neon = @ds4_kernels.generate_q8_neon_kernels([1024, 2048, 4096, 8192])
  let kernels_path = temp_file_path("ds4_ab_kernels", neon, ".c")
  write_text_file(kernels_path, neon)
  let stock = "/tmp/kimicc_ds4_ab_stock"
  let patched = "/tmp/kimicc_ds4_ab_patched"
  let coverage = "/tmp/kimicc_ds4_ab_coverage"
  // Fresh trees every run: rsync --delete protects excluded paths, so a
  // stale object from a previous ds4 revision could otherwise link into
  // one side of a supposedly identical A/B.
  run_command_checked(
    "rm -rf " + stock + " " + patched + " " + coverage,
    "clear previous A/B trees",
  )
  let sync_excludes = "--exclude .git --exclude gguf --exclude '*.gguf' " +
    "--exclude '*.o' --exclude build.log --exclude run.log " +
    "--exclude csv.out --exclude logits"
  run_command_checked(
    "rsync -a --delete " +
    sync_excludes +
    " " +
    shell_quote(ds4_dir) +
    "/ " +
    stock +
    "/",
    "sync stock ds4 tree",
  )
  run_command_checked(
    "rsync -a --delete " + sync_excludes + " " + stock + "/ " + patched + "/",
    "sync patched ds4 tree",
  )
  run_command_checked(
    "python3 scripts/ds4-dropin-patch.py " +
    patched +
    "/ds4.c " +
    kernels_path +
    " 1024 2048 4096 8192",
    "patch ds4.c with generated kernels",
  )
  run_command_checked(
    "rsync -a " + sync_excludes + " " + stock + "/ " + coverage + "/",
    "sync coverage ds4 tree",
  )
  run_command_checked(
    "python3 scripts/ds4-dropin-patch.py --count " +
    coverage +
    "/ds4.c " +
    kernels_path +
    " 1024 2048 4096 8192",
    "patch coverage ds4.c with hit counters",
  )
  run_command_checked(
    "make -C " + stock + " cpu -j12 > " + stock + "/build.log 2>&1",
    "build stock ds4",
  )
  run_command_checked(
    "make -C " + patched + " cpu -j12 > " + patched + "/build.log 2>&1",
    "build patched ds4",
  )
  let bench_args = " --cpu -t 16 -m " +
    shell_quote(ds4_dir + "/ds4flash.gguf") +
    " --prompt-file tests/long_context_story_prompt.txt" +
    " --ctx-start 256 --ctx-max 256 --gen-tokens 8" +
    " --csv csv.out --dump-frontier-logits-dir logits"
  // The coverage build proves the dispatch executes for every width in
  // this workload -- the logits equality alone cannot distinguish
  // correct generated execution from silent fallthrough to ds4's own
  // code. Counters live only here, so the timed A/B stays clean. It
  // also runs FIRST: it touches the same weight pages as the timed
  // runs, so on a cold machine it is the unrecorded warmup -- otherwise
  // stock-before-patched would hand the patched run a page cache the
  // stock run paid for.
  run_command_checked(
    "make -C " + coverage + " cpu -j12 > " + coverage + "/build.log 2>&1",
    "build coverage ds4",
  )
  run_command_checked(
    "cd " +
    coverage +
    " && mkdir -p logits && ./ds4-bench" +
    " --cpu -t 16 -m " +
    shell_quote(ds4_dir + "/ds4flash.gguf") +
    " --prompt-file tests/long_context_story_prompt.txt" +
    " --ctx-start 256 --ctx-max 256 --gen-tokens 2" +
    " --csv csv.out --dump-frontier-logits-dir logits" +
    " > run.log 2>&1",
    "run coverage ds4-bench",
  )
  let hits = run_command_capture(
    "grep kimicc_hits " + coverage + "/run.log",
    "ds4_ab_hits",
  )
  println(hits.output)
  assert_eq(hits.code, 0)
  let zero_hit = run_command_capture(
    "grep -E 'kimicc_hits.*=0( |$)' " + coverage + "/run.log",
    "ds4_ab_zero_hit",
  )
  // grep finding a `=0` count means some width never dispatched.
  assert_eq(zero_hit.code, 1)
  run_command_checked(
    "cd " +
    stock +
    " && mkdir -p logits && ./ds4-bench" +
    bench_args +
    " > run.log 2>&1",
    "run stock ds4-bench",
  )
  run_command_checked(
    "cd " +
    patched +
    " && mkdir -p logits && ./ds4-bench" +
    bench_args +
    " > run.log 2>&1",
    "run patched ds4-bench",
  )
  let compare = run_command_capture(
    "python3 -c \"" +
    "import json; " +
    "a = json.load(open('" +
    stock +
    "/logits/frontier_000256.logits.json')); " +
    "b = json.load(open('" +
    patched +
    "/logits/frontier_000256.logits.json')); " +
    "mx = max(abs(x - y) for x, y in zip(a['logits'], b['logits'])); " +
    "same = a['argmax_id'] == b['argmax_id']; " +
    "print('argmax stock=%d patched=%d max_abs_diff=%.6g' % (a['argmax_id'], b['argmax_id'], mx)); " +
    "exit(0 if same and mx < 0.5 else 1)\"",
    "ds4_ab_compare",
  )
  println(compare.output)
  let stock_csv = run_command_capture("cat " + stock + "/csv.out", "stock_csv")
  let patched_csv = run_command_capture(
    "cat " + patched + "/csv.out",
    "patched_csv",
  )
  println("stock:   " + stock_csv.output)
  println("patched: " + patched_csv.output)
  assert_eq(compare.code, 0)
}
