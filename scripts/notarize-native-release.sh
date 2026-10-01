#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-26.6.0.app/Contents/Developer}"
[[ $# == 2 || ( $# == 3 && "$2" == --asc-profile ) ]] || { echo 'Usage: notarize-native-release.sh SIGNED_DISK_IMAGE NOTARY_KEYCHAIN_PROFILE | SIGNED_DISK_IMAGE --asc-profile ASC_PROFILE'; exit 1; }
dmg="$1"
profile="${3:-$2}"
[[ -f "$dmg" && "$dmg" == *.dmg ]] || { echo 'Provide the signed release disk image.'; exit 1; }
base="${dmg%.dmg}"
submission="$base-notary.json"
codesign --verify --strict "$dmg"
if [[ "$2" == --asc-profile ]]; then
    # asc reads its API key directly from Keychain. No key export or password.
    python3 - "$dmg" "$profile" "$submission" <<'PY'
import json,pathlib,subprocess,sys
dmg,profile,output=sys.argv[1:]
result=subprocess.run(['asc','--profile',profile,'notarization','submit','--file',dmg,'--wait'],capture_output=True,text=True)
if result.returncode:
    print(result.stderr.strip(),file=sys.stderr)
    raise SystemExit(result.returncode)
response=json.loads(result.stdout)
item=response.get('data',response)
if isinstance(item,list): item=item[0]
attributes=item.get('attributes',{})
record={'id':item.get('id',response.get('id')),'status':attributes.get('status',response.get('status')),'authentication':'asc profile: '+profile}
assert record['id'] and record['status'], 'Missing submission metadata'
# Never persist temporary upload credentials from the API response.
pathlib.Path(output).write_text(json.dumps(record,indent=2)+'\n')
PY
else
    xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait --output-format json > "$submission"
fi
result=$(/usr/bin/plutil -extract status raw -o - "$submission")
if [[ "$result" != Accepted ]]; then
    request_id=$(/usr/bin/plutil -extract id raw -o - "$submission")
    if [[ "$2" == --asc-profile ]]; then
        echo "Inspect Apple's log with: asc --profile $profile notarization log --id $request_id"
    else
        xcrun notarytool log "$request_id" --keychain-profile "$profile" "$base-notary-log.json"
    fi
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
