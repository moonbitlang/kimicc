///|
async test "e2e MIR oracle checks scalar calls and arithmetic" {
  let source =
    #|int mul(int a, int b) {
    #|  return a * b;
    #|}
    #|int main(void) {
    #|  int x = 6;
    #|  int y = 7;
    #|  return mul(x, y);
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks scalar control flow" {
  let source =
    #|int main(void) {
    #|  int sum = 0;
    #|  for (int i = 0; i < 10; i++) {
    #|    if (i == 3) continue;
    #|    if (i == 8) break;
    #|    sum += i;
    #|  }
    #|  while (sum < 30) {
    #|    sum++;
    #|  }
    #|  return sum + (sum == 30 ? 12 : 0);
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks scalar globals and casts" {
  let source =
    #|int g = 35;
    #|int bump(int x) {
    #|  g += x;
    #|  return g;
    #|}
    #|int main(void) {
    #|  unsigned char c = 255 + 1;
    #|  int v = bump(5);
    #|  return v + sizeof(long double) - 6 + c;
    #|}
  run_source_against_mir_oracle(source)
}

///|
async test "e2e MIR oracle checks scalar switch fallthrough" {
  let source =
    #|int main(void) {
    #|  int total = 0;
    #|  for (int i = 0; i < 5; i++) {
    #|    switch (i) {
    #|    case 0:
    #|      total += 3;
    #|      break;
    #|    case 1:
    #|    case 2:
    #|      total += 5;
    #|      break;
    #|    case 4:
    #|      total += 7;
    #|    default:
    #|      total += 11;
    #|    }
    #|  }
    #|  return total;
    #|}
  run_source_against_mir_oracle(source)
}
