# Local validation — 2026-10-01

Machine: MacBook Air Mac14,2, M2, 8 GB; macOS 26.6; Xcode 27 / Swift 6.4; native arm64 Python 3.12.12.

Input: macOS Samantha generated speech, 5.536 seconds, mono 16 kHz PCM WAV. Expected and actual transcript match: “This is a local speech recognition test. Please schedule the project review for Friday afternoon.” No personal recordings or microphone were used.

- First environment model load / shader setup: server-reported 24.3 seconds (excludes download; not a full measured startup wall-clock).
- First transcription after model load: 3.94 seconds HTTP wall-clock; 3.902 seconds server decode.
- Warm calls through actual Swift plugin method: 0.377 and 0.356 seconds.
- Warm dynamic `.bundle` load + actual protocol transcription: 0.354 seconds (request latency; bundle load preceded timer).
- Translation and invalid WAV rejection checks passed.
- Build passed. Bundle principal class resolves and conforms to the installed host SDK protocols; dynamic bundle transcription passed.
- TypeWhisper scan finds 1 external plugin bundle and registers it disabled by default. In-host activation / engine selection / dictation remain untested: Computer Use failed with ScreenCaptureKit -3811 audio/video capture failure. No permissions were granted or security settings changed.

Memory: `vmmap -summary` on the Phonon process reported physical footprint **2.5 GB**, peak **3.1 GB**. Earlier snapshot showed swapped writable regions; RSS alone (roughly 50 MB in ps at one snapshot) badly understates this workload and must not be treated as model memory. This measures the whole Python runtime/model/MLX process, not isolated weights or peak system-wide GPU allocation. On an 8 GB machine this is a meaningful constraint. Keep heavy apps closed and validate sustained dictation before routine adoption.

Temporary server stopped after tests; restart manually with `bash scripts/serve.sh`. Host app installed; plugin bundle installed but remains disabled pending UI activation.
