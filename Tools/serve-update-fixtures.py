#!/usr/bin/env python3
"""Loopback-only native Sparkle fixtures; never used by the app."""
import http.server
import pathlib
import sys

feed = pathlib.Path(sys.argv[1]).read_bytes()
directory = pathlib.Path(sys.argv[1]).parent


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        name = self.path.split("?", 1)[0].lstrip("/")
        allowed = {"appcast.xml", "appcast-zh-Hans.xml", "appcast-zh-Hant.xml", "appcast-en.xml"}
        if name in allowed:
            body = (directory / name).read_bytes()
        elif name == "tampered.xml":
            body = feed.replace(b"<title>RadioBar</title>", b"<title>tampered</title>")
        elif name == "tampered-notes.xml":
            body = feed.replace(b"What's New", b"Changed Notes")
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/rss+xml")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
pathlib.Path(sys.argv[2]).write_text(str(server.server_port))
server.serve_forever()
