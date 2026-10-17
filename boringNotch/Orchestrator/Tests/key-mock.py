# Self-exiting stateful mock serve on 47999 for the question card's key queue (run.sh --keymock). Never the live 4777.
# Renders a synthetic multi-select question; POST /api/chat {"key":"1".."3"} toggles that box, "Tab" is logged with the boxes it saw.
# POST /__reset; POST /__drop {"keys":["2"]} swallows the next such key (200, not applied); POST /__delay {"ms":n} slows every key POST.
# GET /__log returns [{key, t (seconds), ticked}].
import http.server, threading, os, json, re, time
HERE = os.path.dirname(os.path.abspath(__file__))
tpl = open(os.path.join(HERE, "fixtures", "multiselect-1.txt"), encoding="utf-8").read()
ticked, log, drop, delay = set(), [], [], 0
def screen():
    def f(m): return m.group(1) + m.group(2) + ". [" + ("✔" if int(m.group(2)) in ticked else " ") + "]"
    return re.sub(r"^(.*?\b)([123])\. \[.\]", f, tpl, flags=re.M)
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def _send(self, body):
        b = json.dumps(body).encode(); self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        p = self.path.split("?")[0]
        self._send(log if p == "/__log" else {"running": True, "screen": screen()} if p == "/api/chat" else {})
    def do_POST(self):
        global delay
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        if self.path == "/__reset": ticked.clear(); log.clear(); drop.clear(); delay = 0
        elif self.path == "/__drop": drop.extend(body["keys"])
        elif self.path == "/__delay": delay = body["ms"]
        elif self.path == "/api/chat" and "key" in body:
            time.sleep(delay / 1000)
            k = body["key"]
            log.append({"key": k, "t": time.time(), "ticked": sorted(ticked)})
            if k in drop: drop.remove(k)
            elif k in "123": ticked.symmetric_difference_update({int(k)})
        self._send({})
class S(http.server.ThreadingHTTPServer): daemon_threads = True
threading.Timer(120, os._exit, [0]).start()
S(("127.0.0.1", 47999), H).serve_forever()
