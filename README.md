# TypeWhisper + Phonon-2 local prototype

WAV-first, English batch transcription on Apple Silicon. Personal prototype. Source may be shared through the owner’s private GitHub repository; no public release or marketplace publication. No translation, live streaming, dictionary/prompt hints, account, or API key. Audio goes to the fixed loopback address `127.0.0.1:8010`, never a configured external provider. The unauthenticated endpoint can be used by other local processes while running.

## Installed and pinned

- TypeWhisper 1.6.1, official vendor-linked GitHub DMG; signature verified and Gatekeeper accepted as Notarized Developer ID (team 2D8ALY3LCL).
- SDK source: TypeWhisper/typewhisper-mac tag v1.6.1, commit 7c4cdd20708556049dccbcb7520eeed44ec6c371. Unmodified SDK sources are vendored solely to emit a compile-time module; plugin links the actual installed host framework. No second SDK runtime is bundled.
- Python 3.12.12 arm64, isolated uv-managed runtime in `.python`; `.venv` uses it. System Python unchanged. Managed Python comes from Astral's python-build-standalone distribution via uv.
- fermion-research 0.2.7 and native MLX dependencies from official PyPI; all resolved versions in `requirements.lock`.
- Official FermionResearch/Phonon-2 five-value model, archive SHA256 `98125795b6dda72f5c6eee9ba33d19815df65dcb18b50a357bf9f73c9935309e`; runtime verified the pinned archive and extracted member hashes.

## Use

Run from this repository:

```sh
bash scripts/serve.sh
```

Keep that terminal running; Control-C stops the server. No launch agent, login item, autostart, or background service was installed. Phonon caches unpacked speech weights in `~/.cache/fermion/speech/`; Hugging Face downloads use this repo's `.cache/huggingface`. Initial setup is about 1 GB for the venv, 54 MB Python, plus downloaded/unpacked model caches.

The plugin is installed at `~/Library/Application Support/TypeWhisper/Plugins/PhononPlugin.bundle`. In TypeWhisper, enable **Phonon Local**, select **Phonon-2 (Local)** as the transcription engine and **Phonon-2** as the model. Use English or automatic language and turn off translation. Microphone/accessibility permissions have not been granted by this task; the user must approve those before real dictation. The host scan registered the external bundle **disabled by default**. UI activation/selection has not been verified because Computer Use hit a ScreenCaptureKit capture failure. See BENCHMARK.md for measured latency and the 2.5 GB process footprint / 3.1 GB peak.

The settings view explains the fixed endpoint and manual server command. Errors cover server unavailable, unsupported language/translation, invalid WAV, oversized recording, HTTP failures, and malformed responses. Prompt hints are intentionally omitted because Phonon ignores them.

## Build and verify

Requires arm64 Mac, Xcode/Swift 6+, macOS 14+, TypeWhisper **1.6.1** in `/Applications`. This is pinned to the host binary and source, not intended as a universal ABI compatibility claim. Rebuild and reverify against any future host update.

```sh
bash scripts/build.sh
# With server running and a generated/nonprivate WAV:
build/smoke-test build/sample.wav
build/bundle-test build/PhononPlugin.bundle build/sample.wav
# Install on another local setup only if destination does not already exist:
bash scripts/install-plugin.sh
```

The build uses ad-hoc signing for the local plugin only. The vendor app signature and macOS security protections are unchanged. Public release would require an appropriate distribution signing/notarization plan.

Generate the nonprivate benchmark sample with the installed macOS Samantha voice:

```sh
say -v Samantha -o build/sample.aiff 'This is a local speech recognition test. Please schedule the project review for Friday afternoon.'
afconvert -f WAVE -d LEI16@16000 -c 1 build/sample.aiff build/sample.wav
```

## Licensing and attribution

Prototype code is GPL-3.0-only; see LICENSE. Vendored SDK is from TypeWhisper and retains its original GPLv3 license in `vendor/TYPEWHISPER-LICENSE`. Phonon runtime is Apache-2.0. Phonon-2 weights are CC-BY-4.0, a derivative of NVIDIA parakeet-tdt-0.6b-v3; model weights are not included in git. Retain Fermion Research attribution and upstream model NOTICE/license when distributing model material. Review all dependency licenses before any public distribution.

Sources: https://www.typewhisper.com/en/ ; https://github.com/TypeWhisper/typewhisper-mac ; https://github.com/fermionresearch/phonon ; https://huggingface.co/FermionResearch/Phonon-2 .

## Install on HomeBookPro

This prototype requires **Apple Silicon**, macOS 14+, Xcode/Swift 6+, and exactly TypeWhisper **1.6.1**. Build checks enforce architecture and host version. The HomeBookPro hardware has not been assessed here.

1. Install TypeWhisper 1.6.1 from the official vendor-linked release: https://github.com/TypeWhisper/typewhisper-mac/releases/tag/v1.6.1 . Put TypeWhisper.app in `/Applications`. Preserve Gatekeeper protections; verify the app with `codesign --verify --deep --strict /Applications/TypeWhisper.app` and `spctl --assess --type execute -v /Applications/TypeWhisper.app`.
2. Install Xcode and complete its normal first-run setup. Install `uv` using Astral's official instructions (https://docs.astral.sh/uv/getting-started/installation/) or the Homebrew registry (`brew install uv`). Authenticate GitHub using your normal credentials to access the private repo.
3. Clone into a new folder and build:

```sh
mkdir -p ~/Dev
cd ~/Dev
git clone https://github.com/svkozak/typewhisper-phonon.git
cd typewhisper-phonon
bash scripts/setup-runtime.sh
bash scripts/build.sh
bash scripts/install-plugin.sh
bash scripts/serve.sh
```

The runtime script preserves existing environments and syncs exact versions from official PyPI. The server’s first run downloads and checksum-verifies the official model. Keep this terminal open. In TypeWhisper enable Phonon Local and select Phonon-2 (Local) / Phonon-2, English, with translation off. Approve microphone/accessibility only when you decide to use dictation. These permissions and plugin activation are manual; installation scripts do not grant them.

For diagnostics with no server listening on 8010, `build/error-test` checks local validation and unavailable-server errors. A temporary test fixture is `scripts/mock-error-server.py`; running `build/error-test --mock` while it listens tests WAV multipart, HTTP failures and malformed responses. It serves exactly three requests and exits; it never uses model weights or personal audio.
