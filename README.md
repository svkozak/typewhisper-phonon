# Phonon

Local on-device English dictation for [TypeWhisper](https://www.typewhisper.com/), powered by
[Phonon-2](https://www.fermionresearch.com/models/phonon-2/) and native Swift/MLX.

## Requirements

- Apple Silicon Mac with macOS 14 or later.
- TypeWhisper **1.6.1** (the tested host version).
- Internet access for the first model download (164 MB).
- About 180 MB for the cached model. Allow roughly 2 GB of free disk space
  during startup for temporary model loading files, which are removed afterward.

## Install

1. Open the release disk image.
2. In TypeWhisper open Settings > Integrations and click 'Install Plugin'
3. Select `PhononPlugin.bundle` on the mounted disk.
4. Wait for the model download and preparation, then select the **Phonon** engine
   and **Phonon-2** model.

Model files and logs are stored under:

```text
~/Library/Application Support/TypeWhisper/PluginData/local.typewhisper.phonon/
```

Check the model status in the plugin settings. If setup fails, select **Retry**.
Logs are available under **Troubleshooting → Show Logs**.

## Development

Building needs full Xcode with Swift 6.3+, its Metal toolchain, and
TypeWhisper 1.6.1 installed in `/Applications`.

```sh
bash scripts/build.sh
# Quit TypeWhisper before installing:
bash scripts/install-plugin.sh --replace
```

See [Development](docs/DEVELOPMENT.md) for verification and release commands.

## License and attribution

The plugin is licensed under **GPL-3.0-only**. See [LICENSE](LICENSE).
TypeWhisper SDK code retains its upstream copyright and GPLv3 license.
Third-party components retain their own licenses; see
[Third-party notices](THIRD_PARTY_NOTICES.md) and
[Native component notices](prototypes/phonon-swift/THIRD_PARTY_NOTICES.md).

This plugin uses [Phonon-2](https://huggingface.co/FermionResearch/Phonon-2) by
Fermion Research, based on NVIDIA's Parakeet TDT 0.6B v3.

Model weights are downloaded directly from Hugging Face, are not included in the plugin bundle,
and are licensed separately under [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/).
