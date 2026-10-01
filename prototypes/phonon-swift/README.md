# Native Phonon feasibility prototype

A separate command-line experiment. It does not replace the installed TypeWhisper
plugin. The Swift executable reads the same compressed Phonon-2 `model.fermion`
file already downloaded by the plugin, decodes its five-value/int6/fp16 records,
maps all 697 tensors, and runs the Swift MLX Parakeet model. No Python process or
Python environment is used by the Swift executable.

## Build and run

Use an Apple Silicon Mac with full Xcode and Swift 6.3+. The package pins MLX
Swift 0.32.3 and the upstream Swift audio repository to a specific commit.

```sh
bash prototypes/phonon-swift/build.sh
prototypes/phonon-swift/.build/release/PhononSwift \
  "$HOME/Library/Application Support/TypeWhisper/PluginData/local.typewhisper.phonon/Models/fermion/speech/FermionResearch__Phonon-2/model_phonon2_c4c_int6" \
  build/sample.wav 5
```

The build script defaults to the Xcode installation used on the development Mac.
Set `DEVELOPER_DIR` for another installation. The script compiles all prepared
Metal kernels from the pinned MLX Swift checkout with `xcrun metal` and
`xcrun metallib`. Install Xcode's Metal toolchain with
`xcodebuild -downloadComponent MetalToolchain` when needed. The generated
library remains next to the executable. A separate stripped executable is
produced for distribution. No Python wheel is used in this native build.

The dependency patch selects `MLX.compile` explicitly at two sites. Without it,
the upstream module picks a different overload from MLXLMCommon that requires
Sendable captures. The patch preserves strict concurrency checks; the executable
performs inference serially.

## Compare with Python

```sh
bash prototypes/phonon-swift/compare.sh
```

Optional arguments: model directory, source WAV, output directory, reference
Python executable. Comparison converts the input once to mono 16 kHz PCM, runs
each implementation five times, compares the model SHA-256 and transcripts, and
checks EVERY tensor's name, shape and float32 value hash against Fermion 0.2.7.
Only the verification script uses Python. Results and process memory statistics
are saved under `.build/comparison` by default.

## Scope and limitations

- This is a feasibility tool, not an installable TypeWhisper plugin.
- The first version expands compressed weights to dense arrays. It writes a
  temporary safetensors checkpoint to adapt to the upstream public loader, then
  removes the checkpoint on exit. It can use roughly 1.3 GB of temporary disk.
- The executable currently links the broad Swift audio dependency. Distribution
  removes development symbols and uses a 1.9 MB Metal library. Further dependency
  reduction is possible.
- First inference compiles GPU kernels and is much slower than warm inference.
- Python's default `tdt16,dense16` optimisations are not ported here. Dense Swift
  inference does not prove parity with Phonon's packed execution path.
- Validation on one generated speech recording establishes loader parity and
  basic transcription, not accuracy across speakers, long recordings or silence.
- The CLI remains a feasibility tool. The owned-helper mode below supplies the
  installed plugin's model lifecycle and host integration. Broad accuracy and
  deployment checks across macOS releases remain separate.

See THIRD_PARTY_NOTICES.md and FERMION-LICENSE for source provenance.

## TypeWhisper native helper mode

`--serve` runs the same engine as an owned loopback helper for the native plugin. Configuration arrives on a private stdin pipe. The helper watches owner exit and pipe EOF, validates an instance-specific readiness file, requires a bearer token for uploads, decodes WAV audio in memory, and performs serial inference. `scripts/build-native-plugin.sh` packages it in a real TypeWhisper bundle. Version 0.5.0 downloads and verifies the model on first use, using macOS HTTPS trust and a bundled Zstandard decoder. `scripts/test-native-helper.py` checks the protocol, authentication, malformed audio, transcription, interrupted-load cleanup, and owner-pipe shutdown. `scripts/test-model-store.sh` checks archive bounds, unsafe entries, damaged files, and exact model hashes. See the root README for signing and notarisation.
