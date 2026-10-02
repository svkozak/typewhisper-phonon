# Native development

Use an Apple Silicon Mac, macOS 14+, full Xcode with Swift 6.3+, Python 3, and
TypeWhisper **1.6.1** in `/Applications`. The plugin links the installed host SDK
framework. Rebuild and verify compatibility before using another host version.

## Build and install

Set `DEVELOPER_DIR` to your full Xcode installation. For example:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -downloadComponent MetalToolchain
bash scripts/build.sh
# Quit TypeWhisper before installing:
bash scripts/install-plugin.sh --replace
```

The installer preserves the previous bundle in TypeWhisper's `PluginBackups`
folder and keeps the model cache. Development builds use ad-hoc signing.

The build pins MLX Swift and the audio library, compiles MLX's prepared Metal
kernels, and strips development symbols from the distributed helper. Dependency
versions are recorded in `Engine/Package.resolved`.

## Verify

Generate the recording expected by the transcription harness:

```sh
say -v Samantha -o build/sample.aiff 'This is a local speech recognition test. Please schedule the project review for Friday afternoon.'
afconvert -f WAVE -d LEI16@16000 -c 1 build/sample.aiff build/sample.wav
```

Check fresh model setup, cancellation, retry, and cached startup:

```sh
python3 scripts/test-native-model-setup.py \
  "$PWD/build/PhononPlugin.bundle/Contents/Resources/Native/PhononSwift"
```

Check authentication, WAV validation, transcription, and owner-pipe shutdown:

```sh
python3 scripts/test-native-helper.py \
  "$PWD/build/PhononPlugin.bundle/Contents/Resources/Native/PhononSwift" \
  "$PWD/build/test-native-data/Models/fermion" build/sample.wav
PHONON_TEST_DATA_DIR="$PWD/build/test-native-data" \
  build/bundle-test build/PhononPlugin.bundle build/sample.wav
PHONON_TEST_NATIVE_EXECUTABLE="$PWD/build/PhononPlugin.bundle/Contents/Resources/Native/PhononSwift" \
  PHONON_TEST_DATA_DIR="$PWD/build/test-native-data" build/lifecycle-test
codesign --verify --deep --strict build/PhononPlugin.bundle
```

The helper test downloads the model if the supplied cache is empty. It leaves
that cache for subsequent bundle and lifecycle tests. Python is only the external
test harness; the native runtime does not use Python.

For a previously downloaded, pinned model archive, check decompression bounds,
archive entries, model hashes, and corrupt-file rejection:

```sh
bash scripts/test-model-store.sh /PATH/TO/phonon-2.bps.tar.zst
```

Check microphone permissions and real dictation inside TypeWhisper separately.

## Signed and notarised release

Use a Developer ID Application certificate and an App Store Connect CLI profile
for the same Apple Developer team:

```sh
bash scripts/package-native-release.sh /ABSOLUTE/OUTPUT/DIRECTORY \
  'Developer ID Application: YOUR NAME (TEAM_ID)' --asc-profile YOUR_PROFILE
```

The script signs the helper and bundle, creates a disk image, submits it to Apple,
requires acceptance, attaches the approval ticket, and checks Gatekeeper. It also
creates a ZIP and release metadata with checksums. Distribute the stapled disk
image for an approval ticket that is available offline.

To notarise an existing signed disk image:

```sh
bash scripts/notarize-native-release.sh /PATH/TO/PhononPlugin-0.5.1.dmg \
  --asc-profile YOUR_PROFILE
```

Both scripts also accept a `notarytool` keychain profile in place of
`--asc-profile YOUR_PROFILE`. Omitting authentication from the release packager
produces a signed release without notarisation. Keep credentials in Keychain.
Provide the matching source and build instructions when distributing GPL binaries.

## Implementation notes

The native helper uses a private loopback connection and exits with its owning
plugin. It verifies the pinned model archive, configuration, and container
checksums before loading. Model installation uses a staging folder and a file
lock. Audio is decoded in memory.

Loading expands the compressed weights and uses a temporary dense checkpoint,
which is removed after loading. MLX allocations peaked near 2.6 GB on the
development Mac. Accuracy across speakers and long recordings needs broader
validation. See the [native engine notes](../Engine/README.md)
for the container comparison and earlier feasibility measurements.
