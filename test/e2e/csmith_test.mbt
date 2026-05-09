///|
priv struct CsmithConfig {
  csmith_command : String
  clang_command : String
  timeout_command : String
  kimicc_command : String?
  include_root : String?
  record_root : String
  bug_dir : String
}

///|
fn csmith_env(name : String) -> String? {
  match @env.get_env_var(name) {
    None | Some("") => None
    x => x
  }
}

///|
fn csmith_path_join(left : String, right : String) -> String {
  if left == "" {
    right
  } else if left.length() > 0 && left[left.length() - 1] == '/' {
    left + right
  } else {
    left + "/" + right
  }
}

///|
fn csmith_default_record_root() -> String {
  match csmith_env("KIMICC_CSMITH_RECORD_ROOT") {
    Some(root) => root
    None =>
      match csmith_env("TMPDIR") {
        Some(tmp) => csmith_path_join(tmp, "kimicc_csmith_records")
        None => ".kimicc_csmith_records"
      }
  }
}

///|
fn csmith_timeout_binary() -> String {
  match csmith_env("KIMICC_CSMITH_TIMEOUT") {
    Some(command) => command
    None =>
      if moonbit_system(@utf8.encode("command -v timeout >/dev/null 2>&1")) == 0 {
        "timeout"
      } else if moonbit_system(
          @utf8.encode("command -v gtimeout >/dev/null 2>&1"),
        ) ==
        0 {
        "gtimeout"
      } else {
        abort("timeout command missing from PATH")
      }
  }
}

///|
fn csmith_config() -> CsmithConfig {
  {
    csmith_command: csmith_env("KIMICC_CSMITH").unwrap_or("csmith"),
    clang_command: csmith_env("KIMICC_CSMITH_CLANG").unwrap_or("clang"),
    timeout_command: csmith_timeout_binary(),
    kimicc_command: csmith_env("KIMICC_CSMITH_KIMICC"),
    include_root: csmith_env("KIMICC_CSMITH_INCLUDE_ROOT"),
    record_root: csmith_default_record_root(),
    bug_dir: csmith_env("KIMICC_CSMITH_BUG_DIR").unwrap_or("test/bugs"),
  }
}

///|
const COMPILE_TIMEOUT_SEC : Int = 30

///|
const RUN_TIMEOUT_SEC : Int = 20

///|
const CASE_COUNT : Int = 20

///|
fn csmith_timed_out(code : Int) -> Bool {
  code == 124 || code == 137 || code == 143
}

///|
fn CsmithConfig::timed_command(
  self : CsmithConfig,
  cmd : String,
  timeout_seconds : Int,
) -> String {
  self.timeout_command +
  " --kill-after=2s " +
  timeout_seconds.to_string() +
  "s " +
  cmd
}

///|
fn csmith_log(tag : String, seed : Int, stage : String) -> Unit {
  println("csmith " + tag + " seed=" + seed.to_string() + " " + stage)
}

///|
fn csmith_compat_header_source() -> String {
  (
    #|extern double fabs(double);
    #|extern float fabsf(float);
    #|extern double ldexp(double, int);
    #|extern float ldexpf(float, int);
  )
}

///|
fn csmith_flags() -> String {
  "--concise --quiet --no-argc --no-float --no-packed-struct " +
  "--max-funcs 3 --max-block-depth 3 --max-block-size 3 " +
  "--max-expr-complexity 5 --max-array-dim 2 --max-array-len-per-dim 4"
}

///|
fn CsmithConfig::generate_command(
  self : CsmithConfig,
  seed : Int,
  source_path : String,
) -> String {
  shell_quote(self.csmith_command) +
  " --seed " +
  seed.to_string() +
  " " +
  csmith_flags() +
  " --output " +
  shell_quote(source_path)
}

///|
fn CsmithConfig::include_dir_word(self : CsmithConfig) -> String {
  match self.include_root {
    Some(root) => shell_quote(root)
    None =>
      "\"$(cmd=$(command -v " +
      shell_quote(self.csmith_command) +
      "); while test -L \"$cmd\"; do link=$(readlink \"$cmd\"); if test \"${link#/}\" != \"$link\"; then cmd=\"$link\"; else cmd=$(dirname \"$cmd\")/\"$link\"; fi; done; prefix=$(cd \"$(dirname \"$cmd\")/..\" && pwd); header=$(find \"$prefix/include\" -name csmith.h -type f | grep -v '/runtime/' | sed -n '1p'); if test -z \"$header\"; then header=$(find \"$prefix/include\" -name csmith.h -type f | sed -n '1p'); fi; dirname \"$header\")\""
  }
}

///|
fn CsmithConfig::include_description(self : CsmithConfig) -> String {
  match self.include_root {
    Some(root) => root
    None => "$(prefix-of-" + self.csmith_command + ")/include/**/csmith.h"
  }
}

