#!/usr/bin/env python3
"""Compare two frontier-logit dumps from ds4-bench.

The referee for a Metal drop-in. Bit-exactness is unavailable on GPU --
accumulation order differs -- so this reports the max absolute deviation
across the full vocabulary and whether the argmax moved, and exits
non-zero when either exceeds the given bound.

Usage: compare-logits.py <dir-a> <dir-b> [max_abs_diff]
"""
import json, sys, glob, os

a_dir, b_dir = sys.argv[1], sys.argv[2]
bound = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5

name = os.path.basename(sorted(glob.glob(os.path.join(a_dir, "*.logits.json")))[0])
a = json.load(open(os.path.join(a_dir, name)))
b = json.load(open(os.path.join(b_dir, name)))
la, lb = a["logits"], b["logits"]
if len(la) != len(lb):
    raise SystemExit("vocab size mismatch: %d vs %d" % (len(la), len(lb)))
mx = max(abs(x - y) for x, y in zip(la, lb))
same = a["argmax_id"] == b["argmax_id"]
print("vocab=%d  argmax %d vs %d (%s)  max_abs_diff=%.6g  bound=%.3g"
      % (len(la), a["argmax_id"], b["argmax_id"],
         "same" if same else "MOVED", mx, bound))
sys.exit(0 if same and mx <= bound else 1)
