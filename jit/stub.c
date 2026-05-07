#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <moonbit.h>

typedef struct {
  uint8_t *ptr;
  size_t size;
} KimiccJitMemory;

static void kimicc_jit_memory_destroy(void *ptr) {
  KimiccJitMemory *memory = (KimiccJitMemory *)ptr;
  if (memory->ptr != NULL && memory->size != 0) {
    munmap(memory->ptr, memory->size);
  }
}

static KimiccJitMemory *kimicc_jit_memory_make_empty(void) {
  KimiccJitMemory *memory = (KimiccJitMemory *)moonbit_make_external_object(
    kimicc_jit_memory_destroy,
    sizeof(KimiccJitMemory)
  );
  memory->ptr = NULL;
  memory->size = 0;
  return memory;
}

MOONBIT_FFI_EXPORT
KimiccJitMemory *kimicc_jit_memory_new(moonbit_bytes_t code) {
  size_t code_size = Moonbit_array_length(code);
  if (code_size == 0) {
    return kimicc_jit_memory_make_empty();
  }

  long page_size_result = sysconf(_SC_PAGESIZE);
  size_t page_size = page_size_result > 0 ? (size_t)page_size_result : 16384;
  size_t mapped_size = (code_size + page_size - 1) & ~(page_size - 1);

  void *ptr = mmap(
    NULL,
    mapped_size,
    PROT_READ | PROT_WRITE,
    MAP_PRIVATE | MAP_ANON,
    -1,
    0
  );
  if (ptr == MAP_FAILED) {
    return kimicc_jit_memory_make_empty();
  }

  memcpy(ptr, code, code_size);
  __builtin___clear_cache((char *)ptr, (char *)ptr + code_size);

  if (mprotect(ptr, mapped_size, PROT_READ | PROT_EXEC) != 0) {
    munmap(ptr, mapped_size);
    return kimicc_jit_memory_make_empty();
  }

  KimiccJitMemory *memory = (KimiccJitMemory *)moonbit_make_external_object(
    kimicc_jit_memory_destroy,
    sizeof(KimiccJitMemory)
  );
  memory->ptr = (uint8_t *)ptr;
  memory->size = mapped_size;
  return memory;
}

MOONBIT_FFI_EXPORT
int32_t kimicc_jit_memory_is_valid(KimiccJitMemory *memory) {
  return memory != NULL && memory->ptr != NULL;
}

MOONBIT_FFI_EXPORT
int32_t kimicc_jit_call_i32_0(KimiccJitMemory *memory, int32_t offset) {
  typedef int32_t (*JitFn)(void);
  JitFn fn = (JitFn)(void *)(memory->ptr + offset);
  return fn();
}

MOONBIT_FFI_EXPORT
int32_t kimicc_jit_call_i32_1(
  KimiccJitMemory *memory,
  int32_t offset,
  int32_t arg0
) {
  typedef int32_t (*JitFn)(int32_t);
  JitFn fn = (JitFn)(void *)(memory->ptr + offset);
  return fn(arg0);
}
