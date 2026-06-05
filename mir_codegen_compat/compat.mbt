///|
/// Parsed-program compatibility wrapper around the strict MIR-module backend.
pub fn generate_assembly_for_target_strict(
  prog : @parser.Program,
  target : @target.Target,
) -> Result[String, String] {
  @mir_codegen.generate_assembly_from_mir_module_strict(
    @mir.lower_to_module(prog, target),
  )
}

///|
/// Transitional wrapper for callers that still hold MIR programs.
pub fn generate_assembly_from_mir_strict(
  mir : @mir.Program,
) -> Result[String, String] {
  @mir_codegen.generate_assembly_from_mir_module_strict(mir.to_module())
}

///|
/// Lowers a MIR program to a module and generates assembly through the
/// MIR-only backend, aborting if that backend's coverage is insufficient.
///
/// This is the non-strict counterpart of `generate_assembly_from_mir_strict`:
/// it returns the assembly text directly instead of a `Result`, mirroring
/// `@mir_codegen.generate_assembly_from_mir_module`. Prefer the `_strict`
/// variant when you want to fall back to the parser-AST backend on uncovered
/// constructs.
pub fn generate_assembly_from_mir(mir : @mir.Program) -> String {
  @mir_codegen.generate_assembly_from_mir_module(mir.to_module())
}

///|
/// Generates assembly for a parsed program, preferring the MIR backend and
/// falling back to the parser-AST backend when MIR coverage is insufficient.
///
/// The program is lowered to MIR and run through the strict MIR backend. If
/// that backend reports an uncovered construct (`Err`), this function silently
/// retries with `@codegen.generate_assembly_for_target`, which always succeeds
/// for the supported subset. The result is therefore the MIR backend's output
/// where available and the established parser-AST output everywhere else,
/// making this the safe default for the `cast -> mir -> codegen` path.
///
/// Parameters:
///
/// - `prog`: the parsed translation unit to compile.
/// - `target`: the output target selecting the assembly dialect.
///
/// Returns the generated assembly as a `String`.
pub fn generate_assembly_for_target_with_parser_fallback(
  prog : @parser.Program,
  target : @target.Target,
) -> String {
  match generate_assembly_from_mir_strict(@mir.lower(prog, target)) {
    Ok(assembly) => assembly
    Err(_) => @codegen.generate_assembly_for_target(prog, target)
  }
}

///|
/// Generates assembly for a parsed program using the parser-AST backend.
///
/// This is a thin re-export of `@codegen.generate_assembly_for_target`. It lets
/// callers depend only on this compatibility package while choosing the legacy
/// `cast -> codegen` path explicitly, in contrast to
/// `generate_assembly_for_target_with_parser_fallback`, which prefers MIR.
///
/// Parameters:
///
/// - `prog`: the parsed translation unit to compile.
/// - `target`: the output target selecting the assembly dialect.
///
/// Returns the generated assembly as a `String`.
pub fn generate_assembly_for_target(
  prog : @parser.Program,
  target : @target.Target,
) -> String {
  @codegen.generate_assembly_for_target(prog, target)
}
