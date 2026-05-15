///|

///|
extern "c" fn moonbit_exit(code : Int) -> Unit = "moonbit_exit"

///|
fn parse_int_arg(value : String, name : String) -> Int {
  @string.parse_int(value) catch {
    _ => abort("invalid \{name}: \{value}")
  }
}

///|
fn print_usage() -> Unit {
  println(
    (
      #|usage: moon run cmd/csmith_fuzz --target native -- [--seed N] [--count N]
      #|
      #|options:
      #|  --seed N    first csmith seed (default: 7)
      #|  --count N   number of cases to run (default: 20)
      #|  -h, --help  print this help
      #|
      #|environment:
      #|  KIMICC_CSMITH_KIMICC       kimicc driver command, e.g. _build/native/debug/build/cmd/main/main.exe
      #|  KIMICC_CSMITH_CLANG        clang command for reference preprocess/compile/run
      #|  KIMICC_CSMITH_RECORD_ROOT  record output root
      #|  KIMICC_CSMITH_BUG_DIR      saved bug case dir
      #|  KIMICC_CSMITH_INCLUDE_ROOT csmith include root override
    ),
  )
}

///|
fn parse_args(args : Array[String]) -> (Int, Int)? {
  let mut seed = @fuzz.DEFAULT_SEED
  let mut count = @fuzz.DEFAULT_COUNT
  let mut i = 1
  while i < args.length() {
    match args[i] {
      "-h" | "--help" => {
        print_usage()
        return None
      }
      "--seed" => {
        if i + 1 >= args.length() {
          abort("missing value for --seed")
        }
        seed = parse_int_arg(args[i + 1], "--seed")
        i = i + 2
      }
      "--count" => {
        if i + 1 >= args.length() {
          abort("missing value for --count")
        }
        count = parse_int_arg(args[i + 1], "--count")
        i = i + 2
      }
      other => abort("unknown argument: \{other}")
    }
  }
  Some((seed, count))
}

///|
async fn main {
  let args = @env.args()
  let parsed = parse_args(args).unwrap()
  let seed = parsed.0
  let count = parsed.1
  if count < 0 {
    abort("--count must be non-negative")
  }
  let result = @fuzz.run_batch(@fuzz.config_from_env(), seed, count)
  if result.failures.length() > 0 {
    println(@fuzz.format_failures(result.failures))
    moonbit_exit(1)
  }
}
