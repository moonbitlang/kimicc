// Minimal stubs for c4.c compilation
// Replaces system headers to avoid inline functions with compiler builtins
int printf(const char *format, ...);
void *malloc(int size);
void free(void *ptr);
void *memset(void *s, int c, int n);
int memcmp(const void *s1, const void *s2, int n);
int open(const char *pathname, int flags);
int read(int fd, void *buf, int count);
int close(int fd);
void exit(int status);
