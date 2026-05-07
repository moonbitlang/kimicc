///|
priv type ExecutableMemory

///|
#borrow(code)
extern "c" fn executable_memory_new(code : Bytes) -> ExecutableMemory = "kimicc_jit_memory_new"

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
