///|
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
pub fn Module::call_i32_0(self : Module, name : String) -> Int? {
  match self.symbol_offset(name) {
    Some(offset) => Some(executable_memory_call_i32_0(self.memory, offset))
    None => None
  }
}

///|
pub fn Module::call_i32_1(self : Module, name : String, arg0 : Int) -> Int? {
  match self.symbol_offset(name) {
    Some(offset) =>
      Some(executable_memory_call_i32_1(self.memory, offset, arg0))
    None => None
  }
}

///|
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
pub fn call_i32_0(source : String, name : String) -> Int? {
  match compile(source) {
    Some(module_) => module_.call_i32_0(name)
    None => None
  }
}

///|
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
pub fn call_i32_1(source : String, name : String, arg0 : Int) -> Int? {
  match compile(source) {
    Some(module_) => module_.call_i32_1(name, arg0)
    None => None
  }
}
