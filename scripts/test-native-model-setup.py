"""Check fresh Core ML setup, owner cancellation, retry, and cached startup.

An optional second argument retains the disposable model cache for other harnesses.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

executable = Path(sys.argv[1]).resolve()
revision = "e931079df1f6bff26f5f416c1c8880e76a0cf2a3"
with tempfile.TemporaryDirectory(prefix="phonon-native-setup-") as temp:
    root = Path(temp)
    cache = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else root / "Models" / "fermion"
    parent = cache / "speech" / "FermionResearch__Phonon-2-CoreML"
    model = parent / revision
    cached_only = len(sys.argv) > 3 and sys.argv[3] == "--cached-only"
    assert cached_only or not model.exists(), "Use a fresh disposable Core ML cache or --cached-only"
    # A previous MLX cache must survive the migration.
    legacy = cache / "speech" / "FermionResearch__Phonon-2" / "model_phonon2_c4c_int6"
    legacy.mkdir(parents=True, exist_ok=True)
    sentinel = legacy / "setup-test-preserve"
    sentinel.write_text("preserve legacy cache")

    def start(name):
        ready = root / f"{name}.json"
        with (root / f"{name}.log").open("wb") as log:
            child = subprocess.Popen([str(executable), "--serve"], stdin=subprocess.PIPE,
                                     stdout=log, stderr=log,
                                     env=dict(os.environ, FERMION_CACHE_DIR=str(cache)))
        child.stdin.write((json.dumps({"token": "setup-test", "instance": name,
                                      "ready_file": str(ready)}) + "\n").encode())
        child.stdin.flush()
        return child, ready

    def stop(child):
        child.stdin.close()
        assert child.wait(timeout=5) == 0

    def progress(ready):
        status = Path(str(ready) + ".status")
        if not status.exists():
            return None
        data = json.loads(status.read_text())
        assert not data["failed"], data
        return data["message"]

    children = []
    try:
        if not cached_only:
            child, ready = start("interrupted")
            children.append(child)
            deadline = time.monotonic() + 15
            while not list(parent.glob(".native-download-*")):
                assert child.poll() is None, (root / "interrupted.log").read_text()
                assert time.monotonic() < deadline
                time.sleep(0.01)
            stop(child)
            assert not ready.exists() and not model.exists()
            print("PASS: owner cancellation during download exits promptly; no partial model is published", flush=True)

            child, ready = start("preparation")
            children.append(child)
            messages = set()
            deadline = time.monotonic() + 1200
            while True:
                assert child.poll() is None, (root / "preparation.log").read_text()
                assert time.monotonic() < deadline, "Model download timeout"
                message = progress(ready)
                if message:
                    messages.add(message)
                    if "Preparing" in message:
                        break
                time.sleep(0.02)
            assert any("Downloading" in m for m in messages), messages
            stop(child)
            assert not ready.exists()
            assert sentinel.read_text() == "preserve legacy cache"
            print("PASS: retry verifies the model; cancellation during Core ML preparation exits promptly; MLX cache preserved", flush=True)

        def wait(child, ready):
            messages = set()
            deadline = time.monotonic() + 1200
            while not ready.exists():
                assert child.poll() is None, ready.with_suffix(".log").read_text()
                assert time.monotonic() < deadline, "Model setup timeout"
                message = progress(ready)
                if message:
                    messages.add(message)
                time.sleep(0.02)
            return messages

        if not cached_only:
            child, ready = start("retry")
            children.append(child)
            messages = wait(child, ready)
            assert not any("Downloading" in m for m in messages), messages
            assert any("Preparing" in m or "Loading" in m for m in messages), messages
            assert not list(parent.glob(".native-download-*"))
            assert not list(model.glob(".native-compile-*"))
            assert hashlib.sha256((model / "decoder.bin").read_bytes()).hexdigest() == "36fa7202dda85c603af60d930ab88d7e9f0d2a619490aff46f5384db924cfa70"
            assert json.loads((model / "native-download.json").read_text())["revision"] == revision
            assert (model / "Phonon-2.mlmodelc").is_dir()
            assert json.loads((model / "native-compiled.json").read_text())["revision"] == revision
            stop(child)
            print("PASS: preparation retry reclaims staging and publishes a compiled cache in PluginData", flush=True)

        child, ready = start("cached")
        children.append(child)
        messages = wait(child, ready)
        assert not any("Downloading" in m for m in messages), messages
        assert not list(parent.glob(".native-download-*"))
        assert sentinel.read_text() == "preserve legacy cache"
        stop(child)
        print("PASS: verified Core ML cache starts without download", flush=True)
    finally:
        sentinel.unlink(missing_ok=True)
        for child in children:
            if child.poll() is None:
                child.terminate()
                child.wait(timeout=5)