///|
fn CsmithConfig::include_check_command(self : CsmithConfig) -> String {
  match self.include_root {
    Some(root) => "test -f " + shell_quote(csmith_path_join(root, "csmith.h"))
    None =>
      "include_dir=" +
      self.include_dir_word() +
      "; test -f \"$include_dir/csmith.h\""
  }
}

///|
fn CsmithConfig::preprocess_command(
  self : CsmithConfig,
  source_path : String,
  preprocessed_path : String,
  compat_path : String,
) -> String {
  shell_quote(self.clang_command) +
  " -w -E -P -DCSMITH_MINIMAL -I " +
  self.include_dir_word() +
  " -include " +
  shell_quote(compat_path) +
  " " +
  shell_quote(source_path) +
  " -o " +
  shell_quote(preprocessed_path)
}

///|
fn CsmithConfig::kimicc_compile_command(
  self : CsmithConfig,
  preprocessed_path : String,
) -> String {
  match self.kimicc_command {
    Some(command) => command + " " + shell_quote(preprocessed_path)
    None =>
      "moon run cmd/main --target native -- " + shell_quote(preprocessed_path)
  }
}

///|
fn csmith_command_available(command : String) -> Bool {
  moonbit_system(
    @utf8.encode("command -v " + shell_quote(command) + " >/dev/null 2>&1"),
  ) ==
  0
}

///|
fn require_csmith_toolchain(config : CsmithConfig) -> Unit {
  if !csmith_command_available(config.csmith_command) {
    abort("csmith command missing: " + config.csmith_command)
  }
  if !csmith_command_available(config.clang_command) {
    abort("clang command missing: " + config.clang_command)
  }
  if !csmith_command_available(config.timeout_command) {
    abort("timeout command missing: " + config.timeout_command)
  }
  if moonbit_system(@utf8.encode(config.include_check_command())) != 0 {
    abort("csmith include root missing: " + config.include_description())
  }
  match config.kimicc_command {
    Some(_) => ()
    None =>
      if !csmith_command_available("moon") {
        abort("moon command missing for default kimicc invocation")
      }
  }
}

///|
fn CsmithConfig::record_dir(
  self : CsmithConfig,
  tag : String,
  seed : Int,
) -> String {
  csmith_path_join(self.record_root, tag + "_" + seed.to_string())
}

///|
fn CsmithConfig::bug_case_path(
  self : CsmithConfig,
  seed : Int,
  stage_slug : String,
) -> String {
  csmith_path_join(
    self.bug_dir,
    "csmith_seed_" + seed.to_string() + "_" + stage_slug + ".c",
  )
}

///|
async fn CsmithConfig::save_bug_case(
  self : CsmithConfig,
  seed : Int,
  tag : String,
  preprocessed_path : String,
  stage_slug : String,
) -> String {
  run_command_checked(
    "mkdir -p " + shell_quote(self.bug_dir),
    "prepare csmith bug case dir",
  )
  let bug_path = self.bug_case_path(seed, stage_slug)
  write_text_file(bug_path, @fs.read_file(preprocessed_path).text())
  csmith_log(tag, seed, "saved " + bug_path)
  bug_path
}

///|
async fn CsmithConfig::record_failure(
  self : CsmithConfig,
  record_dir : String,
  seed : Int,
  tag : String,
  source_path : String,
  preprocessed_path : String,
  stage : String,
  details : String,
) -> Unit {
  run_command_checked(
    "mkdir -p " + shell_quote(record_dir),
    "prepare csmith failure record",
  )
  let kimicc_command = match self.kimicc_command {
    Some(command) => command
    None => "auto"
  }
  write_text_file(record_dir + "/source.c", @fs.read_file(source_path).text())
  write_text_file(
    record_dir + "/preprocessed.i",
    @fs.read_file(preprocessed_path).text(),
  )
  write_text_file(record_dir + "/compat.h", csmith_compat_header_source())
  write_text_file(
    record_dir + "/manifest.txt",
    "tag=" +
    tag +
    "\nseed=" +
    seed.to_string() +
    "\nstage=" +
    stage +
    "\ncsmith-flags=" +
    csmith_flags() +
    "\ncompile-timeout-seconds=" +
    COMPILE_TIMEOUT_SEC.to_string() +
    "\nrun-timeout-seconds=" +
    RUN_TIMEOUT_SEC.to_string() +
    "\npreprocess-flags=-w -E -P -DCSMITH_MINIMAL -I " +
    self.include_description() +
    " -include compat.h" +
    "\ncsmith-command=" +
    self.csmith_command +
    "\nclang-command=" +
    self.clang_command +
    "\ntimeout-command=" +
    self.timeout_command +
    "\nkimicc-command=" +
    kimicc_command +
    "\nrecord-root=" +
    self.record_root +
    "\nbug-dir=" +
    self.bug_dir +
    "\n\n" +
    details,
  )
}

