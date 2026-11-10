#!/usr/bin/env python3
"""Loopback-only fixture server; port 0 avoids races with concurrent test runs."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        # Request paths only; never dump headers.
        with open(sys.argv[3], 'a', encoding='utf-8') as log:
            log.write((fmt % args) + '\n')


server = ThreadingHTTPServer(('127.0.0.1', 0), partial(Handler, directory=sys.argv[1]))
Path(sys.argv[2]).write_text(str(server.server_port))
server.serve_forever()
