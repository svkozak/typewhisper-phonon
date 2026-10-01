#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash prototypes/phonon-swift/build.sh
bash scripts/build.sh
bundle=build/PhononPlugin.bundle
native="$bundle/Contents/Resources/Native"
mkdir -p "$native"
chmod -R u+w "$bundle/Contents/Resources/Licenses"
cp prototypes/phonon-swift/.build/release/PhononSwift-distribution "$native/PhononSwift"
cp prototypes/phonon-swift/.build/release/mlx.metallib "$native/"
cp prototypes/phonon-swift/Sources/CZstd/LICENSE "$bundle/Contents/Resources/Licenses/ZSTD-LICENSE"
cp prototypes/phonon-swift/Sources/CZstd/COPYING "$bundle/Contents/Resources/Licenses/ZSTD-COPYING"
cp prototypes/phonon-swift/FERMION-LICENSE "$bundle/Contents/Resources/Licenses/FERMION-LICENSE"
cp prototypes/phonon-swift/.build/checkouts/mlx-audio-swift/LICENSE "$bundle/Contents/Resources/Licenses/MLX-AUDIO-SWIFT-LICENSE"
cp prototypes/phonon-swift/.build/checkouts/mlx-swift/LICENSE "$bundle/Contents/Resources/Licenses/MLX-SWIFT-LICENSE"
cp Resources/native-plugin-manifest.json "$bundle/Contents/Resources/manifest.json"
cp prototypes/phonon-swift/THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/NATIVE-NOTICES.md"
mkdir -p "$bundle/Contents/Resources/Licenses/SwiftDependencies"
for dependency in prototypes/phonon-swift/.build/checkouts/*; do
    for license_name in LICENSE LICENSE.txt LICENSE.md COPYING COPYING.txt NOTICE NOTICE.txt; do
        if [[ -f "$dependency/$license_name" ]]; then
            cp "$dependency/$license_name" "$bundle/Contents/Resources/Licenses/SwiftDependencies/$(basename "$dependency")-$license_name"
        fi
    done
done
# These generated resources belong to the Python variant and are unused here.
rm -f "$bundle/Contents/Resources/managed-server.py" "$bundle/Contents/Resources/runtime-manifest.json"
/usr/libexec/PlistBuddy -c 'Set CFBundleShortVersionString 0.5.0' "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set CFBundleVersion 6' "$bundle/Contents/Info.plist"
codesign --force --sign - "$native/PhononSwift"
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
echo 'Native Swift plugin built. Phonon-2 downloads on first use into PluginData/Models.'
