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
test "jit calls two-argument int function" {
  let source = "int add(int x, int y) { return x + y; }"
  match call_i32_2(source, "add", 20, 22) {
    Some(value) => if value != 42 { abort("expected 42") }
    None => abort("JIT call failed")
  }
}

///|
test "jit calls three-argument int function" {
  let source = "int mix(int x, int y, int z) { return x * y + z; }"
  match call_i32_3(source, "mix", 5, 8, 2) {
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
test "jit calls external libc function" {
  let source =
    #|extern int strcmp(char *, char *);
    #|int entry(void) { return strcmp("kimicc", "kimicc") + 42; }
  match call_i32_0(source, "entry") {
    Some(value) => if value != 42 { abort("expected 42") }
    None => abort("JIT call failed")
  }
}

///|
test "jit calls external function through local pointer" {
  let source =
    #|extern int strcmp(char *, char *);
    #|int entry(void) {
    #|  int (*p)(char *, char *) = strcmp;
    #|  return p("a", "a") + 42;
    #|}
  match call_i32_0(source, "entry") {
    Some(value) => if value != 42 { abort("expected 42") }
    None => abort("JIT call failed")
  }
}

///|
test "jit calls external function through global pointer" {
  let source =
    #|extern int strcmp(char *, char *);
    #|int (*p)(char *, char *) = strcmp;
    #|int entry(void) { return p("a", "a") + 42; }
  match call_i32_0(source, "entry") {
    Some(value) => if value != 42 { abort("expected 42") }
    None => abort("JIT call failed")
  }
}

///|
test "jit reads initialized global" {
  let source = "int g = 40; int entry(void) { return g + 2; }"
  match call_i32_0(source, "entry") {
    Some(value) => if value != 42 { abort("expected 42") }
    None => abort("JIT call failed")
  }
}

///|
test "jit reads string literal" {
  let source = "int entry(void) { char *s = \"AZ\"; return s[1] - 48; }"
  match call_i32_0(source, "entry") {
    Some(value) => if value != 42 { abort("expected 42") }
    None => abort("JIT call failed")
  }
}

///|
test "jit patches pointer data initializer" {
  let source = "int g = 41; int *p = &g; int entry(void) { return *p + 1; }"
  match call_i32_0(source, "entry") {
    Some(value) => if value != 42 { abort("expected 42") }
    None => abort("JIT call failed")
  }
}

///|
test "jit writes uninitialized global" {
  let source = "int g; int entry(void) { g = 40; return g + 2; }"
  match call_i32_0(source, "entry") {
    Some(value) => if value != 42 { abort("expected 42") }
    None => abort("JIT call failed")
  }
}

///|
test "jit preserves writable data across calls" {
  let source = "int g; int entry(void) { g = g + 20; return g + 2; }"
  match compile(source) {
    Some(module_) => {
      match module_.call_i32_0("entry") {
        Some(value) =>
          if value != 22 {
            abort("expected first call to return 22")
          }
        None => abort("JIT call failed")
      }
      match module_.call_i32_0("entry") {
        Some(value) =>
          if value != 42 {
            abort("expected second call to return 42")
          }
        None => abort("JIT call failed")
      }
    }
    None => abort("JIT allocation failed")
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
