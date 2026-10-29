# Self-exiting mock serve on 47999 for run.sh --slowmock. Never the live 4777. Synthetic data only.
# POST /__set {chat, blocks, delay, on_key: {key: screen}, on_text: screen} merges settings; GET /api/state sleeps `delay` s.
# GET /__log: POST /api/chat bodies. GET /__events: the `since` of each /api/events connect ("" = none). POST /__drop ends open streams.
import http.server, threading, os, json, time, urllib.parse
cfg = {"chat": {}, "blocks": [], "delay": 0, "on_key": {}, "on_text": None}
log, events, gen = [], [], [0]
def after(since):
    ids = [b["id"] for b in cfg["blocks"]]
    return cfg["blocks"][ids.index(since) + 1:] if since in ids else cfg["blocks"]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, body, code=200):
        b = json.dumps(body).encode(); self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        u = urllib.parse.urlparse(self.path); since = urllib.parse.parse_qs(u.query).get("since", [None])[0]
        if u.path == "/__log": self._send(log)
        elif u.path == "/__events": self._send(events)
        elif u.path == "/api/state": time.sleep(cfg["delay"]); self._send({"runs": [{"id": "r1", "project": "demo", "state": "running", "prompt": "demo run"}]})
        elif u.path == "/api/chat": self._send(cfg["chat"])
        elif u.path == "/api/chat/blocks": self._send({"running": True, "blocks": after(since)})
        elif u.path == "/api/events":
            events.append(since or ""); g = gen[0]
            self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.end_headers()
            first = {"running": True, "blocks": after(since)}
            if not since: first["reset"] = True
            chat, last = json.dumps(cfg["chat"]), (cfg["blocks"][-1]["id"] if cfg["blocks"] else None)
            try:
                self.wfile.write(f"event: chat\ndata: {chat}\n\nevent: blocks\ndata: {json.dumps(first)}\n\n".encode()); self.wfile.flush()
                while gen[0] == g: # like serve: push chat and new blocks as they change
                    time.sleep(0.25); out = ": ping\n\n"
                    if json.dumps(cfg["chat"]) != chat: chat = json.dumps(cfg["chat"]); out += f"event: chat\ndata: {chat}\n\n"
                    new = after(last) if last else cfg["blocks"]
                    if new: last = new[-1]["id"]; out += f"event: blocks\ndata: {json.dumps({'running': True, 'blocks': new})}\n\n"
                    self.wfile.write(out.encode()); self.wfile.flush()
            except OSError: pass
        else: self._send({})
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        if self.path == "/__set": cfg.update(body); self._send({})
        elif self.path == "/__drop": gen[0] += 1; self._send({})
        elif self.path == "/api/chat":
            log.append(body)
            if body.get("key") in cfg["on_key"]: cfg["chat"] = {**cfg["chat"], "screen": cfg["on_key"][body["key"]]}
            if "text" in body and cfg["on_text"]: cfg["chat"] = {**cfg["chat"], "screen": cfg["on_text"]}
            self._send({})
        else: self._send({})
threading.Timer(180, os._exit, [0]).start()
s = http.server.ThreadingHTTPServer(("127.0.0.1", 47999), H); s.daemon_threads = True; s.serve_forever()
