"""Test the native helper protocol; Python is only the external test harness."""
import json
import io
import os
from pathlib import Path
import secrets
import subprocess
import struct
import sys
import tempfile
import time
import urllib.error
import urllib.request
import wave

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
            deadline = time.monotonic() + 1200
            while not ready.exists():
                assert process.poll() is None, (folder / "helper.log").read_text()
                assert time.monotonic() < deadline, "Native readiness timeout"
                time.sleep(0.1)
            metadata = json.loads(ready.read_text())
            assert metadata["pid"] == process.pid and metadata["instance"] == "protocol-test"
            base = f"http://127.0.0.1:{metadata['port']}"
            health = json.loads(opener.open(base + "/health", timeout=5).read())
            assert health["engine"] == "swift-coreml" and health["status"] == "ok"
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

            converted = folder / "stereo-44100.wav"
            subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@44100", "-c", "2",
                            str(wav), str(converted)], check=True)
            text = json.loads(post(converted.read_bytes()).read())["text"]
            assert text == expected, text
            print("PASS: 44.1 kHz stereo WAV is mixed and resampled in memory")

            with wave.open(str(wav), "rb") as source:
                assert source.getnchannels() == 1 and source.getframerate() == 16000
                pcm = source.readframes(source.getnframes())
            samples = struct.unpack("<" + "h" * (len(pcm) // 2), pcm)

            def float_wav(values):
                data = struct.pack("<" + "f" * len(values), *values)
                fmt = struct.pack("<HHIIHH", 3, 1, 16000, 64000, 4, 32)
                body = b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(data)) + data
                return b"RIFF" + struct.pack("<I", len(body) + 4) + b"WAVE" + body

            text = json.loads(post(float_wav([s / 32768 for s in samples])).read())["text"]
            assert text == expected, text
            print("PASS: float32 WAV produces the expected transcript")
            try:
                post(float_wav([float("nan")] * 16000))
                raise AssertionError("Non-finite audio accepted")
            except urllib.error.HTTPError as error:
                assert error.code == 400
            assert json.loads(post(float_wav([0.0] * 16000)).read())["text"] == ""
            assert json.loads(post(float_wav([0.4] * 159)).read())["text"] == ""
            assert json.loads(post(float_wav([0.4] * 160)).read())["text"] == ""
            print("PASS: non-finite audio rejected; silence and tiny clips return empty text")

            boundary_audio = io.BytesIO()
            with wave.open(boundary_audio, "wb") as output:
                output.setnchannels(1)
                output.setsampwidth(2)
                output.setframerate(16000)
                output.writeframes(((pcm + bytes(32000)) * 7)[:35 * 32000])
            text = json.loads(post(boundary_audio.getvalue()).read())["text"]
            assert text.startswith(expected), text
            print("PASS: an exact 35-second recording transcribes without an encoder boundary error")

            long_audio = io.BytesIO()
            with wave.open(long_audio, "wb") as output:
                output.setnchannels(1)
                output.setsampwidth(2)
                output.setframerate(16000)
                for _ in range(7):
                    output.writeframes(pcm + bytes(32000))
            text = json.loads(post(long_audio.getvalue()).read())["text"]
            import re
            normalize = lambda value: re.findall(r"[a-z0-9]+", value.lower())
            assert normalize(text) == normalize(expected * 7), text
            print("PASS: audio longer than 35 seconds retains all words across encoder windows")
            helper_log = (folder / "helper.log").read_text()
            assert expected not in helper_log, "Transcript leaked into helper logs"
            process.stdin.close()
            assert process.wait(timeout=5) == 0
            print("PASS: closing the owner pipe stops the native helper")
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
