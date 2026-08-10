///|
/// The assembly labels a `switch` reserved for its own `case` and `default`
/// clauses, in source order, and how many of them the body has emitted.
///
/// The dispatch is emitted before the body, so every clause needs a label
/// before the statement carrying it is reached; `emitted` is what hands them
/// back out in the order the body reaches them.
struct SwitchClauses {
  labels : ReadOnlyArray[String]
  mut emitted : Int
}

///|
/// Returns the label reserved for the clause the body has just reached.
///
/// Aborts on a `case` outside any `switch`, which is invalid C that neither
/// the parser nor the semantic check rejects today.
fn Codegen::next_switch_clause_label(self : Codegen) -> String {
  guard self.switch_clauses.last() is Some(clauses) &&
    clauses.emitted < clauses.labels.length() else {
    abort("case or default label outside of switch")
  }
  let label = clauses.labels[clauses.emitted]
  clauses.emitted += 1
  label
}

///|
/// Returns the label reserved for the clause the body has just reached.
///
/// Aborts on a `case` outside any `switch`, which is invalid C that neither
/// the parser nor the semantic check rejects today.
fn X64Codegen::next_switch_clause_label(self : X64Codegen) -> String {
  guard self.switch_clauses.last() is Some(clauses) &&
    clauses.emitted < clauses.labels.length() else {
    abort("case or default label outside of switch")
  }
  let label = clauses.labels[clauses.emitted]
  clauses.emitted += 1
  label
}

///|
/// Checks that the body emitted every clause the dispatch reserved a label for.
///
/// The two walks are matched up by position, so a construct one descends into
/// and the other does not would otherwise surface as an assembler error about
/// an undefined symbol, a long way from the traversal that dropped it.
fn check_switch_clauses_emitted(clauses : SwitchClauses?) -> Unit {
  guard clauses is Some(clauses) && clauses.emitted == clauses.labels.length() else {
    abort("switch body did not emit every case label")
  }
}

///|
/// Collects the clauses one `switch` owns, in the order its body emits them:
/// `Some(value)` for `case value:` and `None` for `default:`.
///
/// The walk stops at a nested `switch`, which owns its own clauses, and must
/// visit statements in the same order the code generator does -- the two are
/// matched up by position.
fn collect_switch_clauses(stmt : @parser.Stmt, out : Array[Int64?]) -> Unit {
  match stmt {
    Case(value, body) => {
      out.push(Some(value))
      collect_switch_clauses(body, out)
    }
    Default(body) => {
      out.push(None)
      collect_switch_clauses(body, out)
    }
    Label(_, body) => collect_switch_clauses(body, out)
    Compound(stmts) | StmtList(stmts) =>
      for nested in stmts {
        collect_switch_clauses(nested, out)
      }
    If(_, then_, else_) => {
      collect_switch_clauses(then_, out)
      if else_ is Some(alternative) {
        collect_switch_clauses(alternative, out)
      }
    }
    While(_, body) | DoWhile(_, body) => collect_switch_clauses(body, out)
    For(init, _, _, body) => {
      if init is Some(stmt) {
        collect_switch_clauses(stmt, out)
      }
      collect_switch_clauses(body, out)
    }
    Switch(_, _) => ()
    _ => ()
  }
}
