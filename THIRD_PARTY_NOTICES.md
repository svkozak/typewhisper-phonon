# Third-party notices

Phonon plugin code is GPL-3.0-only. Copyright (c) 2026 Sergii Kozak.
The vendored TypeWhisper 1.6.1 SDK interfaces retain their upstream GPLv3
license and copyright. See LICENSE and vendor/TYPEWHISPER-LICENSE.

The native helper uses MLX Swift and mlx-audio-swift (MIT), a container reader
adapted from Fermion Research 0.2.7 (Apache-2.0), and Zstandard 1.5.7
(distributed under BSD-3-Clause). Their licenses and the licenses of transitive
Swift dependencies are included in the bundle's Resources/Licenses folder.
See prototypes/phonon-swift/THIRD_PARTY_NOTICES.md for pinned source versions
and details of our changes.

Phonon-2 model weights are downloaded directly from Hugging Face and are not
included in the repository or plugin bundle. Credit Fermion Research and
NVIDIA: Phonon-2 is based on nvidia/parakeet-tdt-0.6b-v3. The weights retain
their separate CC-BY-4.0 license. The downloaded archive is unchanged; the
native loader expands the compressed weights for local inference.

Model source: https://huggingface.co/FermionResearch/Phonon-2
Model license: https://creativecommons.org/licenses/by/4.0/
