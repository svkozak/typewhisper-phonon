#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
frameworks=/Applications/TypeWhisper.app/Contents/Frameworks
mkdir -p build/PhononPlugin.bundle/Contents/{MacOS,Resources}
swiftc -emit-module -module-name TypeWhisperPluginSDK -swift-version 6 -target arm64-apple-macos14.0 vendor/TypeWhisperPluginSDK/*.swift -emit-module-path build/TypeWhisperPluginSDK.swiftmodule
swiftc -emit-library -module-name PhononPlugin -swift-version 6 -target arm64-apple-macos14.0 -I build -F "$frameworks" -framework TypeWhisperPluginSDK -Xlinker -rpath -Xlinker "$frameworks" Sources/PhononPlugin.swift -o build/PhononPlugin.bundle/Contents/MacOS/PhononPlugin
cp manifest.json build/PhononPlugin.bundle/Contents/Resources/
cat > build/PhononPlugin.bundle/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.typewhisper.phonon</string><key>CFBundleExecutable</key><string>PhononPlugin</string><key>CFBundlePackageType</key><string>BNDL</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>0.1.0</string><key>NSPrincipalClass</key><string>PhononPlugin</string></dict></plist>
PLIST
codesign --force --sign - build/PhononPlugin.bundle
swiftc -parse-as-library -swift-version 6 -target arm64-apple-macos14.0 -I build -F "$frameworks" -framework TypeWhisperPluginSDK -Xlinker -rpath -Xlinker "$frameworks" Sources/PhononPlugin.swift Sources/SmokeTest.swift -o build/smoke-test
swiftc -parse-as-library -swift-version 6 -target arm64-apple-macos14.0 -I build -F "$frameworks" -framework TypeWhisperPluginSDK -Xlinker -rpath -Xlinker "$frameworks" Sources/BundleTest.swift -o build/bundle-test
