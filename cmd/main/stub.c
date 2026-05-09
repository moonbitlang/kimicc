#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <moonbit.h>

MOONBIT_FFI_EXPORT
moonbit_bytes_t moonbit_read_file(moonbit_bytes_t path) {
  FILE *f = fopen((const char *)path, "r");
  if (!f) return moonbit_make_bytes(0, 0);
  fseek(f, 0, SEEK_END);
  long len = ftell(f);
  fseek(f, 0, SEEK_SET);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  fread(bytes, 1, len, f);
  fclose(f);
  return bytes;
}

MOONBIT_FFI_EXPORT
int moonbit_file_exists(moonbit_bytes_t path) {
  FILE *f = fopen((const char *)path, "r");
  if (!f) return 0;
  fclose(f);
  return 1;
}

MOONBIT_FFI_EXPORT
int moonbit_write_file(moonbit_bytes_t path, moonbit_bytes_t content) {
  FILE *f = fopen((const char *)path, "wb");
  if (!f) return -1;
  size_t len = Moonbit_array_length(content);
  size_t written = fwrite(content, 1, len, f);
  fclose(f);
  return written == len ? 0 : -1;
}

MOONBIT_FFI_EXPORT
int moonbit_system(moonbit_bytes_t cmd) {
  return system((const char *)cmd);
}

MOONBIT_FFI_EXPORT
void moonbit_exit(int code) {
  exit(code);
}
