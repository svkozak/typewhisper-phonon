# TypeWhisper Phonon

Local on-device English dictation plugin for [TypeWhisper](https://www.typewhisper.com/), powered by
[Phonon-2](https://www.fermionresearch.com/models/phonon-2/) model and native Swift/Core ML.

## Requirements

- Apple Silicon Mac with macOS 15 or later.
- TypeWhisper **1.7.0 or 1.7.1** (the tested host versions).
- Internet access for the first model download (345 MB).
- About 700 MB for downloaded and compiled model files. First setup and the
  system Neural Engine cache need additional space. Preparation can take
  several minutes. Preserved rollback caches also use additional space.

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

Building needs full Xcode with Swift 6.3+ and
TypeWhisper 1.7.0 or 1.7.1 installed in `/Applications`.

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
[Native component notices](Engine/THIRD_PARTY_NOTICES.md).

This plugin uses [Phonon-2 Core ML](https://huggingface.co/FermionResearch/Phonon-2-CoreML) by
Fermion Research, based on NVIDIA's Parakeet TDT 0.6B v3.

Model weights are downloaded directly from Hugging Face, are not included in the plugin bundle,
and are licensed separately under [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/).
