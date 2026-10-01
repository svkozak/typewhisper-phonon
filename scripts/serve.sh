#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export HF_HOME="$PWD/.cache/huggingface"
exec .venv/bin/fermion serve phonon-2 --host 127.0.0.1 --port 8010
