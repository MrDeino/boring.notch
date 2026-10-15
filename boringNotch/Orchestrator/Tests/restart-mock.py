# Self-exiting mock serve on 47999 for the Claude update restart (ORCH_RESTART_MOCK). Never the live 4777.
# POST /__set {"chat": {...}, "busy": bool, "after": {...}}: GET /api/chat reply, whether a restart without force
# is refused (409), and the chat reply once a restart succeeds. GET /__log returns recorded restart POSTs.
import http.server, threading, os, json
st, log = {"chat": {}, "busy": False, "after": {}}, []
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, body, code=200):
        b = json.dumps(body).encode(); self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        self._send(log if self.path == "/__log" else st["chat"])
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        if self.path == "/__set": st.update(body); self._send({}); return
        if self.path == "/api/chat/restart":
            log.append({"body": body, "xorch": self.headers.get("x-orch"), "ctype": self.headers.get("Content-Type")})
            if st["busy"] and not body.get("force"): self._send({"error": "orchestrator is mid-turn"}, 409); return
            st["chat"] = st["after"]
        self._send(st["chat"])
threading.Timer(30, os._exit, [0]).start()
http.server.HTTPServer(("127.0.0.1", 47999), H).serve_forever()
