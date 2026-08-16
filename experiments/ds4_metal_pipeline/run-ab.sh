#!/usr/bin/env bash
# Drop-in A/B for a generated Metal kernel inside ds4's real engine.
#
# ds4 loads metal/*.metal at startup and honours DS4_METAL_MOE_SOURCE, so
# a patched shader needs no rebuild -- the entire loop is: patch a file,
# point the env var at it, run, compare frontier logits against stock.
#
# Usage: run-ab.sh <patched-moe.metal|stock> <label>
# Env:   DS4_HOME (default $HOME), OUT (default /tmp/kimicc_metal_ab)
set -euo pipefail

patched="${1:?usage: run-ab.sh <patched-moe.metal|stock> <label>}"
label="${2:?missing label}"
ds4_dir="${DS4_HOME:-$HOME}/git/ds4"
out="${OUT:-/tmp/kimicc_metal_ab}/${label}"
mkdir -p "${out}"

args=(--metal -m "${ds4_dir}/ds4flash.gguf"
      --prompt-file tests/long_context_story_prompt.txt
      --ctx-start 256 --ctx-max 256 --gen-tokens "${GEN_TOKENS:-2}"
      --csv "${out}/bench.csv" --dump-frontier-logits-dir "${out}")

if [[ "${patched}" == "stock" ]]; then
  ( cd "${ds4_dir}" && ./ds4-bench "${args[@]}" ) > "${out}/run.log" 2>&1
else
  ( cd "${ds4_dir}" && DS4_METAL_MOE_SOURCE="${patched}" \
      ./ds4-bench "${args[@]}" ) > "${out}/run.log" 2>&1
fi
echo "${label}: $(tail -1 "${out}/bench.csv")"
