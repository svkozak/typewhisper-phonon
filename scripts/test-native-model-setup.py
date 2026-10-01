"""Check interrupted fresh setup, retry, progress, and cached native startup."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

executable = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="phonon-native-setup-") as temp:
    root = Path(temp)
    cache = root / "Models" / "fermion"
    parent = cache / "speech" / "FermionResearch__Phonon-2"
    model = parent / "model_phonon2_c4c_int6"

    def start(name):
        ready = root / f"{name}.json"
        log = (root / f"{name}.log").open("wb")
        child = subprocess.Popen([str(executable), "--serve"], stdin=subprocess.PIPE,
                                 stdout=log, stderr=log,
                                 env=dict(os.environ, FERMION_CACHE_DIR=str(cache)))
        log.close()
        child.stdin.write((json.dumps({"token": "setup-test", "instance": name,
                                      "ready_file": str(ready)}) + "\n").encode())
        child.stdin.flush()
        return child, ready

    def stop(child):
        child.stdin.close()
        assert child.wait(timeout=5) == 0

    children = []
    try:
        child, ready = start("interrupted")
        children.append(child)
        deadline = time.monotonic() + 15
        while not list(parent.glob(".native-download-*")):
            assert child.poll() is None, (root / "interrupted.log").read_text()
            assert time.monotonic() < deadline
            time.sleep(0.01)
        stop(child)
        assert not ready.exists() and not model.exists()
        print("PASS: owner cancellation during initial setup exits promptly; no partial model is published", flush=True)

        def wait(child, ready):
            messages = set()
            deadline = time.monotonic() + 120
            status = Path(str(ready) + ".status")
            while not ready.exists():
                assert child.poll() is None, ready.with_suffix(".log").read_text()
                assert time.monotonic() < deadline, "Model setup timeout"
                if status.exists():
                    progress = json.loads(status.read_text())
                    assert not progress["failed"], progress
                    messages.add(progress["message"])
                time.sleep(0.02)
            return messages

        child, ready = start("retry")
        children.append(child)
        messages = wait(child, ready)
        assert any("Downloading" in m for m in messages), messages
        assert any("Loading" in m for m in messages), messages
        assert not list(parent.glob(".native-download-*"))
        assert hashlib.sha256((model / "model.fermion").read_bytes()).hexdigest() == "4b6bfa3a12cc3c4e0a54f2ab3ec4ca7a842b09e5c7ecfc8e7ca0ac6cc8c11468"
        assert json.loads((model / "native-download.json").read_text())["revision"] == "ca1bef26bcd8ef4a7e16d0636d8a77bb25e298ee"
        stop(child)
        print("PASS: retry reclaims staging, reports progress, verifies hashes, and removes compressed temporary files", flush=True)

        child, ready = start("cached")
        children.append(child)
        messages = wait(child, ready)
        assert not any("Downloading" in m for m in messages), messages
        assert not list(parent.glob(".native-download-*"))
        stop(child)
        print("PASS: verified model cache starts without download", flush=True)
    finally:
        for child in children:
            if child.poll() is None:
                child.terminate()
                child.wait(timeout=5)
