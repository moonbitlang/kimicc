///|
#borrow(path, content)
extern "c" fn moonbit_write_file(path : Bytes, content : Bytes) -> Int = "moonbit_write_file"

///|
#borrow(cmd)
extern "c" fn moonbit_system(cmd : Bytes) -> Int = "moonbit_system"

///|
extern "c" fn moonbit_flush_stdout() -> Unit = "moonbit_flush_stdout"

///|
pub(all) struct Config {
  csmith_command : String
  clang_command : String
  timeout_command : String
  kimicc_command : String?
  include_root : String?
  record_root : String
  bug_dir : String
}

///|
pub(all) struct BatchResult {
  failures : Array[String]
}

///|
priv struct CommandResult {
  code : Int
  output : String
}

///|
fn env(name : String) -> String? {
  match @env.get_env_var(name) {
    None | Some("") => None
    x => x
  }
}

///|
fn path_join(left : String, right : String) -> String {
  if left == "" {
    right
  } else if left.length() > 0 && left[left.length() - 1] == '/' {
    left + right
  } else {
    "\{left}/\{right}"
  }
}

///|
fn default_record_root() -> String {
  match env("KIMICC_CSMITH_RECORD_ROOT") {
    Some(root) => root
    None =>
      match env("TMPDIR") {
        Some(tmp) => path_join(tmp, "kimicc_csmith_records")
        None => ".kimicc_csmith_records"
      }
  }
}

