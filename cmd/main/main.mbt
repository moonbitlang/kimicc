///|
fn main {
  let args = @env.args()
  let default_source =
    #|int main() {
    #|  int a = 10;
    #|  int b = 20;
    #|  int c = a + b;
    #|  if (c > 25) {
    #|    c = c * 2;
    #|  } else {
    #|    c = c - 5;
    #|  }
    #|  while (c > 0) {
    #|    c = c - 1;
    #|  }
    #|  return c + 100;
    #|}
  let source = if args.length() >= 2 { args[1] } else { default_source }
  let prog = @parser.parse(source)
  let codegen = @codegen.Codegen::new()
  let assembly = codegen.generate(prog)
  println(assembly)
}
