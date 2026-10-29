#!/usr/bin/env python3
"""Hard gate for Hermes' PR approvals on kireque/home-ops.

Hermes judges whether a change is safe; this server enforces everything that
must not be left to judgement: who opened the PR, which paths it touches, its
size, CI state, mergeability and the exact head SHA that gets approved and
merged.

It runs in its own container so the GitHub App key never reaches the agent's
shell. It listens on loopback only; the agent reaches it through pr-gate.py:

  GET  /candidates   undecided candidates (cron monitor)
  GET  /show/<pr>    metadata, release notes and diff to review
  POST /approve      {"pr": <pr>, "sha": <sha>, "summary": <text>}
  POST /decline      {"pr": <pr>, "sha": <sha>, "reason": <text>}
"""

import contextlib
import fnmatch
import io
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import jwt

REPO = "kireque/home-ops"
BASE = "main"
API = "https://api.github.com"
SECRET_DIR = Path("/var/run/secrets/hermes-github")
RENOVATE_LOGIN = "kireque-bot[bot]"
HUMAN_LOGINS = {"kireque"}
MARKER = "<!-- hermes-pr-gate"
HOLD_LABELS = {"do-not-merge", "hermes/hold", "hold"}
LISTEN = ("127.0.0.1", int(os.environ.get("PR_GATE_PORT", "8765")))
MAX_BODY = 16384

# Never approved, whoever opened the PR: cluster bootstrap and control plane,
# CI and Renovate policy, secrets, and this gate itself
DENY_PATHS = [
    ".github/*",
    ".renovate/*",
    ".renovaterc*",
    "bootstrap/*",
    "talos/*",
    "kubernetes/flux/*",
    "kubernetes/components/*",
    "kubernetes/apps/ai/hermes/*",
    "kubernetes/apps/flux-system/*",
    "kubernetes/apps/kube-system/cilium/*",
    "kubernetes/apps/rook-ceph/*",
    "kubernetes/apps/external-secrets/*",
    "*.sops.*",
    "*crds*",
]
DOCS_PATHS = ["*.md", ".agents/*"]
HUMAN_MAX_FILES = 4
HUMAN_MAX_LINES = 40
DOCS_MAX_LINES = 300
# Version bumps are a few lines; anything bigger needs a human
RENOVATE_MAX_LINES = 100
# show prints at most this much; larger diffs are refused, never reviewed partially
MAX_DIFF_CHARS = 20000
SECRET_PATTERN = re.compile(r"(?im)^\+.*\b(kind:\s*secret|password|token|private[_-]?key)\b")
GOOD_CONCLUSIONS = {"success", "skipped", "neutral"}


class GateError(Exception):
    pass


