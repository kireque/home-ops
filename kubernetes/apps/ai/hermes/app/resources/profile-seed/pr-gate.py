#!/usr/bin/env python3
"""Hard gate for Hermes' PR approvals on kireque/home-ops.

Hermes judges whether a change is safe; this script enforces everything that
must not be left to judgement: who opened the PR, which paths it touches, its
size, CI state, mergeability and the exact head SHA that gets approved and
merged.

  pr-gate.py                         list undecided candidates (cron monitor)
  pr-gate.py show <pr>               metadata, release notes and diff to review
  pr-gate.py approve <pr> <sha> <summary>
  pr-gate.py decline <pr> <sha> <reason>
"""

import fnmatch
import json
import re
import sys
import time
import urllib.error
import urllib.request
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
    if pr["user"]["login"] == RENOVATE_LOGIN and pr["head"]["ref"].startswith("renovate/"):
        lines = sum(f["additions"] + f["deletions"] for f in files)
        if lines > RENOVATE_MAX_LINES:
            raise GateError(f"too large for a version bump ({lines} lines)")
        if "!" in pr["title"].split(":", 1)[0]:
            raise GateError("breaking change (! in title)")
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
    failed, so it stays a candidate and approve() retries the merge.
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
    for pr in paginate(f"/repos/{REPO}/pulls?state=open&base={BASE}&sort=created&direction=asc", token):
        try:
            _, _, kind = gate(pr["number"], token)
        except GateError:
            continue
        if not decided(pr["number"], pr["head"]["sha"], token, bot):
            print(f"#{pr['number']} {pr['head']['sha']} {kind} {pr['title']}")


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
    merged = request("PUT", f"/repos/{REPO}/pulls/{number}/merge", token, {
        "sha": sha,
        "merge_method": "squash",
        "commit_title": f"{pr['title']} (#{number})",
    })
    print(f"approved and merged #{number} as {merged['sha']}")


def decline(number, sha, reason, token, bot):
    if decided(number, sha, token, bot):
        raise GateError("already decided for this SHA")
    request("POST", f"/repos/{REPO}/issues/{number}/comments", token, {
        "body": f"Hermes is leaving this one for a human: {reason}\n{MARKER} sha={sha} decision=decline -->",
    })
    print(f"declined #{number}")


def main(argv):
    token, bot = app_token()
    if not argv:
        return scan(token, bot)
    command, number = argv[0], int(argv[1]) if len(argv) > 1 else None
    if command == "show" and len(argv) == 2:
        return show(number, token)
    if command in ("approve", "decline") and len(argv) == 4:
        action = approve if command == "approve" else decline
        return action(number, argv[2], argv[3], token, bot)
    sys.exit(__doc__)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except GateError as err:
        sys.exit(f"refused: {err}")
