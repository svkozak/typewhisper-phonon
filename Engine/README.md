# Native Phonon engine

The Swift executable reads Phonon-2's compressed `model.fermion` container,
expands its five-value/int6/fp16 records, maps 697 tensors, and runs the
Swift MLX Parakeet model. It does not use Python.

## Build and run

Use an Apple Silicon Mac with full Xcode and Swift 6.3+. The package pins
MLX Swift 0.32.3 and the audio library to a specific commit.

```sh
bash Engine/build.sh
Engine/.build/release/PhononSwift \
  /PATH/TO/MODEL_DIRECTORY recording.wav 5
```

The CLI reports load time, transcription time, memory measurements, and the
model container checksum. An optional fourth argument writes a tensor audit:

```sh
Engine/.build/release/PhononSwift \
  /PATH/TO/MODEL_DIRECTORY recording.wav 5 /PATH/TO/weights.json
```

Set `DEVELOPER_DIR` for another Xcode installation. Install the Metal toolchain
with `xcodebuild -downloadComponent MetalToolchain` when needed. The build
compiles the pinned MLX Swift kernels and creates a stripped executable for
release packaging. The dependency patch explicitly selects `MLX.compile` at
two sites and preserves strict concurrency checks.

## Plugin helper

`--serve` receives configuration on a private stdin pipe, downloads and verifies
the pinned model when needed, and serves authenticated loopback requests.
The helper watches its owner and pipe EOF, decodes WAV audio in memory, and
performs serial inference. It exits when the plugin stops.

Loading uses a temporary dense safetensors checkpoint, removed after loading.
Allow roughly 1.3 GB of temporary disk space. Inference uses dense bfloat16
weights, rather than Phonon's packed execution optimisations. Earlier comparison
with the Python engine matched all 697 tensor names, shapes, and float32 hashes;
the comparison tooling is retained in Git history.

See the [development guide](../docs/DEVELOPMENT.md) for current verification
and release commands, and [notices](THIRD_PARTY_NOTICES.md) for source licenses.
