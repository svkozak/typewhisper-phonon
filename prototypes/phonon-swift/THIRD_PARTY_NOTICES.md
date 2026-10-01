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

The build script reuses the precompiled mlx.metallib from the locally installed
MLX 0.32.3 wheel for the experiment. This compiled MIT-licensed GPU library is
copied alongside the executable. It executes without a Python runtime.
