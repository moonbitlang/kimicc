#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${KIMICC_LINUX_AMD64_SMOKE_IMAGE:-kimicc-linux-amd64-smoke:ubuntu24.04}"

docker build --platform linux/amd64 \
  -f "$repo/scripts/linux-amd64-smoke.Dockerfile" \
  -t "$image" \
  "$repo"
