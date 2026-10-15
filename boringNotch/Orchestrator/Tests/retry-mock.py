# Self-exiting mock serve on 47998 for the send retry (ORCH_RETRY_MOCK). Never the live 4777.
# The first path segment is a scenario: /drop1/... closes its first connection without a response, then answers 200;
# /s500/... and /s409/... answer that status. GET /__count/<scenario> returns how many requests arrived for it.
import socketserver, threading, os, json
counts, lock = {}, threading.Lock()
class H(socketserver.BaseRequestHandler):
    def handle(self):
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = self.request.recv(4096)
            if not chunk: return
            buf += chunk
        head, _, body = buf.partition(b"\r\n\r\n")
        lines = head.decode().split("\r\n")
        method, path = lines[0].split(" ")[:2]
        length = next((int(l.split(":", 1)[1]) for l in lines[1:] if l.lower().startswith("content-length:")), 0)
        while len(body) < length:
            chunk = self.request.recv(4096)
            if not chunk: break
            body += chunk
        scen = path.strip("/").split("/")[0]
        if method == "GET" and scen == "__count":
            return self.reply(200, counts.get(path.strip("/").split("/")[1], 0))
        with lock:
            counts[scen] = counts.get(scen, 0) + 1
            n = counts[scen]
        if scen.startswith("drop") and n == 1:
            return  # connection closed with no response: the dead keep-alive after serve restarts
        self.reply(int(scen[1:]) if scen in ("s500", "s409") else 200, {"path": "/tmp/x.png"})
    def reply(self, code, obj):
        b = json.dumps(obj).encode()
        self.request.sendall(b"HTTP/1.1 %d X\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % (code, len(b)) + b)
socketserver.ThreadingTCPServer.allow_reuse_address = True
threading.Timer(30, os._exit, [0]).start()
socketserver.ThreadingTCPServer(("127.0.0.1", 47998), H).serve_forever()
