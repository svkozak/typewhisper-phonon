The prototype uses MLX Swift 0.32.3 (MIT) and mlx-audio-swift at commit
8d86630ade569728aaea3dc1a29fc44e2efa719b (MIT). Other transitive dependencies
are pinned in Package.resolved. Their licenses remain in the SwiftPM checkouts.

Container.swift ports the container reader and tensor name mapping from
fermion-research 0.2.7 (Apache-2.0). The original license is included as
FERMION-LICENSE. The Phonon model is not included in this prototype.

The two-line dependency patch explicitly selects MLX.compile instead of the
MLXLMCommon overload. It does not add unchecked Sendable conformances or relax
Swift concurrency checking. The command-line experiment invokes inference
serially from one thread; this does not establish safe concurrent inference.

The build script compiles MLX Swift's prepared Metal kernels with Apple's Metal
compiler. No Python library is copied into the native bundle.

The streaming model decoder uses Zstandard 1.5.7 (BSD-3-Clause or GPL-2.0;
distributed here under BSD-3-Clause). Its amalgamated decoder was generated
from facebook/zstd commit f8745da6ff1ad1e7bab384bd1f9d742439278e99 with the
upstream build/single_file_libs/combine.py tool. The original LICENSE and
COPYING files are included. The generator is CC0/public domain.

Phonon-2 weights are downloaded from FermionResearch/Phonon-2, revision
ca1bef26bcd8ef4a7e16d0636d8a77bb25e298ee, under CC-BY-4.0. Credit:
Fermion Research; base model nvidia/parakeet-tdt-0.6b-v3. Source and license:
https://huggingface.co/FermionResearch/Phonon-2
https://creativecommons.org/licenses/by/4.0/
Weights remain outside the plugin bundle and are not modified by download.
The native loader expands the container into dense bfloat16 tensors for MLX.
