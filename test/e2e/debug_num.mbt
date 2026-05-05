///|
test "debug number parsing" {
  let prog = @parser.parse("int main() { return 3000000000U; }")
  inspect(prog.decls.length(), content="1")
}
