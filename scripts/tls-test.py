"""Run with the provisioned Python runtime; no system trust changes required."""
import pathlib
import runpy
import ssl
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


# Truststore is for outbound clients; the local test server uses native SSL.
server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
root = pathlib.Path(__file__).resolve().parents[1]
runpy.run_path(str(root / "scripts/managed-server.py"))["configure_tls"]()

import httpx
import truststore
from huggingface_hub import HfApi

assert isinstance(ssl.create_default_context(), truststore.SSLContext)
with tempfile.TemporaryDirectory() as folder:
    cert = pathlib.Path(folder) / "cert.pem"
    key = pathlib.Path(folder) / "key.pem"
    subprocess.run([
        "/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", str(key), "-out", str(cert), "-days", "1",
        "-sha256", "-addext", "basicConstraints=critical,CA:TRUE",
        "-addext", "keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign",
        "-addext", "extendedKeyUsage=serverAuth",
        "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"verified")

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server_context.load_cert_chain(cert, key)
    server.socket = server_context.wrap_socket(server.socket, server_side=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    try:
        with httpx.Client(trust_env=False) as client:
            try:
                client.get(f"https://localhost:{port}")
            except httpx.ConnectError:
                print("PASS: untrusted certificate rejected")
            else:
                raise AssertionError("Untrusted certificate accepted")
        context = ssl.create_default_context(cafile=str(cert))
        with httpx.Client(verify=context, trust_env=False) as client:
            assert client.get(f"https://localhost:{port}").text == "verified"
            print("PASS: explicitly trusted certificate accepted")
            try:
                client.get(f"https://127.0.0.1:{port}")
            except httpx.ConnectError:
                print("PASS: wrong hostname rejected")
            else:
                raise AssertionError("Wrong hostname accepted")
    finally:
        server.shutdown()
        server.server_close()
        thread.join()

info = HfApi().model_info("FermionResearch/Phonon-2")
assert info.id == "FermionResearch/Phonon-2"
print("PASS: live Hugging Face metadata request with system certificate trust")
