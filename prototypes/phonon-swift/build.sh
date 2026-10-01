#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-26.6.0.app/Contents/Developer}"
xcrun swift package resolve
checkout="$PWD/.build/checkouts/mlx-audio-swift"
patch_file="$PWD/patches/mlx-audio-swift-compile.patch"
if ! git -C "$checkout" apply --reverse --check "$patch_file" 2>/dev/null; then
    git -C "$checkout" apply --check "$patch_file"
    chmod u+w "$checkout/Sources/MLXAudioSTT/Models/Parakeet/ParakeetModel.swift"
    git -C "$checkout" apply "$patch_file"
fi
xcrun swift build -c release -j 8
# SwiftPM does not compile Metal resources. For this experiment, reuse the
# precompiled Metal library from the already-installed, matching MLX 0.32.3 wheel.
# The standalone executable then needs neither Python nor the wheel at runtime.
# A production build must compile/package its own matching Metal library.
metal_library="${1:-../../.venv/lib/python3.12/site-packages/mlx/lib/mlx.metallib}"
[[ -f "$metal_library" ]] || { echo 'Pass the path to the MLX 0.32.3 mlx.metallib as the first argument.'; exit 1; }
cp "$metal_library" .build/release/mlx.metallib
echo "Built $PWD/.build/release/PhononSwift"
