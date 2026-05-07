///|
priv type ExecutableMemory

///|
#borrow(code, base_relocations, external_relocations)
extern "c" fn executable_memory_new(
  code : Bytes,
  executable_size : Int,
  base_relocations : Bytes,
  external_relocations : Bytes,
) -> ExecutableMemory = "kimicc_jit_memory_new"

///|
#borrow(memory)
extern "c" fn executable_memory_is_valid(memory : ExecutableMemory) -> Bool = "kimicc_jit_memory_is_valid"

///|
#borrow(memory)
extern "c" fn executable_memory_call_i32_0(
  memory : ExecutableMemory,
  offset : Int,
) -> Int = "kimicc_jit_call_i32_0"

///|
#borrow(memory)
extern "c" fn executable_memory_call_i32_1(
  memory : ExecutableMemory,
  offset : Int,
  arg0 : Int,
) -> Int = "kimicc_jit_call_i32_1"

///|
#borrow(memory)
extern "c" fn executable_memory_call_i32_2(
  memory : ExecutableMemory,
  offset : Int,
  arg0 : Int,
  arg1 : Int,
) -> Int = "kimicc_jit_call_i32_2"

///|
#borrow(memory)
extern "c" fn executable_memory_call_i32_3(
  memory : ExecutableMemory,
  offset : Int,
  arg0 : Int,
  arg1 : Int,
  arg2 : Int,
) -> Int = "kimicc_jit_call_i32_3"
