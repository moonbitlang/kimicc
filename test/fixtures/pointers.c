int main() {
  int x = 42;
  int *p = &x;
  *p = *p + 8;
  return x;
}
