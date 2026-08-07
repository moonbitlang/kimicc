///|
/// C expression precedence levels, loosest first.
///
/// `print_expr_at` renders a subexpression with the minimum precedence its
/// position tolerates and parenthesizes anything looser, which is what keeps
/// the printed text parsing back to the same tree.
const PREC_COMMA : Int = 0

///|
const PREC_ASSIGN : Int = 1

///|
const PREC_TERNARY : Int = 2

///|
const PREC_LOGICAL_OR : Int = 3

///|
const PREC_LOGICAL_AND : Int = 4

///|
const PREC_BIT_OR : Int = 5

///|
const PREC_BIT_XOR : Int = 6

///|
const PREC_BIT_AND : Int = 7

///|
const PREC_EQUALITY : Int = 8

///|
const PREC_RELATIONAL : Int = 9

///|
const PREC_SHIFT : Int = 10

///|
const PREC_ADDITIVE : Int = 11

///|
const PREC_MULTIPLICATIVE : Int = 12

///|
const PREC_UNARY : Int = 13

///|
const PREC_POSTFIX : Int = 14

///|
const PREC_PRIMARY : Int = 15

///|
/// Returns the precedence of a binary operator spelling.
fn binary_precedence(op : String) -> Int {
  match op {
    "," => PREC_COMMA
    "||" => PREC_LOGICAL_OR
    "&&" => PREC_LOGICAL_AND
    "|" => PREC_BIT_OR
    "^" => PREC_BIT_XOR
    "&" => PREC_BIT_AND
    "==" | "!=" => PREC_EQUALITY
    "<" | ">" | "<=" | ">=" => PREC_RELATIONAL
    "<<" | ">>" => PREC_SHIFT
    "+" | "-" => PREC_ADDITIVE
    "*" | "/" | "%" => PREC_MULTIPLICATIVE
    // An operator the parser produced but this table does not know binds
    // tightest, so it always gets parenthesized rather than silently
    // reassociating.
    _ => PREC_PRIMARY
  }
}

///|
/// Renders an expression as C source.
///
/// Output is canonical rather than source-preserving: parentheses appear only
/// where precedence requires them, and `(*p).f` is printed as `p->f`.
///
/// ```mbt check
/// test {
///   inspect(
///     @printer.print_expr(
///       Binary(
///         "*",
///         Binary("+", Number(1, SInt), Number(2, SInt)),
///         Number(3, SInt),
///       ),
///     ),
///     content="(1 + 2) * 3",
///   )
/// }
/// ```
pub fn print_expr(expr : @parser.Expr) -> String {
  print_expr_at(expr, PREC_COMMA)
}

///|
/// Renders `expr`, wrapping it in parentheses when its precedence is looser
/// than `min_prec` allows.
fn print_expr_at(expr : @parser.Expr, min_prec : Int) -> String {
  let (text, prec) = render_expr(expr)
  if prec < min_prec {
    "(" + text + ")"
  } else {
    text
  }
}

