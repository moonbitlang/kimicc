#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${KIMICC_LINUX_AMD64_SMOKE_IMAGE:-kimicc-linux-amd64-smoke:ubuntu24.04}"

build_args=(
  --platform linux/amd64
  -f "$repo/scripts/linux-amd64-smoke.Dockerfile"
  -t "$image"
)

if [ "${KIMICC_LINUX_AMD64_SMOKE_NO_CACHE:-0}" = "1" ]; then
  build_args+=(--no-cache)
fi

docker build "${build_args[@]}" "$repo"
