#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
plugin_data="$HOME/Library/Application Support/TypeWhisper/PluginData/local.typewhisper.phonon"
model_directory="${1:-$plugin_data/Models/fermion/speech/FermionResearch__Phonon-2/model_phonon2_c4c_int6}"
source_audio="${2:-../../build/sample.wav}"
output_directory="${3:-$PWD/.build/comparison}"
reference_python="${4:-$plugin_data/Runtime/cpython312-phonon027-mlx-v2/bin/python3.12}"
mkdir -p "$output_directory"
output_directory=$(cd "$output_directory" && pwd)
/usr/bin/afconvert -f WAVE -d LEI16@16000 -c 1 "$source_audio" "$output_directory/audio-16k.wav"
/usr/bin/time -l .build/release/PhononSwift "$model_directory" "$output_directory/audio-16k.wav" 5 "$output_directory/weights.json" > "$output_directory/swift.json" 2> "$output_directory/swift.log"
/usr/bin/time -l "$reference_python" -I -B python-reference.py "$model_directory" "$output_directory/audio-16k.wav" "$output_directory/weights.json" > "$output_directory/python.json" 2> "$output_directory/python.log"
"$reference_python" -I -B - "$output_directory" <<'PY'
import json,pathlib,statistics,sys
folder=pathlib.Path(sys.argv[1])
swift=json.loads((folder/'swift.json').read_text())
python=json.loads((folder/'python.json').read_text())
assert swift['model_container_sha256']==python['model_container_sha256']
assert swift['transcripts']==python['transcripts'], 'Transcript mismatch'
assert len(set(swift['transcripts']))==1, 'Non-deterministic transcript'
for name,result in [('Swift',swift),('Python',python)]:
    print(f"{name}: warm median {statistics.median(result['decode_seconds'][1:])*1000:.1f} ms; active MLX memory {result['mlx_active_memory_bytes']/1e9:.2f} GB")
print('PASS: same model and matching transcripts on all five runs')
print('Results:',folder)
PY
