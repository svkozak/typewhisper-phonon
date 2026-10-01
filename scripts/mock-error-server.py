"""Deterministic local HTTP test fixture; no model or personal audio."""
from http.server import BaseHTTPRequestHandler, HTTPServer
class Handler(BaseHTTPRequestHandler):
    count = 0
    def do_POST(self):
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
server = HTTPServer(('127.0.0.1', 8010), Handler)
server.timeout = 10
while Handler.count < 3:
    before = Handler.count
    server.handle_request()
    if Handler.count == before: raise TimeoutError('Test request did not arrive')
server.server_close()
print('PASS: loopback endpoint, WAV multipart, fixed model, omitted language/prompt')
