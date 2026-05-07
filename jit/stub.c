#include <dlfcn.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
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

static uint32_t kimicc_jit_read_u32_le(const uint8_t *bytes) {
  return ((uint32_t)bytes[0]) |
         ((uint32_t)bytes[1] << 8) |
         ((uint32_t)bytes[2] << 16) |
         ((uint32_t)bytes[3] << 24);
}

static int kimicc_jit_add_u64_to_slot(
  uint8_t *ptr,
  size_t mapped_size,
  uint32_t offset,
  uint64_t addend
) {
  if (
    (size_t)offset > mapped_size ||
    mapped_size - (size_t)offset < sizeof(uint64_t)
  ) {
    return -1;
  }
  uint64_t value = 0;
  memcpy(&value, ptr + offset, sizeof(value));
  value += addend;
  memcpy(ptr + offset, &value, sizeof(value));
  return 0;
}

static int kimicc_jit_apply_base_relocations(
  uint8_t *ptr,
  size_t mapped_size,
  moonbit_bytes_t base_relocations
) {
  size_t reloc_size = Moonbit_array_length(base_relocations);
  if (reloc_size % 4 != 0) {
    return -1;
  }
  uintptr_t base = (uintptr_t)ptr;
  for (size_t i = 0; i < reloc_size; i += 4) {
    uint32_t offset = kimicc_jit_read_u32_le(
      (const uint8_t *)base_relocations + i
    );
    if (
      kimicc_jit_add_u64_to_slot(
        ptr,
        mapped_size,
        offset,
        (uint64_t)base
      ) != 0
    ) {
      return -1;
    }
  }
  return 0;
}

static void *kimicc_jit_lookup_symbol(const char *name) {
  void *symbol = dlsym(RTLD_DEFAULT, name);
  if (symbol == NULL && name[0] == '_') {
    symbol = dlsym(RTLD_DEFAULT, name + 1);
  }
  return symbol;
}

static int kimicc_jit_apply_external_relocations(
  uint8_t *ptr,
  size_t mapped_size,
  moonbit_bytes_t external_relocations
) {
  const uint8_t *bytes = (const uint8_t *)external_relocations;
  size_t reloc_size = Moonbit_array_length(external_relocations);
  size_t i = 0;
  while (i < reloc_size) {
    if (reloc_size - i < 8) {
      return -1;
    }
    uint32_t offset = kimicc_jit_read_u32_le(bytes + i);
    uint32_t name_size = kimicc_jit_read_u32_le(bytes + i + 4);
    i += 8;
    if (name_size > reloc_size - i) {
      return -1;
    }
    char *name = (char *)malloc((size_t)name_size + 1);
    if (name == NULL) {
      return -1;
    }
    memcpy(name, bytes + i, name_size);
    name[name_size] = '\0';
    i += name_size;

    void *symbol = kimicc_jit_lookup_symbol(name);
    free(name);
    if (symbol == NULL) {
      return -1;
    }
    if (
      kimicc_jit_add_u64_to_slot(
        ptr,
        mapped_size,
        offset,
        (uint64_t)(uintptr_t)symbol
      ) != 0
    ) {
      return -1;
    }
  }
  return 0;
}

MOONBIT_FFI_EXPORT
KimiccJitMemory *kimicc_jit_memory_new(
  moonbit_bytes_t code,
  int32_t executable_size,
  moonbit_bytes_t base_relocations,
  moonbit_bytes_t external_relocations
) {
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
  if (kimicc_jit_apply_base_relocations(
        (uint8_t *)ptr,
        mapped_size,
        base_relocations
      ) != 0) {
    munmap(ptr, mapped_size);
    return kimicc_jit_memory_make_empty();
  }
  if (kimicc_jit_apply_external_relocations(
        (uint8_t *)ptr,
        mapped_size,
        external_relocations
      ) != 0) {
    munmap(ptr, mapped_size);
    return kimicc_jit_memory_make_empty();
  }
  __builtin___clear_cache((char *)ptr, (char *)ptr + code_size);

  if (executable_size > 0) {
    size_t exec_size = (size_t)executable_size;
    if (exec_size > mapped_size) {
      munmap(ptr, mapped_size);
      return kimicc_jit_memory_make_empty();
    }
    size_t exec_mprotect_size = (exec_size + page_size - 1) & ~(page_size - 1);
    if (mprotect(ptr, exec_mprotect_size, PROT_READ | PROT_EXEC) != 0) {
      munmap(ptr, mapped_size);
      return kimicc_jit_memory_make_empty();
    }
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
