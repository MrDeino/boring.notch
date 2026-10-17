# Self-exiting mock serve on 47999 for POST /api/chat/file (ORCH_FILE_MOCK). Never the live 4777.
# Needs x-orch: 1 and x-filename. "boom*" answers 500, "huge*" 413, "flaky*" 500 once then 200. Files are kept in memory only.
# Answers {"path": "/mock/<n>-<name>"}. GET /__log returns [{path, filename, size, ctype, xorch}] for /api/chat/file and /api/chat/image.
import http.server, threading, os, json, urllib.parse
log, flaky_seen = [], set()
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, body, code=200):
        b = json.dumps(body).encode(); self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        self._send(log if self.path == "/__log" else {})
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        size = 0
        while size < n: size += len(self.rfile.read(min(65536, n - size)))
        name = self.headers.get("x-filename")
        e = {"path": self.path, "filename": name, "size": size, "ctype": self.headers.get("Content-Type"), "xorch": self.headers.get("x-orch")}
        if self.path not in ("/api/chat/file", "/api/chat/image") or e["xorch"] != "1" or (self.path == "/api/chat/file" and not name):
            self._send({"error": "bad"}, 400); return
        log.append(e)
        shown = urllib.parse.unquote(name or "img.png")
        if shown.startswith("boom"): self._send({"error": "mock"}, 500); return
        if shown.startswith("huge"): self._send({"error": "mock"}, 413); return
        if shown.startswith("flaky") and shown not in flaky_seen: flaky_seen.add(shown); self._send({"error": "mock"}, 500); return
        self._send({"path": "/mock/%d-%s" % (len(log), shown)})
threading.Timer(90, os._exit, [0]).start()
http.server.HTTPServer(("127.0.0.1", 47999), H).serve_forever()
