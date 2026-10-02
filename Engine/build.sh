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
bash build-metal.sh
# Preserve a symbol-rich build locally. Ship only the stripped executable.
cp .build/release/PhononSwift .build/release/PhononSwift-distribution
xcrun strip .build/release/PhononSwift-distribution
echo "Built $PWD/.build/release/PhononSwift"
