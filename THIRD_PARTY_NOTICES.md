# Third-party components

The Phonon TypeWhisper plugin is GPL-3.0-only. Its SDK interfaces are from
TypeWhisper 1.6.1 (GPLv3). See Resources/Licenses in the installed bundle.

The separately downloaded runtime contains Python 3.12.12 from Astral's
python-build-standalone distribution and the dependency versions pinned in
Resources/runtime-manifest.json (a tested subset of requirements.lock). The Python runtime retains its LICENSE files. Python packages
retain their accompanying license files and .dist-info metadata under
the plugin data Runtime/<version>/lib/python3.12/site-packages.

Fermion Research's Phonon runtime is Apache-2.0:
https://github.com/fermionresearch/phonon

Phonon-2 model weights are downloaded separately, not included in the bundle.
They are CC-BY-4.0 and derive from NVIDIA parakeet-tdt-0.6b-v3. Credit Fermion
Research and NVIDIA. Retain the upstream model license and NOTICE when
redistributing model material:
https://huggingface.co/FermionResearch/Phonon-2

This is a local prototype, ad-hoc signed. A public release requires a complete
distribution license review and appropriate signing/notarization.

The runtime also includes truststore 0.10.4 (MIT), which connects Python HTTPS certificate verification to the macOS system trust store. Its license is retained in its wheel metadata.
