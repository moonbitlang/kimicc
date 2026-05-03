int main() {
  int a, b, c;
  a = 10;
  b = 20;
  c = a + b;
  if (c > 25) {
    c = c * 2;
  } else {
    c = c - 5;
  }
  while (c > 0) {
    c = c - 1;
  }
  return c + 100;
}
