"""Validation only. The Swift executable never starts or imports Python."""
import hashlib
import json
import pathlib
import sys
import time

import mlx.core as mx
import numpy as np
from fermion._speech import engine_phonon2
from fermion._speech.engine import read_audio
from fermion._speech._engine_phonon2 import load as load_engine

directory, audio_path, audit_path = map(pathlib.Path, sys.argv[1:4])
if audit_path.exists():
    # Verify every mapped tensor, not just the final transcript.
    reader = load_engine("fermion_container")
    mapper = load_engine("hf_to_mlx_parakeet")
    tensors, index = reader.read_container(str(directory / "model.fermion"))
    expected = mapper.hf_to_mlx(tensors)
    observed = json.loads(audit_path.read_text())
    assert set(expected) == set(observed), "Tensor name sets differ"
    for name, values in expected.items():
        assert list(values.shape) == observed[name]["shape"], name
        digest = hashlib.sha256(np.ascontiguousarray(values.astype(np.float32)).tobytes()).hexdigest()
        assert digest == observed[name]["sha256"], "Tensor values differ: " + name
    print("PASS: all 697 Swift tensor names, shapes, and float32 values match Python exactly", file=sys.stderr)
    del tensors, expected

start = time.perf_counter()
model = engine_phonon2.load(directory, profile="five-value", backend="phonon2-five-value")
load_seconds = time.perf_counter() - start
audio = read_audio(audio_path)
load_peak_memory = mx.get_peak_memory()
mx.reset_peak_memory()
transcripts, latencies = [], []
for _ in range(5):
    start = time.perf_counter()
    text, _, _ = model.transcribe_array(audio)
    mx.synchronize()
    latencies.append(time.perf_counter() - start)
    transcripts.append(text)
print(json.dumps({
    "engine": "Fermion 0.2.7 / Python MLX / upstream default optimisations",
    "model_container_sha256": hashlib.sha256((directory / "model.fermion").read_bytes()).hexdigest(),
    "model_load_seconds": load_seconds,
    "audio_seconds": len(audio) / 16000,
    "decode_seconds": latencies,
    "transcripts": transcripts,
    "mlx_peak_memory_bytes": mx.get_peak_memory(),
    "mlx_load_peak_memory_bytes": load_peak_memory,
    "mlx_active_memory_bytes": mx.get_active_memory(),
    "configuration": model.describe(),
}, indent=2))
