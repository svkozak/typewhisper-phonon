#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -m)" == arm64 ]] || { echo "Apple Silicon required"; exit 1; }
host_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' /Applications/TypeWhisper.app/Contents/Info.plist)
[[ "$host_version" == 1.6.1 ]] || { echo "Requires TypeWhisper 1.6.1; found $host_version. Rebuild SDK against that host before proceeding."; exit 1; }
# CLT lacks the SwiftUI compiler plugins on this Mac. Use a full installed Xcode
# per invocation, without changing the user's global developer-tool selection.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == /Library/Developer/CommandLineTools ]]; then
    if [[ -d /Applications/Xcode-26.6.0.app ]]; then
        export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
    elif [[ -d /Applications/Xcode.app ]]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    else
        echo 'Set DEVELOPER_DIR to a full Xcode installation before building.'; exit 1
    fi
fi
frameworks=/Applications/TypeWhisper.app/Contents/Frameworks
mkdir -p build/PhononPlugin.bundle/Contents/{MacOS,Resources}
# This script builds the Python variant. The native builder adds its generated
# helper only after this step, so switching variants cannot reuse stale engines.
rm -rf build/PhononPlugin.bundle/Contents/Resources/Native
python3 - "$PWD" <<'PY'
import json,sys,pathlib
root=sys.argv[1]
pathlib.Path('build/RuntimeLocation.swift').write_text('enum RuntimeLocation { static let directory = '+json.dumps(root)+' }\n')
PY
flags=(-swift-version 6 -target arm64-apple-macos14.0 -I build -F "$frameworks" -framework TypeWhisperPluginSDK -Xlinker -rpath -Xlinker "$frameworks")
sources=(Sources/PhononPlugin.swift Sources/PhononServer.swift Sources/PhononRuntime.swift build/RuntimeLocation.swift)
xcrun swiftc -emit-module -module-name TypeWhisperPluginSDK -swift-version 6 -target arm64-apple-macos14.0 vendor/TypeWhisperPluginSDK/*.swift -emit-module-path build/TypeWhisperPluginSDK.swiftmodule
xcrun swiftc -emit-library -module-name PhononPlugin "${flags[@]}" "${sources[@]}" -o build/PhononPlugin.bundle/Contents/MacOS/PhononPlugin
cp Resources/runtime-manifest.json manifest.json scripts/managed-server.py build/PhononPlugin.bundle/Contents/Resources/
mkdir -p build/PhononPlugin.bundle/Contents/Resources/Licenses
cp LICENSE build/PhononPlugin.bundle/Contents/Resources/Licenses/PHONON-PLUGIN-LICENSE
cp vendor/TYPEWHISPER-LICENSE build/PhononPlugin.bundle/Contents/Resources/Licenses/TYPEWHISPER-LICENSE
cp THIRD_PARTY_NOTICES.md build/PhononPlugin.bundle/Contents/Resources/
cat > build/PhononPlugin.bundle/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.typewhisper.phonon</string><key>CFBundleExecutable</key><string>PhononPlugin</string><key>CFBundlePackageType</key><string>BNDL</string><key>CFBundleVersion</key><string>4</string><key>CFBundleShortVersionString</key><string>0.3.1</string><key>NSPrincipalClass</key><string>PhononPlugin</string></dict></plist>
PLIST
# Runtime provisioning is separate; remove the old generated bundled runtime.
if [[ -d build/PhononPlugin.bundle/Contents/Resources/Runtime ]]; then
    mv build/PhononPlugin.bundle/Contents/Resources/Runtime "build/legacy-runtime-$(date +%s)"
fi
codesign --force --sign - build/PhononPlugin.bundle
xcrun swiftc -parse-as-library "${flags[@]}" "${sources[@]}" Sources/TestHost.swift Sources/SmokeTest.swift -o build/smoke-test
xcrun swiftc -parse-as-library "${flags[@]}" Sources/TestHost.swift Sources/BundleTest.swift -o build/bundle-test
xcrun swiftc -parse-as-library "${flags[@]}" "${sources[@]}" Sources/ErrorTest.swift -o build/error-test
xcrun swiftc -parse-as-library "${flags[@]}" "${sources[@]}" Sources/LifecycleTest.swift -o build/lifecycle-test

xcrun swiftc -parse-as-library "${flags[@]}" "${sources[@]}" Sources/RuntimeTest.swift -o build/runtime-test
