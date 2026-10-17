# Self-exiting mock serve on 47999 for deploys (ORCH_DEPLOY_MOCK). Never the live 4777. Synthetic data only.
# POST /__set <state json>: the GET /api/state reply (omit "deploys" to play an old serve).
import http.server, threading, os, json
st = {"runs": []}
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, body):
        b = json.dumps(body).encode(); self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self): self._send(st)
    def do_POST(self):
        st.clear(); st.update(json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")); self._send({})
threading.Timer(30, os._exit, [0]).start()
http.server.HTTPServer(("127.0.0.1", 47999), H).serve_forever()