///|
async fn CsmithConfig::record_abnormal_case(
  self : CsmithConfig,
  record_dir : String,
  seed : Int,
  tag : String,
  source_path : String,
  preprocessed_path : String,
  stage : String,
  stage_slug : String,
  details : String,
) -> String {
  let bug_path = self.save_bug_case(seed, tag, preprocessed_path, stage_slug)
  self.record_failure(
    record_dir,
    seed,
    tag,
    source_path,
    preprocessed_path,
    stage,
    details + "\nbug-case=" + bug_path + "\n",
  )
  stage +
  " seed=" +
  seed.to_string() +
  " bug=" +
  bug_path +
  " record=" +
  record_dir
}

///|
fn csmith_failure_message(
  record_dir : String,
  seed : Int,
  tag : String,
  stage : String,
) -> String {
  "csmith differential failure at " +
  stage +
  " for " +
  tag +
  " seed=" +
  seed.to_string() +
  "; recorded at " +
  record_dir
}

///|
async fn CsmithConfig::run_case(
  self : CsmithConfig,
  seed : Int,
  tag : String,
) -> String? {
  let source_path = temp_file_path(
    tag + "_csmith_source",
    seed.to_string(),
    ".c",
  )
  let preprocessed_path = temp_file_path(
    tag + "_csmith_preprocessed",
    seed.to_string(),
    ".i",
  )
  let compat_path = temp_file_path(
    tag + "_csmith_compat",
    seed.to_string(),
    ".h",
  )
  let kimicc_asm_path = temp_file_path(
    tag + "_csmith_kimicc",
    seed.to_string(),
    ".s",
  )
  let kimicc_bin_path = temp_file_path(
    tag + "_csmith_kimicc",
    seed.to_string(),
    "",
  )
  let clang_bin_path = temp_file_path(
    tag + "_csmith_clang",
    seed.to_string(),
    "",
  )
  let record_dir = self.record_dir(tag, seed)
  csmith_log(tag, seed, "start")
  csmith_log(tag, seed, "generate")
  write_text_file(compat_path, csmith_compat_header_source())
  run_command_checked(
    self.timed_command(
      self.generate_command(seed, source_path),
      COMPILE_TIMEOUT_SEC,
    ),
    "generate csmith " + tag,
  )
  csmith_log(tag, seed, "preprocess")
  run_command_checked(
    self.timed_command(
      self.preprocess_command(source_path, preprocessed_path, compat_path),
      COMPILE_TIMEOUT_SEC,
    ),
    "preprocess csmith " + tag,
  )
  csmith_log(tag, seed, "clang compile")
  let clang_compile = run_command_capture(
    self.timed_command(
      shell_quote(self.clang_command) +
      " -w -o " +
      shell_quote(clang_bin_path) +
      " " +
      shell_quote(preprocessed_path),
      COMPILE_TIMEOUT_SEC,
    ),
    tag + "_csmith_clang_compile",
  )
  if clang_compile.code != 0 {
    let stage = if csmith_timed_out(clang_compile.code) {
      "clang compile timeout"
    } else {
      "clang compile"
    }
    self.record_failure(
      record_dir,
      seed,
      tag,
      source_path,
      preprocessed_path,
      stage,
      "exit code=" +
      clang_compile.code.to_string() +
      "\n" +
      clang_compile.output,
    )
    csmith_log(
      tag,
      seed,
      "skip " + csmith_failure_message(record_dir, seed, tag, stage),
    )
    return None
  }
  csmith_log(tag, seed, "clang run")
  let clang_run = run_command_capture(
    self.timed_command(shell_quote(clang_bin_path), RUN_TIMEOUT_SEC),
    tag + "_csmith_clang_run",
  )
  if csmith_timed_out(clang_run.code) {
    self.record_failure(
      record_dir,
      seed,
      tag,
      source_path,
      preprocessed_path,
      "clang run timeout",
      "exit code=" + clang_run.code.to_string() + "\n" + clang_run.output,
    )
    write_text_file(record_dir + "/clang.out", clang_run.output)
    csmith_log(
      tag,
      seed,
      "skip " +
      csmith_failure_message(record_dir, seed, tag, "clang run timeout"),
    )
    return None
  }
  csmith_log(tag, seed, "kimicc compile")
  let kimicc_compile = run_command_capture(
    self.timed_command(
      self.kimicc_compile_command(preprocessed_path),
      COMPILE_TIMEOUT_SEC,
    ),
    tag + "_csmith_kimicc_compile",
  )
  if kimicc_compile.code != 0 {
    let stage = if csmith_timed_out(kimicc_compile.code) {
      "kimicc compile timeout"
    } else {
      "kimicc compile"
    }
    self.record_failure(
      record_dir,
      seed,
      tag,
      source_path,
      preprocessed_path,
      stage,
      "exit code=" +
      kimicc_compile.code.to_string() +
      "\n" +
      kimicc_compile.output,
    )
    let stage_slug = if csmith_timed_out(kimicc_compile.code) {
      "kimicc_compile_timeout"
    } else {
      "kimicc_compile"
    }
    return Some(
      self.record_abnormal_case(
        record_dir,
        seed,
        tag,
        source_path,
        preprocessed_path,
        stage,
        stage_slug,
        "exit code=" +
        kimicc_compile.code.to_string() +
        "\n" +
        kimicc_compile.output,
      ),
    )
  }
  write_text_file(kimicc_asm_path, kimicc_compile.output)
  csmith_log(tag, seed, "kimicc link")
  let kimicc_link = run_command_capture(
    self.timed_command(
      shell_quote(self.clang_command) +
      " -w -o " +
      shell_quote(kimicc_bin_path) +
      " " +
      shell_quote(kimicc_asm_path),
      COMPILE_TIMEOUT_SEC,
    ),
    tag + "_csmith_kimicc_link",
  )
  if kimicc_link.code != 0 {
    self.record_failure(
      record_dir,
      seed,
      tag,
      source_path,
      preprocessed_path,
      "kimicc link",
      "exit code=" + kimicc_link.code.to_string() + "\n" + kimicc_link.output,
    )
    write_text_file(record_dir + "/kimicc.s", kimicc_compile.output)
    return Some(
      self.record_abnormal_case(
        record_dir,
        seed,
        tag,
        source_path,
        preprocessed_path,
        "kimicc link",
        "kimicc_link",
        "exit code=" + kimicc_link.code.to_string() + "\n" + kimicc_link.output,
      ),
    )
  }
  csmith_log(tag, seed, "kimicc run")
  let kimicc_run = run_command_capture(
    self.timed_command(shell_quote(kimicc_bin_path), RUN_TIMEOUT_SEC),
    tag + "_csmith_kimicc_run",
  )
  if csmith_timed_out(kimicc_run.code) {
    self.record_failure(
      record_dir,
      seed,
      tag,
      source_path,
      preprocessed_path,
      "kimicc run timeout",
      "exit code=" + kimicc_run.code.to_string() + "\n" + kimicc_run.output,
    )
    write_text_file(record_dir + "/kimicc.s", kimicc_compile.output)
    write_text_file(record_dir + "/kimicc.out", kimicc_run.output)
    return Some(
      self.record_abnormal_case(
        record_dir,
        seed,
        tag,
        source_path,
        preprocessed_path,
        "kimicc run timeout",
        "kimicc_run_timeout",
        "exit code=" + kimicc_run.code.to_string() + "\n" + kimicc_run.output,
      ),
    )
  }
  if kimicc_run.code != clang_run.code || kimicc_run.output != clang_run.output {
    self.record_failure(
      record_dir,
      seed,
      tag,
      source_path,
      preprocessed_path,
      "runtime mismatch",
      "kimicc code=" +
      kimicc_run.code.to_string() +
      "\nkimicc output:\n" +
      kimicc_run.output +
      "\nclang code=" +
      clang_run.code.to_string() +
      "\nclang output:\n" +
      clang_run.output,
    )
    write_text_file(record_dir + "/kimicc.s", kimicc_compile.output)
    write_text_file(record_dir + "/clang.out", clang_run.output)
    write_text_file(record_dir + "/kimicc.out", kimicc_run.output)
    return Some(
      self.record_abnormal_case(
        record_dir,
        seed,
        tag,
        source_path,
        preprocessed_path,
        "runtime mismatch",
        "runtime_mismatch",
        "kimicc code=" +
        kimicc_run.code.to_string() +
        "\nkimicc output:\n" +
        kimicc_run.output +
        "\nclang code=" +
        clang_run.code.to_string() +
        "\nclang output:\n" +
        clang_run.output,
      ),
    )
  }
  csmith_log(tag, seed, "ok")
  None
}

///|
async test "external csmith fuzz differential matches clang when enabled" {
  guard external_testbed_enabled("csmith") else { return }
  let config = csmith_config()
  require_csmith_toolchain(config)
  let failures : Array[String] = []
  for case_index in 0..<CASE_COUNT {
    let seed = case_index * 101 + 7
    if config.run_case(seed, "csmith_fuzz_" + case_index.to_string())
      is Some(failure) {
      failures.push(failure)
    }
  }
  if failures.length() > 0 {
    let output = StringBuilder::new()
    output.write_string("csmith abnormal cases:\n")
    for failure in failures {
      output.write_string("- ")
      output.write_string(failure)
      output.write_char('\n')
    }
    abort(output.to_string())
  }
}
