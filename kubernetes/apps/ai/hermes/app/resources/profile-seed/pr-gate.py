#!/usr/bin/env python3
"""Hermes' side of the PR approval gate.

The GitHub App key and every hard rule live in the pr-gate sidecar; this only
forwards requests to it over loopback.

  pr-gate.py                         list undecided candidates (cron monitor)
  pr-gate.py show <pr>               metadata, release notes and diff to review
  pr-gate.py approve <pr> <sha> <summary>
  pr-gate.py decline <pr> <sha> <reason>
"""

import json
import os
import sys
import urllib.error
import urllib.request

URL = f"http://127.0.0.1:{os.environ.get('PR_GATE_PORT', '8765')}"


def call(path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(URL + path, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            sys.stdout.write(resp.read().decode())
    except urllib.error.HTTPError as err:
        sys.exit(err.read().decode().rstrip() or f"HTTP {err.code}")
    except urllib.error.URLError as err:
        sys.exit(f"pr-gate sidecar unreachable: {err.reason}")


def main(argv):
    if not argv:
        return call("/candidates")
    if argv[0] == "show" and len(argv) == 2 and argv[1].isdigit():
        return call(f"/show/{argv[1]}")
    if argv[0] in ("approve", "decline") and len(argv) == 4 and argv[1].isdigit():
        field = "summary" if argv[0] == "approve" else "reason"
        return call(f"/{argv[0]}", {"pr": int(argv[1]), "sha": argv[2], field: argv[3]})
    sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
