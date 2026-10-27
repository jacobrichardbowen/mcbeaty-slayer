"""A stand-in internet on this machine, for testing how friends join a host.

- A STUN server that tells each game its address "on the internet".
- A message board that works like ntfy.sh (POST a note to a topic, poll it
  as JSON lines).
- The host's home router: friends reach the host through its public port,
  and, like most home routers, it drops a friend's packets until the host
  has sent something toward that friend (which the game does after reading
  the friend's note). Each friend gets a public port of their own on it.
- Lag and packet loss on everything passing through the router.

Run it, then point the games at it (see tests/net_soak_test.gd):
    python3 tests/fake_internet.py --seconds 90
It prints what passed through when it stops.
"""

import argparse
import heapq
import itertools
import json
import os
import random
import select
import socket
import string
import struct
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

MAGIC = 0x2112A442
LOCAL = "127.0.0.1"

ap = argparse.ArgumentParser()
ap.add_argument("--stun-port", type=int, default=34780)
ap.add_argument("--board-port", type=int, default=34781)
ap.add_argument("--router-port", type=int, default=34790, help="the host's public port")
ap.add_argument("--host-port", type=int, default=24565, help="the port the host's game uses")
ap.add_argument("--delay", type=float, default=40.0, help="ms each way")
ap.add_argument("--jitter", type=float, default=10.0, help="ms")
ap.add_argument("--loss", type=float, default=0.02)
ap.add_argument("--no-board", action="store_true", help="the message board is down")
ap.add_argument("--seconds", type=float, default=90.0)
args = ap.parse_args()

stats = dict(stun=0, notes=0, polls=0, forwarded=0, lost=0, turned_away=0, knocks=0)


# --- Message board ------------------------------------------------------------------------

board = {}  # topic -> [message]
board_lock = threading.Lock()


class Board(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        topic = self.path.strip("/")
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        msg = {"id": "".join(random.choices(string.ascii_letters + string.digits, k=12)), "time": int(time.time()),
               "expires": int(time.time()) + 43200, "event": "message", "topic": topic, "message": body}
        with board_lock:
            board.setdefault(topic, []).append(msg)
            stats["notes"] += 1
        self._reply(json.dumps(msg) + "\n")

    def do_GET(self):
        url = urlparse(self.path)
        parts = url.path.strip("/").split("/")
        if len(parts) != 2 or parts[1] != "json":
            self.send_error(404)
            return
        since = parse_qs(url.query).get("since", ["all"])[0]
        with board_lock:
            msgs = list(board.get(parts[0], []))
            stats["polls"] += 1
        if since != "all":
            ids = [m["id"] for m in msgs]
            if since in ids:
                msgs = msgs[ids.index(since) + 1:]
            elif since[-1:] in "smh" and since[:-1].isdigit():
                age = int(since[:-1]) * {"s": 1, "m": 60, "h": 3600}[since[-1]]
                msgs = [m for m in msgs if m["time"] >= time.time() - age]
            elif since.isdigit():
                msgs = [m for m in msgs if m["time"] >= int(since)]
        self._reply("".join(json.dumps(m) + "\n" for m in msgs))

    def _reply(self, text):
        data = text.encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if not args.no_board:
    server = ThreadingHTTPServer((LOCAL, args.board_port), Board)
    threading.Thread(target=server.serve_forever, daemon=True).start()


# --- STUN and the host's router ---------------------------------------------------------------

def udp(port=0):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind((LOCAL, port))
    return s


stun = udp(args.stun_port)
public = udp(args.router_port)  # the host's public port
host = (LOCAL, args.host_port)
friend_port = {}  # a friend's own address -> their public socket
friend_of = {}  # a public socket -> that friend's own address
opened = set()  # public sockets the host has sent toward
queue, order = [], itertools.count()


def public_socket(friend):
    s = friend_port.get(friend)
    if s is None:
        s = udp()
        friend_port[friend], friend_of[s] = s, friend
    return s


def later(sock, data, to):
    if random.random() < args.loss:
        stats["lost"] += 1
        return
    due = time.time() + (args.delay + random.uniform(-args.jitter, args.jitter)) / 1000.0
    heapq.heappush(queue, (due, next(order), sock, data, to))


def stun_answer(data, sender):
    if len(data) < 20 or struct.unpack(">HHI", data[:8]) != (1, 0, MAGIC):
        return
    stats["stun"] += 1
    port = args.router_port if sender == host else public_socket(sender).getsockname()[1]
    ip = struct.unpack(">I", socket.inet_aton(LOCAL))[0]
    software = b"fake internet"  # 13 bytes: padded, so readers must skip it properly
    attrs = struct.pack(">HH", 0x8022, len(software)) + software + b"\0" * (-len(software) % 4)
    attrs += struct.pack(">HHBBHI", 0x0020, 8, 0, 1, port ^ (MAGIC >> 16), ip ^ MAGIC)
    stun.sendto(struct.pack(">HHI", 0x0101, len(attrs), MAGIC) + data[8:20] + attrs, sender)


stop_at = time.time() + args.seconds
while time.time() < stop_at:
    wait = min(max(0.0, queue[0][0] - time.time()), 0.005) if queue else 0.005
    ready, _, _ = select.select([stun, public] + list(friend_of), [], [], wait)
    for s in ready:
        data, sender = s.recvfrom(65536)
        if s is stun:
            stun_answer(data, sender)
        elif s is public:
            # A friend knocking at the host's public port: let in only if the host sent toward them.
            pub = public_socket(sender)
            if pub in opened:
                later(pub, data, host)
            else:
                stats["turned_away"] += 1
        elif sender == host:
            # The host sending to a friend's public address: opens the way back, then goes on.
            opened.add(s)
            if len(data) == 1:
                stats["knocks"] += 1
            later(public, data, friend_of[s])
    now = time.time()
    while queue and queue[0][0] <= now:
        _, _, s, data, to = heapq.heappop(queue)
        s.sendto(data, to)
        stats["forwarded"] += 1

print("fake internet:", ", ".join("%s %d" % kv for kv in stats.items()))
os._exit(0)
