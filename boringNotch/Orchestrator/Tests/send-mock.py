# Self-exiting mock serve on 47999 for the composer send path (run.sh --sendmock). Never the live 4777.
# POST /__set {chat json} sets GET /api/chat; POST /__fail {"code": n} makes POST /api/chat answer n (0 = 200).
# GET /api/chat/blocks never echoes a sent message. GET /__log returns recorded POST /api/chat bodies.
import http.server, threading, os, json
chat, log, fail = {}, [], 0
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, body, code=200):
        b = json.dumps(body).encode(); self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/__log": self._send(log)
        elif p == "/api/chat": self._send(chat)
        elif p == "/api/chat/blocks": self._send({"running": True, "blocks": []})
        else: self._send({})
    def do_POST(self):
        global chat, fail
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        if self.path == "/__set": chat = body; self._send({})
        elif self.path == "/__fail": fail = body.get("code", 0); self._send({})
        elif self.path == "/api/chat":
            if fail: self._send({"error": "mock"}, fail); return
            log.append({"body": body, "xorch": self.headers.get("x-orch"), "ctype": self.headers.get("Content-Type")}); self._send({})
        else: self._send({})
threading.Timer(120, os._exit, [0]).start()
http.server.HTTPServer(("127.0.0.1", 47999), H).serve_forever()
