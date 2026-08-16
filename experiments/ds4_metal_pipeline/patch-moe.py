#!/usr/bin/env python3
"""Build a patched copy of ds4's metal/moe.metal for a drop-in A/B run.

ds4 concatenates metal/*.metal into one Metal library at startup and
honours a per-file environment override (`DS4_METAL_MOE_SOURCE`) so a
diagnostic run can swap one shader without touching the executable. That
makes the whole drop-in loop free: no rebuild, no tree copy, no linker
work -- write a patched file, point the env var at it, run.

Two modes:

  --canary       Perturb ds4's own IQ2_XXS pair-swiglu epilogue by 1%.
                 Proves the override is live before any passing result is
                 trusted: a kernel that never gets dispatched is
                 indistinguishable from a correct one.

  --replace F    Replace the named kernel's definition with the contents
                 of F (a generated kernel carrying the same signature).

Usage:
  patch-moe.py <ds4-moe.metal> <output.metal> --canary
  patch-moe.py <ds4-moe.metal> <output.metal> --replace generated.metal
                                              [--kernel NAME]
"""
import sys

KERNEL = "kernel_mul_mv_addr_iq2_xxs_pair_swiglu_f32"
CANARY_FROM = "            mid_f32[out_row] = silu * u * route_weight;"
CANARY_TO = (
    "            mid_f32[out_row] = silu * u * route_weight * 1.01f;"
    " /* kimicc canary */"
)


def find_kernel_span(src, name):
    """Byte span of `kernel void NAME(...) { ... }`, brace-balanced."""
    marker = "kernel void " + name + "("
    start = src.index(marker)
    open_brace = src.index("{", src.index(")", start))
    depth, i = 0, open_brace
    while i < len(src):
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return start, i + 1
        i += 1
    raise SystemExit("unbalanced braces in " + name)


def main():
    args = sys.argv[1:]
    if len(args) < 3:
        raise SystemExit(__doc__)
    src_path, out_path, mode = args[0], args[1], args[2]
    kernel = KERNEL
    if "--kernel" in args:
        kernel = args[args.index("--kernel") + 1]
    src = open(src_path).read()

    if mode == "--canary":
        if src.count(CANARY_FROM) < 1:
            raise SystemExit("canary anchor not found; ds4 source changed?")
        out = src.replace(CANARY_FROM, CANARY_TO, 1)
        note = "canary: 1%% perturbation in %s epilogue" % kernel
    elif mode == "--replace":
        replacement = open(args[args.index("--replace") + 1]).read()
        start, end = find_kernel_span(src, kernel)
        out = src[:start] + replacement + src[end:]
        note = "replaced %s (%d -> %d bytes)" % (kernel, end - start, len(replacement))
    else:
        raise SystemExit("unknown mode " + mode)

    open(out_path, "w").write(out)
    print("wrote %s: %s" % (out_path, note))


if __name__ == "__main__":
    main()
