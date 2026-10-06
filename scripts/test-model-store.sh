#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-26.6.0.app/Contents/Developer}"
[[ $# == 1 ]] || { echo 'Usage: test-model-store.sh PATH_TO_VERIFIED_COREML_MODEL_DIRECTORY'; exit 1; }
xcrun swiftc -swift-version 6 -target arm64-apple-macos15.0 -parse-as-library Engine/Sources/PhononSwift/EngineError.swift Engine/Sources/PhononSwift/ModelStore.swift Sources/ModelStoreTest.swift -o build/model-store-test
build/model-store-test "$1"