///|
fn timeout_binary() -> String {
  match env("KIMICC_CSMITH_TIMEOUT") {
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
pub fn config_from_env() -> Config {
  {
    csmith_command: env("KIMICC_CSMITH").unwrap_or("csmith"),
    clang_command: env("KIMICC_CSMITH_CLANG").unwrap_or("clang"),
    timeout_command: timeout_binary(),
    kimicc_command: env("KIMICC_CSMITH_KIMICC"),
    include_root: env("KIMICC_CSMITH_INCLUDE_ROOT"),
    record_root: default_record_root(),
    bug_dir: env("KIMICC_CSMITH_BUG_DIR").unwrap_or("test/bugs"),
  }
}

///|
pub const DEFAULT_SEED : Int = 7

///|
pub const DEFAULT_COUNT : Int = 20

///|
const COMPILE_TIMEOUT_SEC : Int = 30

///|
const RUN_TIMEOUT_SEC : Int = 20

///|
fn timed_out(code : Int) -> Bool {
  code == 124 || code == 137 || code == 143
}

///|
fn Config::timed_command(
  self : Config,
  cmd : String,
  timeout_seconds : Int,
) -> String {
  "\{self.timeout_command} --kill-after=2s \{timeout_seconds}s \{cmd}"
}

///|
fn log(tag : String, seed : Int, stage : String) -> Unit {
  println("csmith \{tag} seed=\{seed} \{stage}")
  moonbit_flush_stdout()
}

///|
fn compat_header_source() -> String {
  (
    #|extern double fabs(double);
    #|extern float fabsf(float);
    #|extern double ldexp(double, int);
    #|extern float ldexpf(float, int);
  )
}

///|
fn flags() -> String {
  "--concise --quiet --no-argc --no-float --no-packed-struct " +
  "--max-funcs 3 --max-block-depth 3 --max-block-size 3 " +
  "--max-expr-complexity 5 --max-array-dim 2 --max-array-len-per-dim 4"
}

///|
fn Config::generate_command(
  self : Config,
  seed : Int,
  source_path : String,
) -> String {
  let csmith = shell_quote(self.csmith_command)
  let output = shell_quote(source_path)
  "\{csmith} --seed \{seed} \{flags()} --output \{output}"
}

///|
fn Config::include_dir_word(self : Config) -> String {
  match self.include_root {
    Some(root) => shell_quote(root)
    None =>
      "\"$(cmd=$(command -v " +
      shell_quote(self.csmith_command) +
      "); while test -L \"$cmd\"; do link=$(readlink \"$cmd\"); if test \"${link#/}\" != \"$link\"; then cmd=\"$link\"; else cmd=$(dirname \"$cmd\")/\"$link\"; fi; done; prefix=$(cd \"$(dirname \"$cmd\")/..\" && pwd); header=$(find \"$prefix/include\" -name csmith.h -type f | grep -v '/runtime/' | sed -n '1p'); if test -z \"$header\"; then header=$(find \"$prefix/include\" -name csmith.h -type f | sed -n '1p'); fi; dirname \"$header\")\""
  }
}

///|
fn Config::include_description(self : Config) -> String {
  match self.include_root {
    Some(root) => root
    None => "$(prefix-of-\{self.csmith_command})/include/**/csmith.h"
  }
}

///|
fn Config::include_check_command(self : Config) -> String {
  match self.include_root {
    Some(root) => {
      let header = shell_quote(path_join(root, "csmith.h"))
      "test -f \{header}"
    }
    None =>
      "include_dir=\{self.include_dir_word()}; test -f \"$include_dir/csmith.h\""
  }
}

///|
fn Config::preprocess_command(
  self : Config,
  source_path : String,
  preprocessed_path : String,
  compat_path : String,
) -> String {
  let clang = shell_quote(self.clang_command)
  let include_dir = self.include_dir_word()
  let compat = shell_quote(compat_path)
  let source = shell_quote(source_path)
  let preprocessed = shell_quote(preprocessed_path)
  "\{clang} -w -E -P -DCSMITH_MINIMAL -I \{include_dir} -include \{compat} \{source} -o \{preprocessed}"
}

///|
fn Config::kimicc_compile_command(
  self : Config,
  preprocessed_path : String,
) -> String {
  match self.kimicc_command {
    Some(command) => "\{command} \{shell_quote(preprocessed_path)}"
    None =>
      "moon run cmd/main --target native -- \{shell_quote(preprocessed_path)}"
  }
}

///|
fn command_available(command : String) -> Bool {
  moonbit_system(
    @utf8.encode("command -v \{shell_quote(command)} >/dev/null 2>&1"),
  ) ==
  0
}

///|
pub fn require_toolchain(config : Config) -> Unit {
  if !command_available(config.csmith_command) {
    abort("csmith command missing: \{config.csmith_command}")
  }
  if !command_available(config.clang_command) {
    abort("clang command missing: \{config.clang_command}")
  }
  if !command_available(config.timeout_command) {
    abort("timeout command missing: \{config.timeout_command}")
  }
  if moonbit_system(@utf8.encode(config.include_check_command())) != 0 {
    abort("csmith include root missing: \{config.include_description()}")
  }
  if config.kimicc_command is None && !command_available("moon") {
    abort("moon command missing for default kimicc invocation")
  }
}

///|
fn Config::record_dir(self : Config, tag : String, seed : Int) -> String {
  path_join(self.record_root, "\{tag}_\{seed}")
}

///|
fn Config::bug_case_path(
  self : Config,
  seed : Int,
  stage_slug : String,
) -> String {
  path_join(self.bug_dir, "csmith_seed_\{seed}_\{stage_slug}.c")
}

///|
async fn Config::save_bug_case(
  self : Config,
  seed : Int,
  tag : String,
  preprocessed_path : String,
  stage_slug : String,
) -> String {
  run_command_checked(
    "mkdir -p \{shell_quote(self.bug_dir)}",
    "prepare csmith bug case dir",
  )
  let bug_path = self.bug_case_path(seed, stage_slug)
  write_text_file(bug_path, @fs.read_file(preprocessed_path).text())
  log(tag, seed, "saved \{bug_path}")
  bug_path
}

///|
async fn Config::record_failure(
  self : Config,
  record_dir : String,
  seed : Int,
  tag : String,
  source_path : String,
  preprocessed_path : String,
  stage : String,
  details : String,
) -> Unit {
  run_command_checked(
    "mkdir -p \{shell_quote(record_dir)}",
    "prepare csmith failure record",
  )
  let kimicc_command = self.kimicc_command.unwrap_or("auto")
  write_text_file("\{record_dir}/source.c", @fs.read_file(source_path).text())
  write_text_file(
    "\{record_dir}/preprocessed.i",
    @fs.read_file(preprocessed_path).text(),
  )
  write_text_file("\{record_dir}/compat.h", compat_header_source())
  let manifest =
    $|tag=\{tag}
    $|seed=\{seed}
    $|stage=\{stage}
    $|csmith-flags=\{flags()}
    $|compile-timeout-seconds=\{COMPILE_TIMEOUT_SEC}
    $|run-timeout-seconds=\{RUN_TIMEOUT_SEC}
    $|preprocess-flags=-w -E -P -DCSMITH_MINIMAL -I \{self.include_description()} -include compat.h
    $|csmith-command=\{self.csmith_command}
    $|clang-command=\{self.clang_command}
    $|timeout-command=\{self.timeout_command}
    $|kimicc-command=\{kimicc_command}
    $|record-root=\{self.record_root}
    $|bug-dir=\{self.bug_dir}
    $|
    $|\{details}
  write_text_file("\{record_dir}/manifest.txt", manifest)
}

///|
async fn Config::record_abnormal_case(
  self : Config,
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
    "\{details}\nbug-case=\{bug_path}\n",
  )
  "\{stage} seed=\{seed} bug=\{bug_path} record=\{record_dir}"
}

///|
fn failure_message(
  record_dir : String,
  seed : Int,
  tag : String,
  stage : String,
) -> String {
  "csmith differential failure at \{stage} for \{tag} seed=\{seed}; recorded at \{record_dir}"
}

///|
fn output_checksum(output : String) -> String {
  for raw in output.split("\n") {
    for part in raw.split("\r") {
      let line = part.trim()
      match line.split_once("=") {
        Some((left, right)) if left.trim() == "checksum" =>
          return right.trim().to_owned()
        _ => ()
      }
    }
  }
  "<missing>"
}

///|
async fn Config::run_case(self : Config, seed : Int, tag : String) -> String? {
  let source_path = temp_file_path(
    "\{tag}_csmith_source",
    seed.to_string(),
    ".c",
  )
  let preprocessed_path = temp_file_path(
    "\{tag}_csmith_preprocessed",
    seed.to_string(),
    ".i",
  )
  let compat_path = temp_file_path(
    "\{tag}_csmith_compat",
    seed.to_string(),
    ".h",
  )
  let kimicc_asm_path = temp_file_path(
    "\{tag}_csmith_kimicc",
    seed.to_string(),
    ".s",
  )
  let kimicc_bin_path = temp_file_path(
    "\{tag}_csmith_kimicc",
    seed.to_string(),
    "",
  )
  let clang_bin_path = temp_file_path(
    "\{tag}_csmith_clang",
    seed.to_string(),
    "",
  )
  let record_dir = self.record_dir(tag, seed)
  log(tag, seed, "start")
  log(tag, seed, "generate")
  write_text_file(compat_path, compat_header_source())
  run_command_checked(
    self.timed_command(
      self.generate_command(seed, source_path),
      COMPILE_TIMEOUT_SEC,
    ),
    "generate csmith \{tag}",
  )
  log(tag, seed, "preprocess")
  run_command_checked(
    self.timed_command(
      self.preprocess_command(source_path, preprocessed_path, compat_path),
      COMPILE_TIMEOUT_SEC,
    ),
    "preprocess csmith \{tag}",
  )
  log(tag, seed, "clang compile")
  let clang_compile_command = "\{shell_quote(self.clang_command)} -w -o \{shell_quote(clang_bin_path)} \{shell_quote(preprocessed_path)}"
  let clang_compile = run_command_capture(
    self.timed_command(clang_compile_command, COMPILE_TIMEOUT_SEC),
    "\{tag}_csmith_clang_compile",
  )
  if clang_compile.code != 0 {
    let stage = if timed_out(clang_compile.code) {
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
      "exit code=\{clang_compile.code}\n\{clang_compile.output}",
    )
    log(tag, seed, "skip \{failure_message(record_dir, seed, tag, stage)}")
    return None
  }
  log(tag, seed, "clang run")
  let clang_run = run_command_capture(
    self.timed_command(shell_quote(clang_bin_path), RUN_TIMEOUT_SEC),
    "\{tag}_csmith_clang_run",
  )
  if timed_out(clang_run.code) {
    let stage = "clang run timeout discarded"
    self.record_failure(
      record_dir,
      seed,
      tag,
      source_path,
      preprocessed_path,
      stage,
      "discarded=true\nreason=clang run timeout\nexit code=\{clang_run.code}\n\{clang_run.output}",
    )
    write_text_file("\{record_dir}/clang.out", clang_run.output)
    log(tag, seed, "discard clang-run-timeout record=\{record_dir}")
    return None
  }
  log(tag, seed, "kimicc compile")
  let kimicc_compile = run_command_capture(
    self.timed_command(
      self.kimicc_compile_command(preprocessed_path),
      COMPILE_TIMEOUT_SEC,
    ),
    "\{tag}_csmith_kimicc_compile",
  )
  if kimicc_compile.code != 0 {
    let stage = if timed_out(kimicc_compile.code) {
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
      "exit code=\{kimicc_compile.code}\n\{kimicc_compile.output}",
    )
    let stage_slug = if timed_out(kimicc_compile.code) {
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
        "exit code=\{kimicc_compile.code}\n\{kimicc_compile.output}",
      ),
    )
  }
  write_text_file(kimicc_asm_path, kimicc_compile.output)
  log(tag, seed, "kimicc link")
  let kimicc_link_command = "\{shell_quote(self.clang_command)} -w -o \{shell_quote(kimicc_bin_path)} \{shell_quote(kimicc_asm_path)}"
  let kimicc_link = run_command_capture(
    self.timed_command(kimicc_link_command, COMPILE_TIMEOUT_SEC),
    "\{tag}_csmith_kimicc_link",
  )
  if kimicc_link.code != 0 {
    self.record_failure(
      record_dir,
      seed,
      tag,
      source_path,
      preprocessed_path,
      "kimicc link",
      "exit code=\{kimicc_link.code}\n\{kimicc_link.output}",
    )
    write_text_file("\{record_dir}/kimicc.s", kimicc_compile.output)
    return Some(
      self.record_abnormal_case(
        record_dir,
        seed,
        tag,
        source_path,
        preprocessed_path,
        "kimicc link",
        "kimicc_link",
        "exit code=\{kimicc_link.code}\n\{kimicc_link.output}",
      ),
    )
  }
  log(tag, seed, "kimicc run")
  let kimicc_run = run_command_capture(
    self.timed_command(shell_quote(kimicc_bin_path), RUN_TIMEOUT_SEC),
    "\{tag}_csmith_kimicc_run",
  )
  if timed_out(kimicc_run.code) {
    self.record_failure(
      record_dir,
      seed,
      tag,
      source_path,
      preprocessed_path,
      "kimicc run timeout",
      "exit code=\{kimicc_run.code}\n\{kimicc_run.output}",
    )
    write_text_file("\{record_dir}/kimicc.s", kimicc_compile.output)
    write_text_file("\{record_dir}/kimicc.out", kimicc_run.output)
    return Some(
      self.record_abnormal_case(
        record_dir,
        seed,
        tag,
        source_path,
        preprocessed_path,
        "kimicc run timeout",
        "kimicc_run_timeout",
        "exit code=\{kimicc_run.code}\n\{kimicc_run.output}",
      ),
    )
  }
  if kimicc_run.code != clang_run.code || kimicc_run.output != clang_run.output {
    let kimicc_checksum = output_checksum(kimicc_run.output)
    let clang_checksum = output_checksum(clang_run.output)
    let stage = "runtime mismatch clang-checksum=\{clang_checksum} kimicc-checksum=\{kimicc_checksum}"
    log(
      tag,
      seed,
      "mismatch clang-checksum=\{clang_checksum} kimicc-checksum=\{kimicc_checksum}",
    )
    let mismatch_details =
      $|kimicc code=\{kimicc_run.code}
      $|kimicc checksum=\{kimicc_checksum}
      $|kimicc output:
      $|\{kimicc_run.output}
      $|clang code=\{clang_run.code}
      $|clang checksum=\{clang_checksum}
      $|clang output:
      $|\{clang_run.output}
    self.record_failure(
      record_dir, seed, tag, source_path, preprocessed_path, stage, mismatch_details,
    )
    write_text_file("\{record_dir}/kimicc.s", kimicc_compile.output)
    write_text_file("\{record_dir}/clang.out", clang_run.output)
    write_text_file("\{record_dir}/kimicc.out", kimicc_run.output)
    return Some(
      self.record_abnormal_case(
        record_dir, seed, tag, source_path, preprocessed_path, stage, "runtime_mismatch",
        mismatch_details,
      ),
    )
  }
  log(tag, seed, "ok")
  None
}

