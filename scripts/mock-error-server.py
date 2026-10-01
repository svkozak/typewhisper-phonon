"""Deterministic local HTTP test fixture; no model or personal audio."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, os, sys
from pathlib import Path
config = json.loads(sys.stdin.readline())
class Handler(BaseHTTPRequestHandler):
    count = 0
    def do_GET(self):
        payload = b'{"status":"ok","kind":"speech","model":"FermionResearch/Phonon-2"}'
        self.send_response(200); self.send_header('Content-Length', str(len(payload))); self.end_headers(); self.wfile.write(payload)
    def do_POST(self):
        assert self.headers.get('Authorization') == 'Bearer ' + config['token']
        body = self.rfile.read(int(self.headers['Content-Length']))
        assert self.path == '/v1/audio/transcriptions'
        assert 'multipart/form-data; boundary=' in self.headers['Content-Type']
        assert b'filename="audio.wav"' in body and b'Content-Type: audio/wav' in body
        assert b'RIFF' in body and b'WAVE' in body
        assert b'phonon-2' in body and b'name="response_format"' in body
        assert b'name="language"' not in body and b'name="prompt"' not in body
        responses = [(503, b'{"error":"test unavailable"}'), (200, b'{"unexpected":true}'), (200, b'{"text":"Mock transcript"}')]
        status, payload = responses[Handler.count]
        Handler.count += 1
        self.send_response(status); self.send_header('Content-Length', str(len(payload))); self.end_headers(); self.wfile.write(payload)
    def log_message(self, *args): pass
server = HTTPServer(('127.0.0.1', 0), Handler)
Path(config['ready_file']).write_text(json.dumps({'port': server.server_address[1], 'pid': os.getpid(), 'instance': config['instance']}))
server.timeout = 10
while Handler.count < 3:
    before = Handler.count
    server.handle_request()
    # Readiness GETs do not increment the transcript request count.
server.server_close()
print('PASS: loopback endpoint, WAV multipart, fixed model, omitted language/prompt')
