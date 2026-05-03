int main() {
  int a = 1;
  int b = 0;
  if (a && b) {
    return 1;
  }
  if (a || b) {
    if (!b) {
      return 3;
    }
    return 2;
  }
  return 0;
}
