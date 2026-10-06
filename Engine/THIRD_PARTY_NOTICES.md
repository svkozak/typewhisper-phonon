The native engine uses Fermion Research's phonon-coreml 1.1.1 (Apache-2.0),
pinned to commit 464ae57460fed61d4feb6f2a7424b5be1213accb:
https://github.com/fermionresearch/phonon-coreml/tree/464ae57460fed61d4feb6f2a7424b5be1213accb

The upstream Swift library and C decoder are unmodified. The engine selects
CPU and Neural Engine compute units, serial encoder and decoder jobs, and eager
loading of every supported encoder window. Our adapter limits single windows
to 34.9 seconds and long-audio windows to 14.9 seconds, allowing the package's
20 ms margin when selecting an encoder function. Clips below 20 ms return empty
text before frontend normalization. Our model store compiles into a
verified local cache before calling the library. This keeps the compiled model
in PluginData instead of the library's shared cache location. Our WAV decoder
and AVAudioConverter resampler keep plugin audio in memory. The upstream
FileSource API is not used, because it can write temporary resampled audio.

The dependency's LICENSE and NOTICE are copied into the distributed bundle.
No Python code or model weights are copied into the bundle.

Phonon-2 Core ML model data is downloaded from FermionResearch/Phonon-2-CoreML,
revision e931079df1f6bff26f5f416c1c8880e76a0cf2a3, under CC-BY-4.0. Credit:
Fermion Research; base model nvidia/parakeet-tdt-0.6b-v3. Source and license:
https://huggingface.co/FermionResearch/Phonon-2-CoreML/tree/e931079df1f6bff26f5f416c1c8880e76a0cf2a3
https://creativecommons.org/licenses/by/4.0/

Downloaded files are not modified. Core ML creates a compiled model locally.
The download includes the model repository's NOTICE, code license, and weights
license. The model's source container checksum matches the Phonon-2 weights
used by the previous MLX engine.
