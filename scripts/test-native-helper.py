"""Test the native helper protocol; Python is only the external test harness."""
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

executable, cache, wav = map(Path, sys.argv[1:4])
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

with tempfile.TemporaryDirectory(prefix="phonon-native-protocol-") as folder:
    folder = Path(folder)
    stale = folder / "native-load-2147483647-interrupted"
    stale.mkdir()
    (stale / "partial").write_text("interrupted loading")
    ready = folder / "ready.json"
    token = secrets.token_hex(32)
    environment = dict(os.environ, FERMION_CACHE_DIR=str(cache))
    with (folder / "helper.log").open("wb") as log:
        process = subprocess.Popen([str(executable), "--serve"], stdin=subprocess.PIPE,
                                   stdout=log, stderr=log, env=environment)
        try:
            process.stdin.write((json.dumps({"token": token, "ready_file": str(ready), "instance": "protocol-test"}) + "\n").encode())
            process.stdin.flush()
            deadline = time.monotonic() + 120
            while not ready.exists():
                assert process.poll() is None, (folder / "helper.log").read_text()
                assert time.monotonic() < deadline, "Native readiness timeout"
                time.sleep(0.1)
            metadata = json.loads(ready.read_text())
            assert metadata["pid"] == process.pid and metadata["instance"] == "protocol-test"
            base = f"http://127.0.0.1:{metadata['port']}"
            health = json.loads(opener.open(base + "/health", timeout=5).read())
            assert health["engine"] == "swift-mlx" and health["status"] == "ok"
            assert not stale.exists(), "Interrupted load was not reclaimed"
            print("PASS: owned native readiness, loopback health, interrupted-load cleanup")

            def post(audio, authorised=True):
                boundary = "NativeTest" + secrets.token_hex(8)
                body = (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="audio.wav"\r\nContent-Type: audio/wav\r\n\r\n'.encode()
                        + audio + f'\r\n--{boundary}--\r\n'.encode())
                headers = {"Content-Type": "multipart/form-data; boundary=" + boundary}
                if authorised:
                    headers["Authorization"] = "Bearer " + token
                return opener.open(urllib.request.Request(base + "/v1/audio/transcriptions", data=body, headers=headers), timeout=120)

            try:
                post(wav.read_bytes(), authorised=False)
                raise AssertionError("Unauthorised request accepted")
            except urllib.error.HTTPError as error:
                assert error.code == 401
            print("PASS: private token required")
            try:
                post(b"not a WAV file" * 10)
                raise AssertionError("Invalid WAV accepted")
            except urllib.error.HTTPError as error:
                assert error.code == 400
            print("PASS: malformed audio rejected; helper stays alive")

            expected = "This is a local speech recognition test. Please schedule the project review for Friday afternoon."
            for _ in range(2):
                text = json.loads(post(wav.read_bytes()).read())["text"]
                assert text == expected, text
            print("PASS: two authenticated WAV requests produce the expected transcript")
            process.stdin.close()
            assert process.wait(timeout=5) == 0
            print("PASS: closing the owner pipe stops the native helper")
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
