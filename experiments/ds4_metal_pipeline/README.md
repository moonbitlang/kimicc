# Metal drop-in pipeline

Swaps a generated Metal kernel into ds4's real engine and refereed it
against stock, with no rebuild.

ds4 concatenates `metal/*.metal` into one library at startup and honours
a per-file environment override so "a diagnostic run can swap one source
file without changing the executable". That makes the whole loop free:

    patch-moe.py  ~/git/ds4/metal/moe.metal  out.metal  --canary
    DS4_METAL_MOE_SOURCE=out.metal ./ds4-bench --metal ...

`run-ab.sh` wraps that, `compare-logits.py` is the referee.

## Verified so far

The override is honoured: a deliberate syntax error in the patched file
fails shader compilation ("program_source:12441:1: error"), proving ds4
reads it.

## The measurement trap, found by the canary

A 1% perturbation planted in `kernel_mul_mv_addr_iq2_xxs_pair_swiglu_f32`
produced **zero** change in the frontier logits. Not because the patch
failed, but because the referee was watching the wrong phase:

- `--dump-frontier-logits-dir` writes after **prefill**.
- Prefill is batched and runs the `mul_mm` **matmul** family.
- The IQ2_XXS pair-swiglu kernel is a `mul_mv` **matvec**, reached only
  during single-token **decode**.

So the logits dump cannot see any decode-path kernel. This is the same
trap codex identified for the CPU drop-in, where the frontier dump lands
post-prefill and exercises only one of the four patched widths.

**Do not trust a passing logits comparison for a decode kernel.** A
referee for this kernel has to observe decode output -- generated token
sequences, or a decode-phase logit capture -- and the canary must be
shown to move it before any passing result means anything.