///|
/// Renders an expression and reports the precedence of its outermost operator.
fn render_expr(expr : @parser.Expr) -> (String, Int) {
  match expr {
    Number(value, ty) => (print_integer(value, ty), PREC_PRIMARY)
    FloatLiteral(value, ty) => (print_double(value, ty), PREC_PRIMARY)
    String(value) => ("\"" + escape_string(value) + "\"", PREC_PRIMARY)
    Var(name) => (name, PREC_PRIMARY)
    Binary(op, lhs, rhs) => {
      let prec = binary_precedence(op)
      // Every binary operator here is left-associative, so the right operand
      // needs one more level to keep `a - (b - c)` from losing its parentheses.
      let text = print_expr_at(lhs, prec) +
        " " +
        op +
        " " +
        print_expr_at(rhs, prec + 1)
      (text, prec)
    }
    Unary(op, operand) => {
      let rendered = print_expr_at(operand, PREC_UNARY)
      // `- -x` and `+ +x` need the space; without it they lex as `--` and `++`.
      let separator = if needs_unary_space(op, rendered) { " " } else { "" }
      (op + separator + rendered, PREC_UNARY)
    }
    Call(callee, args) =>
      (
        print_expr_at(callee, PREC_POSTFIX) + "(" + print_arguments(args) + ")",
        PREC_POSTFIX,
      )
    Assign(target, value) =>
      // Assignment is right-associative, so the target binds tighter.
      (
        print_expr_at(target, PREC_ASSIGN + 1) +
        " = " +
        print_expr_at(value, PREC_ASSIGN),
        PREC_ASSIGN,
      )
    CompoundAssign(op, target, value) =>
      (
        print_expr_at(target, PREC_ASSIGN + 1) +
        " " +
        op +
        "= " +
        print_expr_at(value, PREC_ASSIGN),
        PREC_ASSIGN,
      )
    // `(*p).f` is spelled `p->f`, which parses back to this exact shape.
    MemberAccess(Deref(base), field) =>
      (print_expr_at(base, PREC_POSTFIX) + "->" + field, PREC_POSTFIX)
    MemberAccess(base, field) =>
      (print_expr_at(base, PREC_POSTFIX) + "." + field, PREC_POSTFIX)
    Deref(operand) => ("*" + print_expr_at(operand, PREC_UNARY), PREC_UNARY)
    AddrOf(operand) => ("&" + print_expr_at(operand, PREC_UNARY), PREC_UNARY)
    ArrayAccess(base, index) =>
      (
        print_expr_at(base, PREC_POSTFIX) + "[" + print_expr(index) + "]",
        PREC_POSTFIX,
      )
    Sizeof(ty) => ("sizeof(" + print_type(ty) + ")", PREC_POSTFIX)
    SizeofExpr(operand) =>
      // Always parenthesized: `sizeof x` would swallow a following `[0]`.
      ("sizeof(" + print_expr(operand) + ")", PREC_POSTFIX)
    Alignof(ty) => ("_Alignof(" + print_type(ty) + ")", PREC_POSTFIX)
    AlignofExpr(operand) =>
      ("_Alignof(" + print_expr(operand) + ")", PREC_POSTFIX)
    Cast(ty, operand) =>
      (
        "(" + print_type(ty) + ")" + print_expr_at(operand, PREC_UNARY),
        PREC_UNARY,
      )
    PrefixInc(operand) =>
      ("++" + print_expr_at(operand, PREC_UNARY), PREC_UNARY)
    PrefixDec(operand) =>
      ("--" + print_expr_at(operand, PREC_UNARY), PREC_UNARY)
    PostfixInc(operand) =>
      (print_expr_at(operand, PREC_POSTFIX) + "++", PREC_POSTFIX)
    PostfixDec(operand) =>
      (print_expr_at(operand, PREC_POSTFIX) + "--", PREC_POSTFIX)
    Ternary(cond, then_expr, else_expr) =>
      // The middle operand sits between `?` and `:` and may be any expression;
      // the branches are conditional-expressions, hence the asymmetry.
      (
        print_expr_at(cond, PREC_TERNARY + 1) +
        " ? " +
        print_expr(then_expr) +
        " : " +
        print_expr_at(else_expr, PREC_TERNARY),
        PREC_TERNARY,
      )
    LabelAddr(label) => ("&&" + label, PREC_UNARY)
    VaArg(list, ty) =>
      (
        "__builtin_va_arg(" +
        print_expr_at(list, PREC_ASSIGN) +
        ", " +
        print_type(ty) +
        ")",
        PREC_POSTFIX,
      )
    OffsetOf(ty, path) =>
      (
        "__builtin_offsetof(" +
        print_type(ty) +
        ", " +
        print_offset_path(path) +
        ")",
        PREC_POSTFIX,
      )
    Array(elements) => ("{ " + print_arguments(elements) + " }", PREC_PRIMARY)
    CompoundLiteral(ty, elements, _) =>
      // The trailing counter is a parser-assigned identity for the generated
      // storage, not syntax, so it is not printed. Reparsing assigns a fresh
      // one in the same order.
      (
        "(" + print_type(ty) + "){ " + print_arguments(elements) + " }",
        PREC_POSTFIX,
      )
    DesignatedField(_, _) | DesignatedIndex(_, _) | DesignatedRange(_, _, _) =>
      (print_designator(expr), PREC_ASSIGN)
  }
}

///|
/// Renders an initializer designator, following a chain to its value.
///
/// Designators nest in the AST, so `.u.float64 = x` is a `DesignatedField`
/// whose value is another `DesignatedField`. Printing each level as
/// `.name = value` independently would emit `.u = .float64 = x`, which is not C
/// -- the chain has to be concatenated and the `=` written once, at the end.
fn print_designator(expr : @parser.Expr) -> String {
  match expr {
    DesignatedField(field, value) => "." + field + print_designator_tail(value)
    DesignatedIndex(index, value) =>
      "[" + index.to_string() + "]" + print_designator_tail(value)
    DesignatedRange(low, high, value) =>
      "[" +
      low.to_string() +
      " ... " +
      high.to_string() +
      "]" +
      print_designator_tail(value)
    other => print_expr_at(other, PREC_ASSIGN)
  }
}

