#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <moonbit.h>

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
  int rc = system((const char *)cmd);
  if (WIFEXITED(rc)) {
    return WEXITSTATUS(rc);
  }
  return -1;
}

MOONBIT_FFI_EXPORT
void moonbit_flush_stdout(void) {
  fflush(stdout);
}

MOONBIT_FFI_EXPORT
void moonbit_exit(int code) {
  exit(code);
}
