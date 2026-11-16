#!/usr/bin/env python3
"""A QNTX node on the runner, for the island to be tested against.

Run from a teranos/QNTX checkout that was built (ats.wasm, the storage
library, and bin/qntx with rustsqlite,qntxwasm), with a home of its own:

    python3 ci-node.py <qntx checkout> <home> <port>

It writes am.toml from the checkout's own am.example.toml with sign-in on,
starts the node once so it makes its store, and stops it. It writes a ROOT
User and a session for that User into the store, as a login would, and
starts the node again, which reads its Users when it starts. What a press
or a hand-over presents is that session, as the app's page does
(QNTX-Web ts/client/session.ts): the node takes a phone's token from a
logged-in person alone (teranos/QNTX server/phones.go, theHumanThemselves).

It prints NODE=<url> and SESSION=<token> for the steps after it.
"""

import hashlib
import json
import os
import secrets
import signal
import sqlite3
import subprocess
import sys
import time
import urllib.request

ROOT = "did:key:z6MkExampleExampleExampleExampleExampleExample"


def configure(checkout, home, port):
    lines = open(os.path.join(checkout, "am.example.toml")).read().split("\n")

    def set_line(old, new, after=0):
        at = lines.index(old, after)
        lines[at] = new
        return at

    set_line('path = "qntx.db"', 'path = "%s"' % os.path.join(home, ".qntx", "qntx.db"))
    set_line("port = 8770", "port = %d" % port)
    at = set_line("enabled = false", "enabled = true", lines.index("[auth]"))
    # The node runs on nothing it was not told, and the example does not say it.
    lines.insert(at + 1, "session_expiry_hours = 24")
    set_line('# root_identities = ["%s"]' % ROOT, 'root_identities = ["%s"]' % ROOT)
    os.makedirs(os.path.join(home, ".qntx"), exist_ok=True)
    open(os.path.join(home, ".qntx", "am.toml"), "w").write("\n".join(lines))


def start(checkout, home, port, log):
    env = dict(os.environ, HOME=home)
    node = subprocess.Popen([os.path.join(checkout, "bin", "qntx"), "server"], env=env,
                            stdout=open(log, "a"), stderr=subprocess.STDOUT)
    for _ in range(90):
        if node.poll() is not None:
            raise SystemExit("the node stopped as it started; its log is %s:\n%s" % (log, open(log).read()[-4000:]))
        try:
            if urllib.request.urlopen("http://127.0.0.1:%d/health" % port, timeout=2).status == 200:
                return node
        except OSError:
            pass
        time.sleep(2)
    node.kill()
    raise SystemExit("the node did not answer its health in three minutes; its log is %s" % log)


def stop(node):
    node.send_signal(signal.SIGINT)
    try:
        node.wait(timeout=60)
    except subprocess.TimeoutExpired:
        node.kill()
        node.wait()


def logged_in(home):
    store = sqlite3.connect(os.path.join(home, ".qntx", "qntx.db"))
    user = {
        "id": "root", "display_name": "ci", "email_addresses": [], "phone_numbers": [],
        "level": "ROOT", "created_by": "", "disabled_by": "",
        "keys": [{"did": ROOT, "origin": "ci"}], "accounts": [], "created_at": int(time.time()),
    }
    session = secrets.token_hex(32)
    with store:
        store.execute("INSERT INTO users(id, record) VALUES(?, ?)", ("root", json.dumps(user)))
        store.execute(
            "INSERT INTO auth_sessions(hash, identity, user_id, display_name, namespace, expires_at) VALUES(?,?,?,?,?,?)",
            (hashlib.sha256(session.encode()).hexdigest(), ROOT, "root", "ci", "default", int(time.time()) + 3600))
    store.close()
    return session


def main(checkout, home, port):
    port = int(port)
    log = os.path.join(home, "node.log")
    configure(checkout, home, port)
    stop(start(checkout, home, port, log))
    session = logged_in(home)
    node = start(checkout, home, port, log)
    print("NODE=http://127.0.0.1:%d" % port)
    print("SESSION=%s" % session)
    print("PID=%d" % node.pid)


if __name__ == "__main__":
    main(*sys.argv[1:4])