///|
pub async fn run_batch(
  config : Config,
  first_seed : Int,
  count : Int,
) -> BatchResult {
  require_toolchain(config)
  let failures : Array[String] = []
  for case_index in 0..<count {
    let seed = first_seed + case_index * 101
    if config.run_case(seed, "csmith_fuzz_\{case_index}") is Some(failure) {
      failures.push(failure)
    }
  }
  { failures, }
}

///|
pub fn format_failures(failures : Array[String]) -> String {
  let output = StringBuilder::new()
  output.write_string("csmith abnormal cases:\n")
  for failure in failures {
    output.write_string("- ")
    output.write_string(failure)
    output.write_char('\n')
  }
  output.to_string()
}

///|
fn write_text_file(path : String, content : String) -> Unit {
  let rc = moonbit_write_file(@utf8.encode(path), @utf8.encode(content))
  if rc != 0 {
    abort("write failed for \{path} with code: \{rc}")
  }
}

///|
fn shell_quote(value : String) -> String {
  let buf = StringBuilder::new()
  buf.write_string("'")
  for ch in value {
    if ch.to_int() == 39 {
      buf.write_string("'\\''")
    } else {
      buf.write_char(ch)
    }
  }
  buf.write_string("'")
  buf.to_string()
}

///|
fn run_command_checked(cmd : String, context : String) -> Unit {
  let rc = moonbit_system(@utf8.encode(cmd))
  if rc != 0 {
    abort("\{context} failed with code: \{rc}")
  }
}

///|
async fn run_command_capture(cmd : String, tag : String) -> CommandResult {
  let output_path = temp_file_path(tag, cmd, ".out")
  let script = "\{cmd} > \{shell_quote(output_path)} 2>&1"
  let rc = moonbit_system(
    @utf8.encode("sh -c \{shell_quote(script)} 2>/dev/null"),
  )
  let data = @fs.read_file(output_path)
  { code: rc, output: data.text() }
}

///|
fn source_id(source : String) -> String {
  let mut h = 0
  for ch in source {
    h = h * 31 + ch.to_int()
  }
  h.to_string()
}

///|
fn temp_file_path(prefix : String, seed : String, suffix : String) -> String {
  path_join(
    env("TMPDIR").unwrap_or("."),
    "kimicc_\{prefix}_\{source_id(seed)}\{suffix}",
  )
}
