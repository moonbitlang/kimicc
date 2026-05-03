int main() {
  int a = 15;
  int b = 240;
  int r = (a & b) | (a ^ b);
  r = r | (a << 2);
  r = r | (b >> 4);
  r = r | ~a;
  return r;
}
