#!/usr/bin/env python3
"""Patch a copy of ds4.c so its q8_0 row dot dispatches to generated kernels.

Usage: ds4-dropin-patch.py <ds4.c-path> <generated-kernels-file> <widths...>

The generated kernels (from `@ds4_kernels.generate_q8_neon_kernels`) are
pasted immediately before ds4's own `dot_q8_0_row`, and a dispatch chain
is inserted at the top of its body: listed widths return the generated
NEON kernel, everything else falls through to ds4's original code. The
seam stays a function boundary -- ds4's callers, threading, and layout
are untouched, which is what makes the A/B an apples-to-apples run.

With `--count`, each dispatch arm also bumps a per-width counter and an
exit hook prints `kimicc_hits ...` to stderr -- the coverage build's
proof that every generated kernel actually ran. The counters are atomic
(the workers are multithreaded) and cost a fetch-add per row dot, so the
timed A/B builds are patched without them.

The file is patched in place; run this only on a scratch copy.
"""
import sys

args = sys.argv[1:]
count = "--count" in args
if count:
    args.remove("--count")
path, kernels_path = args[0], args[1]
widths = [int(w) for w in args[2:]]
if not widths:
    sys.exit("no widths given")

src = open(path).read()
kernels = open(kernels_path).read()

marker = "static inline float dot_q8_0_row("
i = src.index(marker)
brace = src.index("{", i)

counters = ""
if count:
    for w in widths:
        counters += "static unsigned long long kimicc_hits_%d;\n" % w
    report = 'fprintf(stderr, "kimicc_hits'
    report_args = ""
    for w in widths:
        report += " %d=%%llu" % w
        report_args += ", kimicc_hits_%d" % w
    counters += (
        "static void kimicc_report_hits(void) {\n"
        "    " + report + '\\n"' + report_args + ");\n"
        "}\n"
        "__attribute__((constructor)) static void kimicc_arm_report(void) {\n"
        "    atexit(kimicc_report_hits);\n"
        "}\n"
    )

dispatch = (
    "\n#if defined(__ARM_FEATURE_DOTPROD)\n"
    "    /* kimicc drop-in: generated NEON kernels for the model's widths. */\n"
)
for w in widths:
    bump = ""
    if count:
        bump = (
            "        __atomic_fetch_add(&kimicc_hits_%d, 1ULL, __ATOMIC_RELAXED);\n"
            % w
        )
    dispatch += (
        "    if (in_dim == %du && blocks == %du) {\n" % (w, w // 32)
        + bump
        + "        return gen_dot_q8_0_row_neon_%d((unsigned char *)row,\n"
        "                                        (int8_t *)xq, (float *)xscale);\n"
        "    }\n" % w
    )
dispatch += "#endif\n"

patched = (
    src[:i]
    + "/* ---- kimicc generated kernels (drop-in A/B) ---- */\n"
    + "#if defined(__ARM_FEATURE_DOTPROD)\n"
    + counters
    + kernels
    + "\n#endif\n"
    + "/* ---- end generated kernels ---- */\n\n"
    + src[i : brace + 1]
    + dispatch
    + src[brace + 1 :]
)
open(path, "w").write(patched)
print(
    "patched %s: dispatch for widths %s%s"
    % (path, widths, " with hit counters" if count else "")
)
