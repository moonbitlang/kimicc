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
priv struct CaseContext {
  config : Config
  seed : Int
  tag : String
  prefix : String
  record_dir : String
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
fn CommandResult::details(self : CommandResult) -> String {
  "exit code=\{self.code}\n\{self.output}"
}

///|
fn CommandResult::stage(
  self : CommandResult,
  normal : String,
  timeout : String,
) -> String {
  if timed_out(self.code) {
    timeout
  } else {
    normal
  }
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
fn shell_command_in_dir(dir : String, cmd : String) -> String {
  let script = "cd \{shell_quote(dir)} && \{cmd}"
  "sh -c \{shell_quote(script)}"
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
fn Config::kimicc_driver_command(self : Config) -> String {
  match self.kimicc_command {
    Some(command) => command
    None => "moon run cmd/main --target native --"
  }
}

///|
fn Config::kimicc_preprocess_command(
  self : Config,
  source_path : String,
  preprocessed_path : String,
  compat_path : String,
) -> String {
  let include_dir = self.include_dir_word()
  let compat = shell_quote(compat_path)
  let source = shell_quote(source_path)
  let preprocessed = shell_quote(preprocessed_path)
  "\{self.kimicc_driver_command()} -E -DCSMITH_MINIMAL -I \{include_dir} -include \{compat} \{source} -o \{preprocessed}"
}

///|
fn Config::clang_preprocess_command(
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
  output_path : String,
) -> String {
  "\{self.kimicc_driver_command()} --preprocessed \{shell_quote(preprocessed_path)} -o \{shell_quote(output_path)}"
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
fn Config::case_context(self : Config, seed : Int, tag : String) -> CaseContext {
  {
    config: self,
    seed,
    tag,
    prefix: "\{tag}_csmith",
    record_dir: path_join(self.record_root, "\{tag}_\{seed}"),
  }
}

///|
fn CaseContext::log(self : CaseContext, stage : String) -> Unit {
  log(self.tag, self.seed, stage)
}

///|
fn CaseContext::path(
  self : CaseContext,
  name : String,
  suffix : String,
) -> String {
  temp_file_path("\{self.prefix}_\{name}", self.seed.to_string(), suffix)
}

///|
fn CaseContext::generate(self : CaseContext) -> Unit {
  let source = self.path("source", ".c")
  let compat = self.path("compat", ".h")
  let generate_dir = self.path("generate", ".d")
  write_text_file(compat, compat_header_source())
  run_command_checked(
    "mkdir -p \{shell_quote(generate_dir)}",
    "prepare csmith generate dir",
  )
  self.log("generate")
  run_command_checked(
    self.config.timed_command(
      shell_command_in_dir(
        generate_dir,
        self.config.generate_command(self.seed, source),
      ),
      COMPILE_TIMEOUT_SEC,
    ),
    "generate csmith \{self.tag}",
  )
}

///|
fn CaseContext::preprocess_with(
  self : CaseContext,
  stage : String,
  command : String,
) -> Unit {
  self.log(stage)
  run_command_checked(
    self.config.timed_command(command, COMPILE_TIMEOUT_SEC),
    "\{stage} csmith \{self.tag}",
  )
}

///|
fn CaseContext::preprocess(self : CaseContext) -> Unit {
  let source = self.path("source", ".c")
  let compat = self.path("compat", ".h")
  self.preprocess_with(
    "kimicc preprocess",
    self.config.kimicc_preprocess_command(
      source,
      self.path("kimicc_preprocessed", ".i"),
      compat,
    ),
  )
  self.preprocess_with(
    "clang preprocess",
    self.config.clang_preprocess_command(
      source,
      self.path("clang_preprocessed", ".i"),
      compat,
    ),
  )
}

///|
async fn CaseContext::capture_command(
  self : CaseContext,
  stage : String,
  command : String,
  timeout : Int,
  tag_suffix : String,
) -> CommandResult {
  self.log(stage)
  run_command_capture(
    self.config.timed_command(command, timeout),
    "\{self.tag}_csmith_\{tag_suffix}",
  )
}

///|
async fn CaseContext::capture_binary(
  self : CaseContext,
  stage : String,
  bin_path : String,
  run_dir : String,
  tag_suffix : String,
) -> CommandResult {
  run_command_checked(
    "mkdir -p \{shell_quote(run_dir)}",
    "prepare binary run dir",
  )
  self.capture_command(
    stage,
    shell_command_in_dir(run_dir, shell_quote(bin_path)),
    RUN_TIMEOUT_SEC,
    tag_suffix,
  )
}

///|
async fn CaseContext::record_failure(
  self : CaseContext,
  stage : String,
  details : String,
) -> Unit {
  run_command_checked(
    "mkdir -p \{shell_quote(self.record_dir)}",
    "prepare csmith failure record",
  )
  let kimicc_command = self.config.kimicc_command.unwrap_or("auto")
  write_text_file(
    "\{self.record_dir}/source.c",
    @fs.read_file(self.path("source", ".c")).text(),
  )
  write_text_file(
    "\{self.record_dir}/kimicc_preprocessed.i",
    @fs.read_file(self.path("kimicc_preprocessed", ".i")).text(),
  )
  write_text_file(
    "\{self.record_dir}/clang_preprocessed.i",
    @fs.read_file(self.path("clang_preprocessed", ".i")).text(),
  )
  write_text_file("\{self.record_dir}/compat.h", compat_header_source())
  let manifest =
    $|tag=\{self.tag}
    $|seed=\{self.seed}
    $|stage=\{stage}
    $|csmith-flags=\{flags()}
    $|compile-timeout-seconds=\{COMPILE_TIMEOUT_SEC}
    $|run-timeout-seconds=\{RUN_TIMEOUT_SEC}
    $|kimicc-preprocess-command=kimicc -E -DCSMITH_MINIMAL -I \{self.config.include_description()} -include compat.h
    $|clang-preprocess-command=clang -w -E -P -DCSMITH_MINIMAL -I \{self.config.include_description()} -include compat.h
    $|csmith-command=\{self.config.csmith_command}
    $|clang-command=\{self.config.clang_command}
    $|timeout-command=\{self.config.timeout_command}
    $|kimicc-command=\{kimicc_command}
    $|record-root=\{self.config.record_root}
    $|bug-dir=\{self.config.bug_dir}
    $|
    $|\{details}
  write_text_file("\{self.record_dir}/manifest.txt", manifest)
}

///|
async fn CaseContext::record_abnormal(
  self : CaseContext,
  stage : String,
  stage_slug : String,
  details : String,
) -> String {
  run_command_checked(
    "mkdir -p \{shell_quote(self.config.bug_dir)}",
    "prepare csmith bug case dir",
  )
  let bug_path = path_join(
    self.config.bug_dir,
    "csmith_seed_\{self.seed}_\{stage_slug}.c",
  )
  write_text_file(
    bug_path,
    @fs.read_file(self.path("kimicc_preprocessed", ".i")).text(),
  )
  self.log("saved \{bug_path}")
  self.record_failure(stage, "\{details}\nbug-case=\{bug_path}\n")
  "\{stage} seed=\{self.seed} bug=\{bug_path} record=\{self.record_dir}"
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
fn runtime_mismatch_report(
  kimicc : CommandResult,
  clang : CommandResult,
) -> (String, String, String, String) {
  let kimicc_checksum = output_checksum(kimicc.output)
  let clang_checksum = output_checksum(clang.output)
  let stage = "runtime mismatch clang-checksum=\{clang_checksum} kimicc-checksum=\{kimicc_checksum}"
  let details =
    $|kimicc code=\{kimicc.code}
    $|kimicc checksum=\{kimicc_checksum}
    $|kimicc output:
    $|\{kimicc.output}
    $|clang code=\{clang.code}
    $|clang checksum=\{clang_checksum}
    $|clang output:
    $|\{clang.output}
  (stage, details, clang_checksum, kimicc_checksum)
}

///|
async fn Config::run_case(self : Config, seed : Int, tag : String) -> String? {
  let case = self.case_context(seed, tag)
  let clang_bin = case.path("clang", "")
  let clang_preprocessed = case.path("clang_preprocessed", ".i")
  let kimicc_bin = case.path("kimicc", "")
  let kimicc_preprocessed = case.path("kimicc_preprocessed", ".i")
  case.log("start")
  case.generate()
  case.preprocess()
  let clang_compile = case.capture_command(
    "clang compile",
    "\{shell_quote(self.clang_command)} -w -o \{shell_quote(clang_bin)} \{shell_quote(clang_preprocessed)}",
    COMPILE_TIMEOUT_SEC,
    "clang_compile",
  )
  if clang_compile.code != 0 {
    let stage = clang_compile.stage("clang compile", "clang compile timeout")
    case.record_failure(stage, clang_compile.details())
    case.log("skip \{stage} record=\{case.record_dir}")
    return None
  }
  let clang_run = case.capture_binary(
    "clang run",
    clang_bin,
    case.path("clang_run", ".d"),
    "clang_run",
  )
  if timed_out(clang_run.code) {
    let stage = "clang run timeout discarded"
    case.record_failure(
      stage,
      "discarded=true\nreason=clang run timeout\n\{clang_run.details()}",
    )
    write_text_file("\{case.record_dir}/clang.out", clang_run.output)
    case.log("discard clang-run-timeout record=\{case.record_dir}")
    return None
  }
  let kimicc_compile = case.capture_command(
    "kimicc compile",
    self.kimicc_compile_command(kimicc_preprocessed, kimicc_bin),
    COMPILE_TIMEOUT_SEC,
    "kimicc_compile",
  )
  if kimicc_compile.code != 0 {
    let stage = kimicc_compile.stage("kimicc compile", "kimicc compile timeout")
    let stage_slug = kimicc_compile.stage(
      "kimicc_compile", "kimicc_compile_timeout",
    )
    return Some(
      case.record_abnormal(stage, stage_slug, kimicc_compile.details()),
    )
  }
  let kimicc_run = case.capture_binary(
    "kimicc run",
    kimicc_bin,
    case.path("kimicc_run", ".d"),
    "kimicc_run",
  )
  if timed_out(kimicc_run.code) {
    let failure = case.record_abnormal(
      "kimicc run timeout",
      "kimicc_run_timeout",
      kimicc_run.details(),
    )
    write_text_file("\{case.record_dir}/kimicc.out", kimicc_run.output)
    return Some(failure)
  }
  if kimicc_run.code != clang_run.code || kimicc_run.output != clang_run.output {
    let (stage, details, clang_checksum, kimicc_checksum) = runtime_mismatch_report(
      kimicc_run, clang_run,
    )
    case.log(
      "mismatch clang-checksum=\{clang_checksum} kimicc-checksum=\{kimicc_checksum}",
    )
    let failure = case.record_abnormal(stage, "runtime_mismatch", details)
    write_text_file("\{case.record_dir}/clang.out", clang_run.output)
    write_text_file("\{case.record_dir}/kimicc.out", kimicc_run.output)
    return Some(failure)
  }
  case.log("ok")
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
