#!/usr/bin/env python3
"""MD Reader bridge server (Python 3 standard library only).

Usage: python3 md-server.py [file.md]

Serves md-reader.html (found next to this script) on 127.0.0.1 with a random
port and a random access token, then opens it in the default browser.
  GET  /                -> the editor page
  GET  /api/info        -> {"name": ..., "path": ..., "no_file": bool}
  GET  /api/content     -> the file's current text
  POST /api/save        -> writes the request body back to the file
All /api/ calls require ?t=<token>. With no file argument the editor opens
blank and Save falls back to Save As in the browser.
"""
import json
import os
import secrets
import sys
import tempfile
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))
HTML_PATH = os.path.join(HERE, "md-reader.html")
TOKEN = secrets.token_urlsafe(16)
FILEPATH = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # keep the terminal quiet
        pass

    def _token_ok(self, query):
        return parse_qs(query).get("t", [""])[0] == TOKEN

    def _send(self, code, body, content_type="text/plain; charset=utf-8"):
        data = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/":
            try:
                with open(HTML_PATH, "rb") as f:
                    self._send(200, f.read(), "text/html; charset=utf-8")
            except OSError as e:
                self._send(500, "md-reader.html not found next to md-server.py: %s" % e)
            return
        if parsed.path == "/favicon.ico":
            self._send(204, b"")
            return
        if not parsed.path.startswith("/api/"):
            self._send(404, "not found")
            return
        if not self._token_ok(parsed.query):
            self._send(403, "bad or missing token")
            return
        if parsed.path == "/api/info":
            info = {
                "name": os.path.basename(FILEPATH) if FILEPATH else "Untitled.md",
                "path": FILEPATH or "",
                "no_file": FILEPATH is None,
            }
            self._send(200, json.dumps(info), "application/json")
        elif parsed.path == "/api/content":
            if FILEPATH is None:
                self._send(200, "")
                return
            try:
                with open(FILEPATH, "r", encoding="utf-8") as f:
                    self._send(200, f.read())
            except OSError as e:
                self._send(500, "cannot read file: %s" % e)
        else:
            self._send(404, "not found")

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/api/save":
            self._send(404, "not found")
            return
        if not self._token_ok(parsed.query):
            self._send(403, "bad or missing token")
            return
        if FILEPATH is None:
            self._send(400, "no file is open on the server")
            return
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        # Atomic write: temp file in the same directory, then rename.
        directory = os.path.dirname(FILEPATH) or "."
        fd, tmp = tempfile.mkstemp(dir=directory, prefix=".mdreader-", suffix=".tmp")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(body)
            os.replace(tmp, FILEPATH)
        except OSError as e:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            self._send(500, "cannot write file: %s" % e)
            return
        self._send(200, "saved")


def main():
    if FILEPATH and not os.path.isfile(FILEPATH):
        # A not-yet-existing target is fine: start empty, first save creates it.
        open(FILEPATH, "a", encoding="utf-8").close()
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    url = "http://127.0.0.1:%d/?t=%s" % (port, TOKEN)
    target = FILEPATH if FILEPATH else "(new document)"
    print("MD Reader serving %s" % target)
    print("URL: %s" % url)
    print("Close this window / press Ctrl+C to stop the server.")
    sys.stdout.flush()
    try:
        webbrowser.open(url)
    except Exception:
        pass
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
