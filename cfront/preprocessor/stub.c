#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <moonbit.h>

MOONBIT_FFI_EXPORT
bool kimicc_pp_file_exists(moonbit_bytes_t path) {
  FILE *f = fopen((const char *)path, "rb");
  if (!f) return false;
  fclose(f);
  return true;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t kimicc_pp_read_file(moonbit_bytes_t path) {
  FILE *f = fopen((const char *)path, "rb");
  if (!f) return moonbit_make_bytes(0, 0);
  fseek(f, 0, SEEK_END);
  long len = ftell(f);
  if (len < 0) {
    fclose(f);
    return moonbit_make_bytes(0, 0);
  }
  fseek(f, 0, SEEK_SET);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  if (len > 0) {
    fread(bytes, 1, (size_t)len, f);
  }
  fclose(f);
  return bytes;
}
