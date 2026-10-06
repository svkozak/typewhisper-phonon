# Native development

Use an Apple Silicon Mac, macOS 15+, full Xcode with Swift 6.3+, Python 3, and
TypeWhisper **1.7.0 or 1.7.1** in `/Applications`. The plugin links the installed host SDK
framework. Rebuild and verify compatibility before using another host version.

## Build and install

Set `DEVELOPER_DIR` to your full Xcode installation. For example:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
bash scripts/build.sh
# Quit TypeWhisper before installing:
bash scripts/install-plugin.sh --replace
```

The installer preserves the previous bundle in TypeWhisper's `PluginBackups`
folder and keeps the model cache. Development builds use ad-hoc signing with
the same fixed helper identifier as releases: `local.typewhisper.phonon.engine`.

The build pins Fermion Research's phonon-coreml package and strips development
symbols from the distributed helper. The dependency revision is recorded in
`Engine/Package.resolved`. The vendored host SDK is pinned to TypeWhisper 1.7.0;
the 1.7.1 SDK sources are identical. See [vendor source details](../vendor/README.md).

## Verify

Generate the recording expected by the transcription harness:

```sh
say -v Samantha -o build/sample.aiff 'This is a local speech recognition test. Please schedule the project review for Friday afternoon.'
afconvert -f WAVE -d LEI16@16000 -c 1 build/sample.aiff build/sample.wav
```

Check fresh model setup, cancellation, retry, and cached startup:

```sh
python3 scripts/test-native-model-setup.py \
  "$PWD/build/PhononPlugin.bundle/Contents/Resources/Native/PhononSwift" \
  "$PWD/build/test-coreml-data/Models/fermion"
```

Check authentication, WAV validation, transcription, and owner-pipe shutdown:

```sh
python3 scripts/test-native-helper.py \
  "$PWD/build/PhononPlugin.bundle/Contents/Resources/Native/PhononSwift" \
  "$PWD/build/test-coreml-data/Models/fermion" build/sample.wav
PHONON_TEST_DATA_DIR="$PWD/build/test-coreml-data" \
  build/bundle-test build/PhononPlugin.bundle build/sample.wav
PHONON_TEST_NATIVE_EXECUTABLE="$PWD/build/PhononPlugin.bundle/Contents/Resources/Native/PhononSwift" \
  PHONON_TEST_DATA_DIR="$PWD/build/test-coreml-data" build/lifecycle-test
codesign --verify --deep --strict build/PhononPlugin.bundle
```

Use a fresh disposable Core ML cache for the setup harness. The optional second
argument keeps that cache for the remaining checks. Add `--cached-only` as the
third argument to check an existing disposable cache without repeating the
download and cancellation checks. First preparation can take
several minutes on older Apple Silicon. Plugin and fresh-setup readiness waits
allow twenty minutes for the download and preparation. The helper test
downloads the model if the supplied cache is empty. It leaves
that cache for subsequent bundle and lifecycle tests. Python is only the external
test harness; the native runtime does not use Python.

For a verified Core ML cache, check pinned hashes, missing and corrupt files,
linked files and directories, oversized downloads, and compiled cache integrity:

```sh
bash scripts/test-model-store.sh \
  "$PWD/build/test-coreml-data/Models/fermion/speech/FermionResearch__Phonon-2-CoreML/e931079df1f6bff26f5f416c1c8880e76a0cf2a3"
```

The helper checks PCM16, float32, 44.1 kHz stereo resampling, silence, invalid
audio, tiny clips, the exact 35-second boundary, and longer recordings. It also checks that transcripts
do not appear in helper logs. Run `build/error-test` for plugin error handling.
Check microphone permissions and real dictation inside TypeWhisper separately.

To check parent-process shutdown, run the lifecycle harness with `--owner`.
Wait for `OWNER_CHILD_PID`, terminate the harness process, and check that the
reported helper exits within five seconds.

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
bash scripts/notarize-native-release.sh /PATH/TO/PhononPlugin-0.6.0.dmg \
  --asc-profile YOUR_PROFILE
```

Both scripts also accept a `notarytool` keychain profile in place of
`--asc-profile YOUR_PROFILE`. Omitting authentication from the release packager
produces a signed release without notarisation. Keep credentials in Keychain.
Provide the matching source and build instructions when distributing GPL binaries.

## Implementation notes

The native helper uses a private loopback connection and exits with its owning
plugin. It verifies pinned file sizes and checksums before Core ML or the
decoder reads model data. Installation and compilation use staging and a file
lock. Downloaded files, compiled files, receipts, and preserved backups stay in
PluginData. Existing MLX caches are preserved. No recording is written by the
helper.

The Core ML model uses CPU and Neural Engine compute units. All encoder windows
load before readiness. The compiled cache is verified on each startup and
rebuilt after corruption or an OS version change. Apple's own Neural Engine
cache remains managed by the operating system. See the [native engine
notes](../Engine/README.md) for cache and inference details.

Performance measurements must separate fresh preparation, cached startup,
first transcription, and repeated transcription. Use the same audio and Mac
for comparisons. Accuracy across speakers and longer recordings needs broader
validation. Harness results do not establish host microphone or real dictation
behavior.

Local measurements on 6 October 2026 used an M1 Pro with 32 GB RAM, macOS
27.0.1, and the 5.72-second Samantha recording above. Repeated Core ML
transcription had median times of 29–35 ms across runs. The previous MLX
engine took 99 ms on the same recording. Every run returned the expected text.
Cached Core ML startup took about 2.1 seconds. First Neural Engine preparation
took about six minutes, excluding download time. These measurements describe
this recording and Mac; they do not establish accuracy across speakers.
