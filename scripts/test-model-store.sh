#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-26.6.0.app/Contents/Developer}"
[[ $# == 1 ]] || { echo 'Usage: test-model-store.sh PATH_TO_PINNED_MODEL_ARCHIVE'; exit 1; }
native="$PWD/prototypes/phonon-swift"
objects="$native/.build/arm64-apple-macosx/release/CZstd.build"
xcrun swiftc -swift-version 6 -parse-as-library -Xcc "-fmodule-map-file=$objects/module.modulemap" -I "$native/Sources/CZstd/include" "$native/Sources/PhononSwift/ModelStore.swift" Sources/ModelStoreTest.swift "$objects"/*.o -o build/model-store-test
build/model-store-test "$1"
