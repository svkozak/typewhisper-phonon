#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -m)" == arm64 ]] || { echo 'Apple Silicon required'; exit 1; }
host_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' /Applications/TypeWhisper.app/Contents/Info.plist)
[[ "$host_version" == 1.6.1 ]] || { echo "Requires TypeWhisper 1.6.1; found $host_version."; exit 1; }
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    if [[ -d /Applications/Xcode-26.6.0.app ]]; then
        export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
    elif [[ -d /Applications/Xcode.app ]]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    else
        echo 'Set DEVELOPER_DIR to a full Xcode installation.'; exit 1
    fi
fi
bash prototypes/phonon-swift/build.sh
frameworks=/Applications/TypeWhisper.app/Contents/Frameworks
bundle=build/PhononPlugin.bundle
# Always assemble a fresh bundle; previous build resources cannot leak into it.
if [[ -d "$bundle" ]]; then chmod -R u+w "$bundle"; rm -rf "$bundle"; fi
mkdir -p "$bundle/Contents/"{MacOS,Resources/Native,Resources/Licenses/SwiftDependencies}
flags=(-swift-version 6 -target arm64-apple-macos14.0 -I build -F "$frameworks" -framework TypeWhisperPluginSDK -Xlinker -rpath -Xlinker "$frameworks")
sources=(Sources/PhononPlugin.swift Sources/PhononServer.swift)
xcrun swiftc -emit-module -module-name TypeWhisperPluginSDK -swift-version 6 -target arm64-apple-macos14.0 vendor/TypeWhisperPluginSDK/*.swift -emit-module-path build/TypeWhisperPluginSDK.swiftmodule
xcrun swiftc -emit-library -module-name PhononPlugin "${flags[@]}" "${sources[@]}" -o "$bundle/Contents/MacOS/PhononPlugin"
cp manifest.json THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/"
cp LICENSE "$bundle/Contents/Resources/Licenses/PHONON-PLUGIN-LICENSE"
cp vendor/TYPEWHISPER-LICENSE "$bundle/Contents/Resources/Licenses/TYPEWHISPER-LICENSE"
cp prototypes/phonon-swift/.build/release/PhononSwift-distribution "$bundle/Contents/Resources/Native/PhononSwift"
cp prototypes/phonon-swift/.build/release/mlx.metallib "$bundle/Contents/Resources/Native/"
cp prototypes/phonon-swift/FERMION-LICENSE "$bundle/Contents/Resources/Licenses/FERMION-LICENSE"
cp prototypes/phonon-swift/Sources/CZstd/LICENSE "$bundle/Contents/Resources/Licenses/ZSTD-LICENSE"
cp prototypes/phonon-swift/Sources/CZstd/COPYING "$bundle/Contents/Resources/Licenses/ZSTD-COPYING"
cp prototypes/phonon-swift/THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/NATIVE-NOTICES.md"
for dependency in prototypes/phonon-swift/.build/checkouts/*; do
    for license_name in LICENSE LICENSE.txt LICENSE.md COPYING COPYING.txt NOTICE NOTICE.txt; do
        if [[ -f "$dependency/$license_name" ]]; then
            cp "$dependency/$license_name" "$bundle/Contents/Resources/Licenses/SwiftDependencies/$(basename "$dependency")-$license_name"
        fi
    done
done
version=$(/usr/bin/plutil -extract version raw -o - manifest.json)
cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.typewhisper.phonon</string><key>CFBundleExecutable</key><string>PhononPlugin</string><key>CFBundlePackageType</key><string>BNDL</string><key>CFBundleVersion</key><string>7</string><key>CFBundleShortVersionString</key><string>$version</string><key>NSPrincipalClass</key><string>PhononPlugin</string></dict></plist>
PLIST
codesign --force --sign - "$bundle/Contents/Resources/Native/PhononSwift"
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
xcrun swiftc -parse-as-library "${flags[@]}" Sources/TestHost.swift Sources/BundleTest.swift -o build/bundle-test
xcrun swiftc -parse-as-library "${flags[@]}" "${sources[@]}" Sources/ErrorTest.swift -o build/error-test
xcrun swiftc -parse-as-library "${flags[@]}" "${sources[@]}" Sources/LifecycleTest.swift -o build/lifecycle-test
echo "Built Phonon $version. Models download separately on first use."
