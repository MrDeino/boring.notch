# Self-exiting mock serve on 47999 for the approval answer round trip (ORCH_APPROVAL_MOCK). Never the live 4777.
# POST /__set {chat json} sets the GET /api/chat reply; GET /__log returns recorded POST /api/chat requests.
import http.server, threading, os, json
chat, log = {}, []
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, body):
        b = json.dumps(body).encode(); self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        self._send(log if self.path == "/__log" else chat)
    def do_POST(self):
        global chat
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        if self.path == "/__set": chat = body
        elif self.path == "/api/chat": log.append({"body": body, "xorch": self.headers.get("x-orch"), "ctype": self.headers.get("Content-Type")})
        self._send({})
threading.Timer(30, os._exit, [0]).start()
http.server.HTTPServer(("127.0.0.1", 47999), H).serve_forever()