///|
/// Renders what follows a designator: either more of the chain, or the assigned
/// value.
fn print_designator_tail(expr : @parser.Expr) -> String {
  match expr {
    DesignatedField(_, _) | DesignatedIndex(_, _) | DesignatedRange(_, _, _) =>
      print_designator(expr)
    value => " = " + print_expr_at(value, PREC_ASSIGN)
  }
}

///|
/// Hexadecimal digits, indexed by nibble value.
let hex_digits : ReadOnlyArray[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
]

///|
/// Renders an integer literal so that it reads back as the same 64-bit value.
///
/// C has no negative integer literals: `-5` is unary minus applied to `5`, and
/// the parser does not fold that back into a literal, so printing a negative
/// value as decimal would re-parse as `Unary("-", ...)` -- a different tree.
///
/// A negative value here is not a user-written negation anyway. It is the
/// 64-bit pattern of a literal that overflowed the signed range, such as
/// `10000000000000000000` or `0x8000000000000000`, so the honest spelling is
/// the pattern itself: one hexadecimal token, same bits, no negation involved.
fn print_integer(value : Int64, ty : @ctype.Type) -> String {
  if value >= 0L {
    return value.to_string() + integer_suffix(ty)
  }
  let buf = StringBuilder::new()
  buf.write_string("0x")
  for shift = 60; shift >= 0; shift = shift - 4 {
    buf.write_char(hex_digits[((value >> shift) & 0xfL).to_int()])
  }
  buf.write_string(integer_suffix(ty))
  buf.to_string()
}

///|
/// Returns the suffix that makes a literal reparse with type `ty`.
///
/// A bare literal already takes the first type that can hold its value, so
/// `int` and the widths a bare literal would select anyway need nothing. The
/// rest have to say so, or the type is lost on the way back in.
fn integer_suffix(ty : @ctype.Type) -> String {
  match ty {
    UInt => "u"
    SLong => "L"
    ULong => "uL"
    SLongLong => "LL"
    ULongLong => "uLL"
    _ => ""
  }
}

///|
/// Reports whether a unary operator needs a space before its operand to avoid
/// lexing into a longer token.
fn needs_unary_space(op : String, rendered : String) -> Bool {
  guard rendered is [first, ..] else { return false }
  (op is "-" && first is '-') || (op is "+" && first is '+')
}

///|
/// Renders a comma-separated argument or initializer list.
///
/// Each element is printed at assignment precedence so that a comma operator
/// inside one gets parenthesized instead of splitting the list.
fn print_arguments(args : ArrayView[@parser.Expr]) -> String {
  let parts = []
  for arg in args {
    parts.push(print_expr_at(arg, PREC_ASSIGN))
  }
  parts.join(", ")
}

///|
/// Renders an `offsetof` member path.
fn print_offset_path(path : ArrayView[@ctype.OffsetDesignator]) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for step in path {
    match step {
      OffsetField(name) => {
        if !first {
          buf.write_string(".")
        }
        buf.write_string(name)
      }
      OffsetIndex(index) => {
        buf.write_string("[")
        buf.write_string(index.to_string())
        buf.write_string("]")
      }
    }
    first = false
  }
  buf.to_string()
}

///|
/// Renders a floating literal so that it reads back as a `double`.
///
/// MoonBit prints whole doubles without a fractional part, which C would lex as
/// an integer constant, so a `.0` is appended when nothing marks it as
/// floating.
fn print_double(value : Double, ty : @ctype.Type) -> String {
  let text = value.to_string()
  let mut floating = false
  for ch in text {
    if ch is ('.' | 'e' | 'E' | 'n' | 'i') {
      floating = true
      break
    }
  }
  let body = if floating { text } else { text + ".0" }
  match ty {
    Float => body + "f"
    LongDouble => body + "L"
    _ => body
  }
}

///|
/// Escapes a string literal body.
///
/// The lexer decodes escapes when it builds the token, so the stored value is
/// raw bytes and has to be re-escaped here. Non-printable bytes use three-digit
/// octal rather than `\x`, because a hex escape has no length limit in C and
/// would absorb any following hex digit.
fn escape_string(value : String) -> String {
  let buf = StringBuilder::new()
  for ch in value {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\t' => buf.write_string("\\t")
      '\r' => buf.write_string("\\r")
      _ =>
        if ch.to_int() < 32 || ch.to_int() > 126 {
          buf.write_string(octal_escape(ch.to_int()))
        } else {
          buf.write_char(ch)
        }
    }
  }
  buf.to_string()
}

///|
/// Formats a byte as a three-digit octal escape.
fn octal_escape(code : Int) -> String {
  let digits = code & 0xff
  let hundreds = digits / 64
  let tens = digits / 8 % 8
  let ones = digits % 8
  "\\" + hundreds.to_string() + tens.to_string() + ones.to_string()
}
