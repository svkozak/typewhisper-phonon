# TypeWhisper SDK source

The Swift interfaces in `TypeWhisperPluginSDK/` and `TYPEWHISPER-LICENSE` come
from TypeWhisper 1.7.0, pinned to source commit
`c9958a59454b214f267a9d79fdbf6798b8a6d538`:

https://github.com/TypeWhisper/typewhisper-mac/tree/c9958a59454b214f267a9d79fdbf6798b8a6d538/TypeWhisperPluginSDK/Sources/TypeWhisperPluginSDK

The files are unmodified. They provide a local Swift module for compilation.
The plugin links the SDK framework inside the installed TypeWhisper 1.7.0 app.
The SDK compatibility marker remains `v1`.

When updating the host version, copy the complete Swift source set and license
from a pinned host release. Update the build guard, manifest minimum host
version, notices, and documented verification. Run the bundle, error, and
lifecycle harnesses against that installed host.
