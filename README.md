# TypeWhisper + Phonon-2 local plugin

## Native Swift plugin — 0.5.0

The `native-swift-plugin` branch includes a real TypeWhisper bundle using a native Swift/MLX helper. Build with `bash scripts/build-native-plugin.sh`. Quit TypeWhisper, then install with `bash scripts/install-plugin.sh --replace` and reopen TypeWhisper. Select Phonon-2 (Swift / MLX), or use the existing Phonon selection. Recipient Macs need Apple Silicon, macOS 14+, and the tested TypeWhisper 1.6.1 host. They do not need Python, Homebrew, Xcode, or this repository.

On first use, the native helper downloads a 163,515,201-byte Phonon-2 archive into a private staging folder under `PluginData/local.typewhisper.phonon/Models/fermion/speech/FermionResearch__Phonon-2`. The HTTPS URL pins revision `ca1bef26bcd8ef4a7e16d0636d8a77bb25e298ee`. The archive, model container, and configuration have pinned SHA-256 checksums. The signed helper includes a small Zstandard decoder; it accepts only the four expected regular archive entries and bounds decompression to 180 MB. Completed installation is published atomically. A file lock serializes installers. Interrupted staging is reclaimed on retry; an incompatible previous model is preserved in a backup folder. Settings report download and loading progress, or a useful error with a restart action.

The existing Python model cache is reused when its hashes match. Future startup works offline. The model stays outside the bundle. The native helper runs in a separate owned process, keeps the model loaded, requires a private token for audio requests, and stops with TypeWhisper. WAV recordings are decoded in memory. The previous plugin bundle is backed up by the installer for rollback.

Startup includes weight expansion and GPU warm-up. A temporary dense model checkpoint is removed after loading. Allow roughly 2 GB of free disk space during model loading. The GPU library is compiled from the pinned MLX Swift sources (about 1.9 MB); the shipped helper has development symbols removed. Native loading can still peak near 2.6 GB of MLX allocations on the development Mac. This is an early native implementation; accuracy across languages and long recordings is not established.

Development builds use ad-hoc signing. To create a Developer ID signed release, run:

```sh
bash scripts/package-native-release.sh /ABSOLUTE/OUTPUT/DIRECTORY \
  'Developer ID Application: YOUR NAME (TEAM_ID)' NOTARY_KEYCHAIN_PROFILE
```

The optional last argument names a `notarytool` keychain profile. Configure credentials locally with `xcrun notarytool store-credentials`; never put passwords in repository files. Without a profile, the script explicitly produces a signed but **not notarised** release. With a profile, it submits the signed disk image to Apple, requires `Accepted`, staples the ticket, and checks it. The disk image includes the bundle and installation instructions. The release JSON records notarisation status and checksums. Signing alone does not guarantee that Gatekeeper will accept a downloaded plugin on another Mac.

Apple's workflow: https://developer.apple.com/documentation/security/customizing-the-notarization-workflow

To notarise an already signed release later without rebuilding it, run
`bash scripts/notarize-native-release.sh /PATH/TO/PhononPlugin-0.5.0.dmg NOTARY_KEYCHAIN_PROFILE`.

An existing App Store Connect CLI API key also works. With `asc` configured for
the same Developer team as the signing certificate, use
`bash scripts/notarize-native-release.sh /PATH/TO/PhononPlugin-0.5.0.dmg --asc-profile business`.
The script uses the CLI's Keychain credentials directly. No app-specific password
or private-key export is needed. The release packager also accepts
`--asc-profile business` in place of a notarytool profile.

Native verification:

```sh
bash scripts/test-model-store.sh /PATH/TO/phonon-2.bps.tar.zst
python3 scripts/test-native-model-setup.py \
  "$PWD/build/PhononPlugin.bundle/Contents/Resources/Native/PhononSwift"
python3 scripts/test-native-helper.py \
  "$PWD/build/PhononPlugin.bundle/Contents/Resources/Native/PhononSwift" \
  "$HOME/Library/Application Support/TypeWhisper/PluginData/local.typewhisper.phonon/Models/fermion" \
  build/sample.wav
PHONON_TEST_DATA_DIR="$HOME/Library/Application Support/TypeWhisper/PluginData/local.typewhisper.phonon" \
  build/bundle-test build/PhononPlugin.bundle build/sample.wav
```

