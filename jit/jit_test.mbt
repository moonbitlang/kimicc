///|
test "jit calls zero-argument int function" {
  let source = "int answer(void) { return 42; }"
  match call_i32_0(source, "answer") {
    Some(value) => if value != 42 { abort("expected 42") }
    None => abort("JIT call failed")
  }
}

///|
test "jit calls one-argument int function" {
  let source = "int add_one(int x) { return x + 1; }"
  match call_i32_1(source, "add_one", 41) {
    Some(value) => if value != 42 { abort("expected 42") }
    None => abort("JIT call failed")
  }
}

///|
test "jit calls internal helper" {
  let source =
    #|int helper(int x) { return x * 2; }
    #|int entry(int x) { return helper(x) + 2; }
  match call_i32_1(source, "entry", 20) {
    Some(value) => if value != 42 { abort("expected 42") }
    None => abort("JIT call failed")
  }
}

///|
test "jit missing symbol returns none" {
  let source = "int answer(void) { return 42; }"
  match compile(source) {
    Some(module_) =>
      match module_.call_i32_0("missing") {
        Some(_) => abort("missing symbol unexpectedly resolved")
        None => ()
      }
    None => abort("JIT allocation failed")
  }
}
