# Third-party notices

Phonon plugin code is GPL-3.0-only. Copyright (c) 2026 Sergii Kozak.
The vendored TypeWhisper 1.7.0 SDK interfaces retain their upstream GPLv3
license and copyright. See LICENSE, vendor/TYPEWHISPER-LICENSE, and
[vendor source details](vendor/README.md).

The native helper uses Fermion Research's phonon-coreml 1.1.1 (Apache-2.0).
Its LICENSE and NOTICE are included in the bundle's Resources/Licenses folder.
See [native component notices](Engine/THIRD_PARTY_NOTICES.md) for pinned source
versions and integration details.

Phonon-2 Core ML model weights are downloaded directly from Hugging Face and
are not included in the repository or plugin bundle. Credit Fermion Research
and NVIDIA: Phonon-2 is based on nvidia/parakeet-tdt-0.6b-v3. The weights retain
their separate CC-BY-4.0 license. The download includes the model's NOTICE and
licenses. Core ML compiles the model locally for inference.

Model source: https://huggingface.co/FermionResearch/Phonon-2-CoreML
Model license: https://creativecommons.org/licenses/by/4.0/
