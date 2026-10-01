#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-26.6.0.app/Contents/Developer}"
[[ $# == 2 ]] || { echo 'Usage: notarize-native-release.sh SIGNED_DISK_IMAGE NOTARY_KEYCHAIN_PROFILE'; exit 1; }
dmg="$1"
profile="$2"
[[ -f "$dmg" && "$dmg" == *.dmg ]] || { echo 'Provide the signed release disk image.'; exit 1; }
base="${dmg%.dmg}"
submission="$base-notary.json"
codesign --verify --strict "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait --output-format json > "$submission"
result=$(/usr/bin/plutil -extract status raw -o - "$submission")
if [[ "$result" != Accepted ]]; then
    request_id=$(/usr/bin/plutil -extract id raw -o - "$submission")
    xcrun notarytool log "$request_id" --keychain-profile "$profile" "$base-notary-log.json"
    echo 'Notarisation was not accepted. Inspect the saved Apple log.'; exit 1
fi
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
python3 - "$dmg" <<'PY'
import hashlib,json,pathlib,sys
dmg=pathlib.Path(sys.argv[1])
record=dmg.with_name(dmg.stem+'-release.json')
if record.exists():
    data=json.loads(record.read_text())
    digest=hashlib.sha256()
    with dmg.open('rb') as source:
        for block in iter(lambda:source.read(1024*1024),b''): digest.update(block)
    data['notarisation']='Accepted; ticket stapled to disk image'
    data['artifacts'][dmg.name]={'bytes':dmg.stat().st_size,'sha256':digest.hexdigest()}
    record.write_text(json.dumps(data,indent=2)+'\n')
PY
echo 'Accepted; ticket stapled and validated.'
