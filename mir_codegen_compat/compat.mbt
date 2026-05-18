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
/// Transitional wrapper for callers that still hold MIR programs with parser
/// fallback source attached.
pub fn generate_assembly_from_mir_strict(
  mir : @mir.Program,
) -> Result[String, String] {
  @mir_codegen.generate_assembly_from_mir_module_strict(mir.to_module())
}

///|
pub fn generate_assembly_from_mir(mir : @mir.Program) -> String {
  @mir_codegen.generate_assembly_from_mir_module(mir.to_module())
}

///|
/// Explicit parser fallback path for tests and migration-only callers.
pub fn generate_assembly_from_mir_with_parser_fallback(
  mir : @mir.Program,
) -> String {
  match generate_assembly_from_mir_strict(mir) {
    Ok(assembly) => assembly
    Err(_) => @codegen.generate_assembly_for_target(mir.source, mir.target)
  }
}

///|
pub fn generate_assembly_for_target_with_parser_fallback(
  prog : @parser.Program,
  target : @target.Target,
) -> String {
  generate_assembly_from_mir_with_parser_fallback(@mir.lower(prog, target))
}

///|
pub fn generate_assembly_for_target(
  prog : @parser.Program,
  target : @target.Target,
) -> String {
  @codegen.generate_assembly_for_target(prog, target)
}
