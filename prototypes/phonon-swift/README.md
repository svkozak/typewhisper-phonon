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
Set `DEVELOPER_DIR` for another installation. SwiftPM cannot compile the Metal
library. The script copies the precompiled library from the existing MLX 0.32.3
wheel, or accepts a matching `mlx.metallib` path as its first argument. The copied
library remains next to the executable. Production distribution needs an
independent Metal resource build and appropriate licenses.

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
- The executable currently links the broad Swift audio dependency. Binary and
  Metal resource sizes are not optimised.
- First inference compiles GPU kernels and is much slower than warm inference.
- Python's default `tdt16,dense16` optimisations are not ported here. Dense Swift
  inference does not prove parity with Phonon's packed execution path.
- Validation on one generated speech recording establishes loader parity and
  basic transcription, not accuracy across speakers, long recordings or silence.
- A native plugin still needs host integration, model lifecycle, cancellation,
  memory management, and deployment testing. Signing/notarisation remain separate.

See THIRD_PARTY_NOTICES.md and FERMION-LICENSE for source provenance.
