# Native Phonon engine

The Swift executable runs Phonon-2 through Fermion Research's Core ML package.
The encoder uses CPU and Apple Neural Engine compute units. The C decoder runs
on the CPU. The runtime does not use Python or MLX.

## Build and run

Use an Apple Silicon Mac with macOS 15+, full Xcode, and Swift 6.3+.
Build the plugin through the repository's normal build script:

```sh
bash scripts/build.sh
build/PhononPlugin.bundle/Contents/Resources/Native/PhononSwift \
  /PATH/TO/DISPOSABLE_MODEL_CACHE recording.wav 5
```

The CLI downloads the pinned model if needed. Its first argument is the cache
root, such as `build/test-coreml-data/Models/fermion`, rather than a model folder.
It reports load time, transcription times, the model revision, and transcripts.
The CLI reads PCM16 or float32 WAV and resamples in memory.

Set `DEVELOPER_DIR` for another full Xcode installation. The build pins
`phonon-coreml` 1.1.1 to commit `464ae57460fed61d4feb6f2a7424b5be1213accb`.
It creates a stripped executable for release packaging. No Metal toolchain or
third-party Swift dependencies beyond `phonon-coreml` are required.

## Plugin helper

`--serve` receives configuration on a private stdin pipe and serves authenticated
loopback requests. The helper watches its owner and pipe EOF. It decodes WAV
and resamples in memory. One helper owns one transcriber. Requests, encoder
windows, and decoder jobs run serially. CPU work inside a decoder can use
multiple threads.

The model download is about 345 MB. Each file has a pinned byte count and SHA-256
checksum. Installation holds a file lock and publishes a verified staging
folder. The cache has its own Core ML directory; existing MLX model caches are
preserved.

Core ML compilation runs once per cache and OS version. The compiled model is
stored beside the downloaded model in PluginData, at a stable path. A receipt
records its OS version and each compiled file's size and SHA-256 checksum.
Missing, changed, or stale compiled files trigger recompilation. Previous model
and compiled caches are preserved as backups. Apple's own Neural Engine cache
is managed by the operating system.

All four encoder windows (5, 10, 15, and 35 seconds) load before readiness is
reported. First setup can take several minutes. Later startup uses the compiled
cache. Audio beyond 34.9 seconds uses upstream pause-based windowing and word
joining, with windows up to 14.9 seconds. These limits leave room for the
package's 20 ms window-selection margin. Clips shorter than 20 ms return empty
text before reaching the frontend. English transcription only; translation and
live streaming are unsupported.

See the [development guide](../docs/DEVELOPMENT.md) for verification and release
commands, and [notices](THIRD_PARTY_NOTICES.md) for pinned sources and licenses.
