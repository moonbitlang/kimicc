///|
/// Loaded native JIT module.
///
/// A module owns executable memory allocated by the native FFI stub. The type
/// is opaque; use `compile` to create one and `call_i32_N` methods to invoke
/// exported C functions with matching signatures.
struct Module {
  image : @codegen.JitImage
  memory : ExecutableMemory
}

///|
fn normalize_symbol_name(name : String) -> String {
  if name.has_prefix("_") {
    name
  } else {
    "_" + name
  }
}

///|
/// Compiles C source to native memory and resolves relocations.
///
/// Returns `None` if parsing/codegen succeeds but native image allocation,
/// memory protection, base relocation, or external-symbol resolution fails.
/// The source must already be preprocessed.
pub fn compile(source : String) -> Module? {
  let prog = @parser.parse(source)
  let image = @codegen.generate_jit_image(prog)
  let memory = executable_memory_new(
    image.code,
    image.executable_size,
    image.base_relocations,
    image.external_relocations,
  )
  if executable_memory_is_valid(memory) {
    Some({ image, memory })
  } else {
    None
  }
}

///|
/// Preprocesses C source, then compiles it to native memory.
///
/// `compile` remains the preprocessed-source API. Use this function when the
/// source may contain macros, conditionals, or includes.
pub fn compile_c(
  source : String,
  options : @preprocessor.PreprocessOptions,
) -> Result[Module?, @preprocessor.PreprocessError] {
  match @preprocessor.preprocess(source, options) {
    Ok(preprocessed) => Ok(compile(preprocessed))
    Err(err) => Err(err)
  }
}

///|
/// Looks up a compiled symbol by C or Darwin spelling.
///
/// For example, both `"answer"` and `"_answer"` are accepted. The result is a
/// byte offset into the module's in-memory image.
pub fn Module::symbol_offset(self : Module, name : String) -> Int? {
  let normalized = normalize_symbol_name(name)
  for symbol in self.image.symbols {
    if symbol.name == normalized {
      return Some(symbol.offset)
    }
  }
  None
}

///|
/// Calls an exported `int fn(void)` symbol.
///
/// Returns `None` if the symbol is missing. Calling a symbol with a different
/// native signature is undefined behavior.
pub fn Module::call_i32_0(self : Module, name : String) -> Int? {
  match self.symbol_offset(name) {
    Some(offset) => Some(executable_memory_call_i32_0(self.memory, offset))
    None => None
  }
}

///|
/// Calls an exported `int fn(int)` symbol.
///
/// Returns `None` if the symbol is missing. Calling a symbol with a different
/// native signature is undefined behavior.
pub fn Module::call_i32_1(self : Module, name : String, arg0 : Int) -> Int? {
  match self.symbol_offset(name) {
    Some(offset) =>
      Some(executable_memory_call_i32_1(self.memory, offset, arg0))
    None => None
  }
}

///|
/// Calls an exported `int fn(int, int)` symbol.
///
/// Returns `None` if the symbol is missing. Calling a symbol with a different
/// native signature is undefined behavior.
pub fn Module::call_i32_2(
  self : Module,
  name : String,
  arg0 : Int,
  arg1 : Int,
) -> Int? {
  match self.symbol_offset(name) {
    Some(offset) =>
      Some(executable_memory_call_i32_2(self.memory, offset, arg0, arg1))
    None => None
  }
}

///|
/// Calls an exported `int fn(int, int, int)` symbol.
///
/// Returns `None` if the symbol is missing. Calling a symbol with a different
/// native signature is undefined behavior.
pub fn Module::call_i32_3(
  self : Module,
  name : String,
  arg0 : Int,
  arg1 : Int,
  arg2 : Int,
) -> Int? {
  match self.symbol_offset(name) {
    Some(offset) =>
      Some(executable_memory_call_i32_3(self.memory, offset, arg0, arg1, arg2))
    None => None
  }
}

///|
/// Compiles `source` and calls an exported `int fn(void)` symbol once.
///
/// For repeated calls, use `compile` and keep the returned `Module`.
pub fn call_i32_0(source : String, name : String) -> Int? {
  match compile(source) {
    Some(module_) => module_.call_i32_0(name)
    None => None
  }
}

///|
/// Compiles `source` and calls an exported `int fn(int, int)` symbol once.
///
/// For repeated calls, use `compile` and keep the returned `Module`.
pub fn call_i32_2(
  source : String,
  name : String,
  arg0 : Int,
  arg1 : Int,
) -> Int? {
  match compile(source) {
    Some(module_) => module_.call_i32_2(name, arg0, arg1)
    None => None
  }
}

///|
/// Compiles `source` and calls an exported `int fn(int, int, int)` symbol once.
///
/// For repeated calls, use `compile` and keep the returned `Module`.
pub fn call_i32_3(
  source : String,
  name : String,
  arg0 : Int,
  arg1 : Int,
  arg2 : Int,
) -> Int? {
  match compile(source) {
    Some(module_) => module_.call_i32_3(name, arg0, arg1, arg2)
    None => None
  }
}

///|
/// Compiles `source` and calls an exported `int fn(int)` symbol once.
///
/// For repeated calls, use `compile` and keep the returned `Module`.
pub fn call_i32_1(source : String, name : String, arg0 : Int) -> Int? {
  match compile(source) {
    Some(module_) => module_.call_i32_1(name, arg0)
    None => None
  }
}
