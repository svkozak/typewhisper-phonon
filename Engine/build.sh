#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-26.6.0.app/Contents/Developer}"
xcrun swift package resolve
xcrun swift build -c release -j 8
# Preserve a symbol-rich build locally. Ship only the stripped executable.
cp .build/release/PhononSwift .build/release/PhononSwift-distribution
xcrun strip .build/release/PhononSwift-distribution
echo "Built $PWD/.build/release/PhononSwift"
