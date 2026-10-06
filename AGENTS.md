# Working on Phonon

Phonon is a native Swift/Core ML transcription plugin for TypeWhisper on Apple
Silicon. Read [README.md](README.md) for user behaviour and
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for build, test, and release commands.

## Project layout

- `Sources/`: TypeWhisper plugin, settings view, and helper process controller.
- `Engine/`: the production native Swift/Core ML engine. Includes model download,
  Core ML compilation, audio input, and inference.
- `scripts/`: build, installation, verification, and release tools.
- `vendor/TypeWhisperPluginSDK/`: pinned host SDK interfaces.
- `manifest.json`: the authoritative plugin manifest.

## Implementation rules

- Keep the runtime native. Python scripts are external test or release tools;
  do not restore the previous Python server or runtime installer.
- Preserve plugin ID `local.typewhisper.phonon`, provider ID `phonon-local`, and
  model ID `phonon-2`. Changing these can break saved settings and model caches.
- Keep model files outside the plugin bundle, in the plugin's `PluginData`
  directory. Do not commit model weights or generated build output.
- Preserve the helper's ownership and shutdown rules. Use the private loopback
  connection, authentication token, and owner pipe. Keep inference serial.
- Keep audio processing in memory. Do not add recordings or transcript contents
  to logs.
- Preserve pinned model revisions, checksum checks, normal TLS verification,
  bounded downloads, installation locks, and atomic cache publication.
  Do not bypass validation to make a failing download work.
- Preserve user model caches and rollback bundles during installation or
  cleanup. Use disposable directories for tests.
- Keep dependency versions pinned. Update the relevant patches, notices, and
  verification when changing phonon-coreml or the host SDK.
- Keep settings focused on model status and recovery. Put diagnostic details in
  troubleshooting controls or development documentation.
- State current limits accurately: English transcription only; translation and
  live streaming are unsupported. Do not advertise capabilities without
  implementing and verifying them.

## Build and verification

- Use full Xcode with Swift 6.3+ and the compatible TypeWhisper SDK.
  The documented and tested host version is 1.7.0.
- Set `DEVELOPER_DIR` for the command when needed. Do not change the computer's
  global Xcode selection as part of routine work.
- Build with `bash scripts/build.sh`. Do not create a second build path.
- Run checks appropriate to the change. Documentation edits need link and diff
  checks; code changes need a build and the relevant existing harnesses.
- For helper lifecycle changes, run the lifecycle harness. For model setup or
  decoding changes, run model setup and model store checks. For inference or
  audio changes, run helper and SDK bundle transcription checks.
- Follow `docs/DEVELOPMENT.md` for harness arguments and disposable cache paths.
  Host microphone permissions and real dictation require separate verification
  inside TypeWhisper. Do not present harness results as proof of those checks.
- Quit TypeWhisper before replacing its installed bundle. Use
  `bash scripts/install-plugin.sh --replace` to preserve rollback support.
- Report what was verified and any material checks that remain unverified.

## Documentation and releases

- Use short, clear sentences. Keep the README focused on installation, use,
  requirements, and licensing. Keep implementation details in development docs.
- Distinguish permanent model storage (about 700 MB including the compiled
  cache) from temporary space needed during first Core ML preparation. Do not
  describe generated compiled files as bundled weights or an additional download.
- Preserve GPL-3.0-only licensing and third-party notices. The separately
  downloaded Phonon-2 model has its own CC-BY-4.0 terms and attribution.
- When preparing a release, update the version in `manifest.json` and the bundle
  build number in `scripts/build.sh`. Use the existing packaging scripts.
- Keep signing credentials in Keychain. Never commit keys, passwords, tokens,
  or exported credentials.
- Verify Developer ID signatures and Apple's notarisation acceptance before
  describing an artifact as notarised. Prefer the stapled DMG for distribution.
- Publish matching source and build instructions with distributed GPL binaries.
  Keep release assets, checksums, tags, and source commit consistent.
- Do not bump a version or rebuild release artifacts for documentation-only
  changes unless the user requests a release.