def request(method, path, token, body=None, accept="application/vnd.github+json"):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        path if path.startswith("http") else API + path,
        data=data,
        method=method,
        headers={
            "Accept": accept,
            "Authorization": f"Bearer {token}",
            "User-Agent": "hermes-pr-gate",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as err:
        raise GateError(f"{method} {path}: HTTP {err.code} {err.read().decode()[:300]}") from None
    if accept != "application/vnd.github+json":
        return raw.decode()
    return json.loads(raw) if raw else None


def paginate(path, token):
    items, page = [], 1
    while True:
        sep = "&" if "?" in path else "?"
        chunk = request("GET", f"{path}{sep}per_page=100&page={page}", token)
        chunk = chunk.get("check_runs", []) if isinstance(chunk, dict) else chunk
        items.extend(chunk)
        if len(chunk) < 100:
            return items
        page += 1


def app_token():
    app_id = (SECRET_DIR / "app-id").read_text().strip()
    key = (SECRET_DIR / "private-key").read_text()
    now = int(time.time())
    app_jwt = jwt.encode({"iat": now - 60, "exp": now + 540, "iss": app_id}, key, algorithm="RS256")
    app = request("GET", "/app", app_jwt)
    installation = request("GET", f"/repos/{REPO}/installation", app_jwt)
    token = request("POST", f"/app/installations/{installation['id']}/access_tokens", app_jwt)["token"]
    return token, f"{app['slug']}[bot]"


def matches(path, patterns):
    return any(fnmatch.fnmatch(path, p) for p in patterns)


def category(pr, files):
    labels = {label["name"] for label in pr["labels"]}
    paths = [f["filename"] for f in files]
    if "!" in pr["title"].split(":", 1)[0]:
        raise GateError("breaking change (! in title)")
    if pr["user"]["login"] == RENOVATE_LOGIN and pr["head"]["ref"].startswith("renovate/"):
        lines = sum(f["additions"] + f["deletions"] for f in files)
        if lines > RENOVATE_MAX_LINES:
            raise GateError(f"too large for a version bump ({lines} lines)")
        if "Automerge**: Enabled" in (pr["body"] or ""):
            raise GateError("Renovate automerges this itself")
        for update in ("digest", "patch", "minor"):
            if f"type/{update}" in labels:
                return f"renovate-{update}"
        raise GateError(f"update type not digest/patch/minor: {sorted(labels)}")
    if pr["user"]["login"] in HUMAN_LOGINS:
        lines = sum(f["additions"] + f["deletions"] for f in files)
        if all(matches(p, DOCS_PATHS) for p in paths):
            if lines > DOCS_MAX_LINES:
                raise GateError(f"docs change too large ({lines} lines)")
            return "docs"
        if len(files) > HUMAN_MAX_FILES or lines > HUMAN_MAX_LINES:
            raise GateError(f"too large ({len(files)} files, {lines} lines)")
        if any(f["status"] not in ("added", "modified") for f in files):
            raise GateError("removes or renames files")
        if any(SECRET_PATTERN.search(f.get("patch", "")) for f in files):
            raise GateError("diff mentions secrets")
        return "human-small"
    raise GateError(f"author {pr['user']['login']} not allowed")


def ci_green(sha, token):
    runs = paginate(f"/repos/{REPO}/commits/{sha}/check-runs", token)
    if not runs:
        raise GateError("no CI checks yet")
    pending = [r["name"] for r in runs if r["status"] != "completed"]
    if pending:
        raise GateError(f"CI still running: {', '.join(sorted(pending))}")
    failed = [r["name"] for r in runs if r["conclusion"] not in GOOD_CONCLUSIONS]
    if failed:
        raise GateError(f"CI not green: {', '.join(sorted(failed))}")
    status = request("GET", f"/repos/{REPO}/commits/{sha}/status", token)
    if status["statuses"] and status["state"] != "success":
        raise GateError(f"commit status {status['state']}")


def approved(number, sha, token, bot):
    return any(
        review["user"]["login"] == bot and review["commit_id"] == sha and review["state"] == "APPROVED"
        for review in paginate(f"/repos/{REPO}/pulls/{number}/reviews", token)
    )


def decided(number, sha, token, bot):
    """Hermes already declined this exact head SHA.

    An approval alone is not final: an open PR carrying one means the merge
    failed, and scan() retries it.
    """
    for comment in paginate(f"/repos/{REPO}/issues/{number}/comments", token):
        if comment["user"]["login"] == bot and f"{MARKER} sha={sha}" in comment["body"]:
            return True
    return False


def gate(number, token, sha=None, check_ci=True):
    """Return (pr, files, category) or raise GateError with the reason."""
    pr = request("GET", f"/repos/{REPO}/pulls/{number}", token)
    if pr["state"] != "open" or pr["draft"]:
        raise GateError("not an open, ready PR")
    if pr["base"]["ref"] != BASE or pr["head"]["repo"]["full_name"] != REPO:
        raise GateError("not a same-repo PR into main")
    if sha and pr["head"]["sha"] != sha:
        raise GateError(f"head moved to {pr['head']['sha']}; review again")
    held = HOLD_LABELS & {label["name"] for label in pr["labels"]}
    if held:
        raise GateError(f"held by label {sorted(held)}")
    files = paginate(f"/repos/{REPO}/pulls/{number}/files", token)
    denied = [f["filename"] for f in files if matches(f["filename"], DENY_PATHS)]
    denied += [f["previous_filename"] for f in files if matches(f.get("previous_filename", ""), DENY_PATHS)]
    if denied:
        raise GateError(f"touches protected paths: {', '.join(denied)}")
    kind = category(pr, files)
    if check_ci:
        ci_green(pr["head"]["sha"], token)
        if pr["mergeable_state"] != "clean":
            raise GateError(f"mergeable_state is {pr['mergeable_state']}")
    return pr, files, kind


def scan(token, bot):
    # Output must be byte-stable between ticks: the cron monitor only wakes the agent on change
    lines = []
    for pr in paginate(f"/repos/{REPO}/pulls?state=open&base={BASE}&sort=created&direction=asc", token):
        number = pr["number"]
        try:
            pr, _, kind = gate(number, token)
        except GateError:
            continue
        sha = pr["head"]["sha"]
        if decided(number, sha, token, bot):
            continue
        if approved(number, sha, token, bot):
            # Hermes already approved this exact head and the gate still passes, so
            # retry the merge here: the candidate line would not change and would
            # never wake the agent again. Bounded by the cron schedule.
            try:
                merge(pr, sha, token)
            except GateError as err:
                print(f"merge retry for #{number} failed: {err}", file=sys.__stderr__, flush=True)
            continue
        lines.append(f"#{number} {sha} {kind} {pr['title']}")
    if lines:
        # Changes every 6h, so candidates left undecided by a failed agent run are retried
        hour = time.gmtime().tm_hour // 6 * 6
        print(f"retry window: {time.strftime('%Y-%m-%d', time.gmtime())}T{hour:02d}Z")
        print("\n".join(lines))


def full_diff(pr, token):
    """Diff of exactly pr's head SHA, refused when show could not print all of it."""
    diff = request(
        "GET",
        f"/repos/{REPO}/compare/{pr['base']['sha']}...{pr['head']['sha']}",
        token,
        accept="application/vnd.github.diff",
    )
    if len(diff) > MAX_DIFF_CHARS:
        raise GateError(f"diff too large to review in full ({len(diff)} chars)")
    return diff


def show(number, token):
    pr, files, kind = gate(number, token, check_ci=False)
    diff = full_diff(pr, token)
    print(f"PR #{number}: {pr['title']}")
    print(f"category: {kind}  author: {pr['user']['login']}  head: {pr['head']['sha']}")
    print(f"labels: {', '.join(label['name'] for label in pr['labels'])}\n")
    print("## Description\n" + (pr["body"] or "(none)")[:12000] + "\n")
    print("## Diff")
    print(diff)


def merge(pr, sha, token):
    merged = request("PUT", f"/repos/{REPO}/pulls/{pr['number']}/merge", token, {
        "sha": sha,
        "merge_method": "squash",
        "commit_title": f"{pr['title']} (#{pr['number']})",
    })
    return merged["sha"]


def approve(number, sha, summary, token, bot):
    pr, _, kind = gate(number, token, sha=sha)
    full_diff(pr, token)
    if decided(number, sha, token, bot):
        raise GateError("already declined for this SHA")
    if not approved(number, sha, token, bot):
        request("POST", f"/repos/{REPO}/pulls/{number}/reviews", token, {
            "commit_id": sha,
            "event": "APPROVE",
            "body": f"{summary}\n\n_Approved by Hermes ({kind})._\n{MARKER} sha={sha} decision=approve -->",
        })
    print(f"approved and merged #{number} as {merge(pr, sha, token)}")


def decline(number, sha, reason, token, bot):
    if decided(number, sha, token, bot):
        raise GateError("already decided for this SHA")
    request("POST", f"/repos/{REPO}/issues/{number}/comments", token, {
        "body": f"Hermes is leaving this one for a human: {reason}\n{MARKER} sha={sha} decision=decline -->",
    })
    print(f"declined #{number}")


class Handler(BaseHTTPRequestHandler):
    # One request at a time: the handlers print to a shared redirected stdout,
    # and serialising also keeps approve/decline from racing each other
    lock = threading.Lock()

    def do_GET(self):
        parts = self.path.strip("/").split("/")
        if parts == ["healthz"]:
            return self.reply(200, "ok\n")
        if parts == ["candidates"]:
            return self.run(lambda token, bot: scan(token, bot))
        if len(parts) == 2 and parts[0] == "show" and parts[1].isdigit():
            return self.run(lambda token, bot: show(int(parts[1]), token))
        self.reply(404, "unknown request\n")

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY:
            return self.reply(413, "request too large\n")
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
            number, sha = int(body["pr"]), str(body["sha"])
        except (ValueError, KeyError, TypeError):
            return self.reply(400, "expected JSON with pr and sha\n")
        if self.path == "/approve" and isinstance(body.get("summary"), str):
            return self.run(lambda token, bot: approve(number, sha, body["summary"], token, bot))
        if self.path == "/decline" and isinstance(body.get("reason"), str):
            return self.run(lambda token, bot: decline(number, sha, body["reason"], token, bot))
        self.reply(404, "unknown request\n")

    def run(self, action):
        out = io.StringIO()
        with self.lock:
            try:
                with contextlib.redirect_stdout(out):
                    action(*app_token())
            except GateError as err:
                return self.reply(409, f"refused: {err}\n")
            except Exception as err:  # noqa: BLE001 - report, keep serving
                return self.reply(500, f"error: {type(err).__name__}: {err}\n")
        self.reply(200, out.getvalue())

    def reply(self, code, text):
        data = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        # stderr, never stdout: another request may be capturing stdout right now
        print(f"{self.address_string()} {fmt % args}", file=sys.__stderr__, flush=True)


if __name__ == "__main__":
    ThreadingHTTPServer(LISTEN, Handler).serve_forever()
