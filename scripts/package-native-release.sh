#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-26.6.0.app/Contents/Developer}"
[[ $# -ge 2 && $# -le 4 ]] || { echo 'Usage: package-native-release.sh OUTPUT_DIRECTORY DEVELOPER_ID_IDENTITY [NOTARY_KEYCHAIN_PROFILE | --asc-profile ASC_PROFILE]'; exit 1; }
output="$1"
identity="$2"
notary_args=("${@:3}")
[[ "$output" == /* ]] || { echo 'Use an absolute output directory.'; exit 1; }
bundle="$PWD/build/PhononPlugin.bundle"
[[ -x "$bundle/Contents/Resources/Native/PhononSwift" ]] || { echo 'Build the native plugin first.'; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$bundle/Contents/Info.plist")
mkdir -p "$output"
# Sign nested code first. Never use --deep to sign.
codesign --force --sign "$identity" --timestamp --options runtime --identifier local.typewhisper.phonon.engine "$bundle/Contents/Resources/Native/PhononSwift"
codesign --force --sign "$identity" --timestamp --options runtime "$bundle"
codesign --verify --deep --strict --verbose=2 "$bundle"
stage=$(mktemp -d "$PWD/build/release-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$bundle" "$stage/PhononPlugin.bundle"
cat > "$stage/Install Phonon.txt" <<'TXT'
Phonon — Apple Silicon, macOS 15+, TypeWhisper 1.7.0

1. Open the release disk image.
2. In TypeWhisper open Settings > Integrations and click 'Install Plugin'.
3. Select PhononPlugin.bundle on the mounted disk.
4. Wait for the model download and preparation, then select the Phonon engine
   and Phonon-2 model.

The model downloads once into TypeWhisper's PluginData folder. Subsequent
startup and transcription work offline. No Python or Homebrew is required.
The model download is about 345 MB. Downloaded and compiled files use about
700 MB. Allow additional space for first setup, the system Neural Engine
cache, and preserved rollback caches. Preparation can take several minutes.

The bundle is Developer ID signed. Notarisation status is recorded in the
separate release JSON. A signed build without Accepted notarisation may still
be blocked by macOS when transferred to another Mac.
TXT
dmg="$output/PhononPlugin-$version.dmg"
[[ ! -e "$dmg" ]] || { echo "Output already exists: $dmg"; exit 1; }
hdiutil create -volname "Phonon $version" -srcfolder "$stage" -format UDZO -imagekey zlib-level=9 "$dmg"
codesign --sign "$identity" --timestamp "$dmg"
status='Signed; notarisation not requested'
if [[ ${#notary_args[@]} -gt 0 ]]; then
    bash scripts/notarize-native-release.sh "$dmg" "${notary_args[@]}"
    status='Accepted; ticket stapled to disk image'
fi
ditto -c -k --keepParent "$bundle" "$output/PhononPlugin-$version.zip"
python3 - "$output" "$version" "$status" <<'PY'
import hashlib,json,pathlib,sys
output,version,status=pathlib.Path(sys.argv[1]),sys.argv[2],sys.argv[3]
def describe(path):
    digest=hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda:source.read(1024*1024),b''): digest.update(block)
    return {'bytes':path.stat().st_size,'sha256':digest.hexdigest()}
files={p.name:describe(p) for p in (output/f'PhononPlugin-{version}.zip',output/f'PhononPlugin-{version}.dmg')}
(output/f'PhononPlugin-{version}-release.json').write_text(json.dumps({'version':version,'notarisation':status,'artifacts':files},indent=2)+'\n')
PY
echo "$status"
echo "Distribution: $dmg"
