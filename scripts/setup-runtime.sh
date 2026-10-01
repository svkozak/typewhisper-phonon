#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -m)" == arm64 ]] || { echo "Apple Silicon required"; exit 1; }
command -v uv >/dev/null || { echo "Install uv from the official Astral distribution or Homebrew registry first."; exit 1; }
[[ ! -e .venv && ! -e .python ]] || { echo "Runtime already exists; preserving it. Use existing .venv or choose a fresh checkout."; exit 1; }
uv python install 3.12.12 --install-dir "$PWD/.python"
uv venv --python "$PWD/.python/cpython-3.12.12-macos-aarch64-none/bin/python3" .venv
uv pip sync --python .venv/bin/python --index-url https://pypi.org/simple requirements.lock
.venv/bin/python -c 'import platform; import mlx.core as mx; assert platform.machine()=="arm64"; print(mx.default_device())'
