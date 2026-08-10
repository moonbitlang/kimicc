///|
/// Prefix of the labels MIR synthesizes for `case` and `default` clauses.
///
/// The AST spells a clause as `Case`/`Default` wrapping a statement, with no
/// name attached, so lowering invents one label per clause for the switch
/// dispatch to branch to. Double-underscore names are reserved to the
/// implementation, so a program cannot legally collide with these.
const SYNTHETIC_SWITCH_LABEL_PREFIX = "__kimicc_case_"

///|
/// Reports whether a MIR label was synthesized for a `case` or `default`
/// clause rather than written in the program.
///
/// A backend needs this because the two are spelled the same way in MIR and
/// assembled differently: a written label becomes a named assembly label that
/// `goto` and `&&label` can reach, while a clause label is internal to one
/// switch and takes an anonymous one.
pub fn is_synthetic_switch_label(name : String) -> Bool {
  name.has_prefix(SYNTHETIC_SWITCH_LABEL_PREFIX)
}
