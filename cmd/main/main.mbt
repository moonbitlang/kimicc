///|
#borrow(path)
extern "c" fn moonbit_read_file(path : Bytes) -> Bytes = "moonbit_read_file"

///|
#borrow(path, content)
extern "c" fn moonbit_write_file(path : Bytes, content : Bytes) -> Int = "moonbit_write_file"

///|
fn read_file(path : String) -> String? {
  let bytes = moonbit_read_file(@utf8.encode(path))
  if bytes.length() == 0 {
    return None
  }
  Some(@utf8.decode_lossy(bytes))
}

///|
fn write_file(path : String, content : String) -> Bool {
  let rc = moonbit_write_file(
    @utf8.encode(path),
    @utf8.encode(content),
  )
  rc == 0
}

///|
fn main {
  let cmd = @argparse.Command(
    "kimicc",
    flags=[@argparse.FlagArg("version", short='v', long="version")],
    options=[
      @argparse.OptionArg("output", short='o', long="output", default_values=["-"]),
    ],
    positionals=[@argparse.PositionArg("input")],
    about="A simple C compiler",
  )
  let matches = cmd.parse() catch {
    err => {
      println(err.to_string())
      return
    }
  }
  if matches.flags.get("version") == Some(true) {
    println("kimicc 0.1.0")
    return
  }
  let input_path = match matches.values.get("input") {
    Some(arr) =>
      if arr.length() > 0 {
        arr[0]
      } else {
        println("error: no input file")
        return
      }
    None => {
      println("error: no input file")
      return
    }
  }
  let output_path = match matches.values.get("output") {
    Some(arr) =>
      if arr.length() > 0 {
        arr[0]
      } else {
        "-"
      }
    None => "-"
  }
  let source = match read_file(input_path) {
    Some(content) => content
    None => {
      println("error: cannot read file: " + input_path)
      return
    }
  }
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  if output_path == "-" {
    println(assembly)
  } else {
    if !write_file(output_path, assembly) {
      println("error: cannot write file: " + output_path)
    }
  }
}
