#!/bin/bash
set -e

KIMICC="moon run cmd/main --"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

test_program() {
  local name="$1"
  local source="$2"
  local expected="$3"
  echo -n "Testing $name... "
  $KIMICC "$source" > "$TMPDIR/$name.s"
  clang -o "$TMPDIR/$name" "$TMPDIR/$name.s"
  set +e
  "$TMPDIR/$name"
  local actual=$?
  set -e
  if [ "$actual" -eq "$expected" ]; then
    echo "PASS (exit code: $actual)"
  else
    echo "FAIL: expected $expected, got $actual"
    exit 1
  fi
}

# Basic tests
test_program "return_42" "int main() { return 42; }" 42
test_program "add" "int add(int a, int b) { return a + b; } int main() { return add(10, 32); }" 42
test_program "sub" "int main() { return 100 - 58; }" 42
test_program "mul" "int main() { return 6 * 7; }" 42
test_program "div" "int main() { return 126 / 3; }" 42
test_program "mod" "int main() { return 142 % 50; }" 42
test_program "neg" "int main() { return -(-42); }" 42
test_program "if_true" "int main() { if (1) return 42; else return 0; }" 42
test_program "if_false" "int main() { if (0) return 0; else return 42; }" 42
test_program "eq_true" "int main() { if (42 == 42) return 42; return 0; }" 42
test_program "ne_true" "int main() { if (42 != 0) return 42; return 0; }" 42
test_program "lt_true" "int main() { if (41 < 42) return 42; return 0; }" 42
test_program "le_true" "int main() { if (42 <= 42) return 42; return 0; }" 42
test_program "gt_true" "int main() { if (43 > 42) return 42; return 0; }" 42
test_program "ge_true" "int main() { if (42 >= 42) return 42; return 0; }" 42
test_program "while_loop" "int main() { int x = 0; while (x < 42) x = x + 1; return x; }" 42
test_program "var_assign" "int main() { int x = 10; x = 32; return x + 10; }" 42

# Array tests
test_program "array_sum" "int main() { int a[3]; a[0] = 1; a[1] = 2; a[2] = 3; return a[0] + a[1] + a[2]; }" 6
test_program "array_param" "int sum(int a[], int n) { int s = 0; int i = 0; while (i < n) { s = s + a[i]; i = i + 1; } return s; } int main() { int a[3]; a[0] = 10; a[1] = 20; a[2] = 12; return sum(a, 3); }" 42

# Struct tests
test_program "struct_member" "struct Point { int x; int y; }; int main() { struct Point p; p.x = 3; p.y = 4; return p.x + p.y; }" 7
test_program "struct_pointer" "struct Node { int data; struct Node* next; }; int main() { struct Node* n = malloc(sizeof(struct Node)); n->data = 42; return n->data; }" 42

# Linked list
test_program "linked_list" \
"struct Node { int data; struct Node* next; }; \
int sum_list(struct Node* head) { \
  int sum = 0; \
  while (head != 0) { sum = sum + head->data; head = head->next; } \
  return sum; \
} \
int main() { \
  struct Node* a = malloc(sizeof(struct Node)); \
  struct Node* b = malloc(sizeof(struct Node)); \
  struct Node* c = malloc(sizeof(struct Node)); \
  a->data = 10; a->next = b; \
  b->data = 20; b->next = c; \
  c->data = 12; c->next = 0; \
  return sum_list(a); \
}" 42

# Binary tree
test_program "binary_tree" \
"struct TreeNode { int val; struct TreeNode* left; struct TreeNode* right; }; \
int sum_tree(struct TreeNode* root) { \
  if (root == 0) return 0; \
  return root->val + sum_tree(root->left) + sum_tree(root->right); \
} \
int main() { \
  struct TreeNode* a = malloc(sizeof(struct TreeNode)); \
  struct TreeNode* b = malloc(sizeof(struct TreeNode)); \
  struct TreeNode* c = malloc(sizeof(struct TreeNode)); \
  a->val = 10; a->left = b; a->right = c; \
  b->val = 20; b->left = 0; b->right = 0; \
  c->val = 12; c->left = 0; c->right = 0; \
  return sum_tree(a); \
}" 42

# N-Queens
test_program "nqueens_4" \
"int abs(int x) { if (x < 0) return -x; return x; } \
int is_safe(int col[], int row, int col_idx) { \
  int i = 0; \
  while (i < col_idx) { \
    if (col[i] == row) return 0; \
    if (abs(col[i] - row) == abs(i - col_idx)) return 0; \
    i = i + 1; \
  } \
  return 1; \
} \
int solve(int col[], int n, int col_idx) { \
  int count = 0; int row = 0; \
  if (col_idx == n) return 1; \
  while (row < n) { \
    if (is_safe(col, row, col_idx)) { \
      col[col_idx] = row; \
      count = count + solve(col, n, col_idx + 1); \
    } \
    row = row + 1; \
  } \
  return count; \
} \
int main() { int col[4]; return solve(col, 4, 0); }" 2

test_program "nqueens_8" \
"int abs(int x) { if (x < 0) return -x; return x; } \
int is_safe(int col[], int row, int col_idx) { \
  int i = 0; \
  while (i < col_idx) { \
    if (col[i] == row) return 0; \
    if (abs(col[i] - row) == abs(i - col_idx)) return 0; \
    i = i + 1; \
  } \
  return 1; \
} \
int solve(int col[], int n, int col_idx) { \
  int count = 0; int row = 0; \
  if (col_idx == n) return 1; \
  while (row < n) { \
    if (is_safe(col, row, col_idx)) { \
      col[col_idx] = row; \
      count = count + solve(col, n, col_idx + 1); \
    } \
    row = row + 1; \
  } \
  return count; \
} \
int main() { int col[8]; return solve(col, 8, 0); }" 92

echo "All e2e tests passed!"