Use an empty cache path in the helper test to check fresh installation. Python is only the external test harness. The native release contains no interpreter or Python packages. The native build needs a full Xcode installation with its Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`).

The following sections document the Python variant and the earlier feasibility tool.

English batch transcription on Apple Silicon. The Swift plugin manages a local
Python/MLX Phonon-2 server. Audio stays on this Mac. No external transcription
provider or API key is required. Translation, live streaming, and dictionary or
prompt hints are unsupported.

## Use

Enable **Phonon Local** in TypeWhisper. Select **Phonon-2 (Local)** as the engine
and **Phonon-2** as the model. Use English or automatic language, with translation
off. No terminal command is needed with version 0.3.1.

The plugin starts its server when enabled, checks the loaded model through the
health endpoint, and reports readiness to TypeWhisper. Settings show startup,
ready, or error status and provide **Restart Phonon** and **Show Logs** buttons.
The first recording in a fresh process can take longer than subsequent recordings.

Disabling the plugin closes the owned server. Closing TypeWhisper also closes the
server, including after a host crash: the helper watches a private parent pipe
and the parent process. A server crash after readiness triggers up to three
restart attempts per activation, with 1/2/3-second delays. Startup failures or a
600-second startup timeout show an error requiring a restart. Recordings are not
automatically retried after a failed request.

The server binds only to `127.0.0.1` on an OS-assigned free port. Transcription
requires a random per-process token sent privately over stdin, not through process
arguments or a persisted settings file. The old manual server on port 8010 is no
longer used by the plugin. No launch agent, login item, or system-wide Python
change is needed.

## Runtime and model storage

Version 0.3.1 keeps the `.bundle` small (about 608 KB on the development Mac).
The plugin downloads a private Python 3.12.12/MLX runtime into its own data folder
on first activation. The tested runtime is about 473 MB on disk; its compressed
first-run downloads total about 146 MB. PyTorch, SymPy, NetworkX, and setuptools
are omitted. This reduces the active runtime footprint rather than merely moving
the former full environment outside the bundle.

Every interpreter archive and wheel has a pinned official HTTPS URL, byte count,
and SHA-256 in `Resources/runtime-manifest.json`. Python comes from Astral's
python-build-standalone releases; wheels come from official PyPI hosting. The
plugin verifies each download before extraction, installs in a temporary folder,
validates imports, and publishes the completed version atomically. A file lock
serializes concurrent setup. Failed or cancelled setup removes the temporary
installation; completed setup is reused offline. Settings show the current asset
being installed. No Homebrew, uv, Xcode, system Python, or checkout is needed to
use the plugin on another compatible Mac.

All active files are under:

`~/Library/Application Support/TypeWhisper/PluginData/local.typewhisper.phonon/`

- `Runtime/cpython312-phonon027-mlx-v2/`: private interpreter and MLX packages.
- `Models/fermion/speech/`: checksum-verified unpacked Phonon-2 weights.
- `Models/huggingface/`: original model download cache.
- `server.log`: the latest owned server's diagnostics.

Model weights are downloaded separately and never placed in the bundle. Internet
access is needed for initial runtime/model setup, then cached use is local.
Existing model caches can be copied into the above layout during migration.

The Python runtime starts in isolated mode with bytecode writes disabled. The
readiness file contains only port, PID, and instance ID; it is removed after
startup. The plugin does not write audio or the private token to that file or log.

## Build and install

Development requires an arm64 Mac, macOS 14+, Xcode/Swift 6+, `uv`, and exactly
TypeWhisper **1.6.1** in `/Applications`. The SDK source is pinned to TypeWhisper
tag v1.6.1, commit `7c4cdd20708556049dccbcb7520eeed44ec6c371`. The plugin links the
installed host SDK framework; no second SDK runtime is bundled. Rebuild and
reverify compatibility before using a different host version.

```sh
# In a fresh checkout under ~/Dev:
bash scripts/setup-runtime.sh
bash scripts/build.sh
# Quit TypeWhisper before installing:
bash scripts/install-plugin.sh
# For an existing installation, retain a backup outside the Plugins directory:
bash scripts/install-plugin.sh --replace
```

The build script uses full Xcode rather than incomplete Command Line Tools when
the known installed Xcode path is available, without changing global tool
selection. Set `DEVELOPER_DIR` explicitly for another Xcode location.

`scripts/setup-runtime.sh` prepares the developer environment. It is not required
on a Mac receiving the compiled bundle. `scripts/generate-runtime-manifest.py`
regenerates pinned asset metadata from official distributions when intentionally
updating dependencies; validate a fresh setup and transcription after any change.

The local plugin is ad-hoc signed. The TypeWhisper app signature and macOS
security protections remain unchanged. Distribution signing/notarization and
clean-Mac installation verification are separate release work.

## Verify

No manually running server is required. The harnesses activate the plugin or its
server controller and stop owned processes after testing.

```sh
say -v Samantha -o build/sample.aiff 'This is a local speech recognition test. Please schedule the project review for Friday afternoon.'
afconvert -f WAVE -d LEI16@16000 -c 1 build/sample.aiff build/sample.wav
build/error-test
# Validate first-run setup in a dedicated folder (kept for warm tests):
build/runtime-test "$PWD/build/test-plugin-data"
"$PWD/build/test-plugin-data/Runtime/cpython312-phonon027-mlx-v2/bin/python3.12" -I -B scripts/tls-test.py
PHONON_TEST_RUNTIME_DIR="$PWD/build/test-plugin-data/Runtime/cpython312-phonon027-mlx-v2" PHONON_TEST_DATA_DIR="$PWD/build/test-plugin-data" build/lifecycle-test
PHONON_TEST_DATA_DIR="$PWD/build/test-plugin-data" build/smoke-test build/sample.wav
PHONON_TEST_DATA_DIR="$PWD/build/test-plugin-data" build/bundle-test build/PhononPlugin.bundle build/sample.wav
codesign --verify --deep --strict build/PhononPlugin.bundle
```

The error harness owns a temporary HTTP fixture and checks audio validation,
unsupported options, WAV multipart, authentication, HTTP errors, malformed JSON,
and valid responses. The lifecycle harness checks real model startup, duplicate
start, authentication, server crash recovery, bounded retries, stop during
startup, rapid stop/start, startup timeout, and missing-runtime errors. The
`--owner` lifecycle mode exposes its child PID for an external host-death test.

`BENCHMARK.md` contains measurements from the original manual-server prototype;
those numbers do not establish the new managed startup latency. Microphone
permissions and real dictation should be checked by the user in TypeWhisper.

## Licensing and attribution

Plugin code is GPL-3.0-only. Vendored TypeWhisper SDK source retains GPLv3.
Phonon runtime is Apache-2.0. Phonon-2 weights are CC-BY-4.0, derived from NVIDIA
parakeet-tdt-0.6b-v3. Model material is not included in git or the bundle. See
`THIRD_PARTY_NOTICES.md`, the bundle's `Licenses` folder, and downloaded dependency
license metadata. Complete a distribution license review before public release.

Sources:
- https://www.typewhisper.com/en/addons/develop/
- https://github.com/TypeWhisper/typewhisper-mac
- https://github.com/fermionresearch/phonon
- https://huggingface.co/FermionResearch/Phonon-2

### HTTPS certificate trust

The managed Python helper uses `truststore` 0.10.4 to verify HTTPS connections with macOS Keychain trust. This supports organisation certificates already trusted by macOS. Certificate and hostname verification stay enabled. Runtime v2 adds this small package; the first launch provisions the updated runtime separately from the plugin bundle. If certificate errors persist on a managed Mac, ask IT to check the certificate chain and system trust for Hugging Face. Do not disable TLS verification.

### Native Swift feasibility prototype

`prototypes/phonon-swift` contains a separate native MLX command-line experiment, build instructions, and an automated comparison with the Python engine. It reads the same Phonon-2 container and checks all 697 mapped tensors. This experiment is not an installable plugin; startup, temporary checkpoint loading, and package size still need optimisation.
