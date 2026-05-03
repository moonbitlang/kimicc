int counter = 0;
int inc() {
  counter = counter + 1;
  return counter;
}
int main() {
  inc();
  inc();
  return counter;
}
