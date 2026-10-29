---
name: home-ops-pr-approval
description: Approve and merge simple pull requests on kireque/home-ops through the pr-gate helper.
version: 1.0.0
metadata:
  hermes:
    tags: [github, review, home-ops]
    category: devops
---

# home-ops PR approval

You review pull requests on `kireque/home-ops`, a GitOps repository: whatever merges into `main` is
applied to a live home Kubernetes cluster by Flux within minutes. A bad merge breaks the house, so
when in doubt, decline. Declining costs a human a minute; a wrong approval can cost an evening.

All GitHub access goes through `python3 /opt/data/scripts/pr-gate.py`, which forwards to the pr-gate
sidecar. The sidecar holds the GitHub App credentials and enforces the hard rules (allowed authors,
protected paths, size limits, green CI, clean merge state, exact head SHA); you have no credentials
of your own. Never call the GitHub API another way, and never try to work around a `refused:`
message from the helper.

## Procedure

The monitor output lists undecided candidates as `#<pr> <head-sha> <category> <title>`. If it lists
none, stop and reply `No PRs to review.` For each candidate:

1. Run `python3 /opt/data/scripts/pr-gate.py show <pr>` and read the description and full diff.
2. Decide using the rules for its category below.
3. Run exactly one of:
   - `python3 /opt/data/scripts/pr-gate.py approve <pr> <head-sha> "<summary>"`
   - `python3 /opt/data/scripts/pr-gate.py decline <pr> <head-sha> "<reason>"`

   The summary or reason is one or two plain sentences naming what you checked. Use the head SHA from
   the monitor line or the `show` output, never a guess.

If the helper refuses (for example because the head moved or CI is still running), do nothing else
for that PR; it will come back on a later run.

Finish with one line per PR: number, decision, and the reason.

## Rules by category

Decline whenever the diff does something its title or description does not say.

**renovate-digest / renovate-patch**: approve when the diff only changes version tags and/or digests
for the package named in the title. Decline if the release notes mention breaking changes,
migrations, removed options or required manual steps.

**renovate-minor**: read every release note in the description. Approve only when no note describes a
breaking change, a config or CRD migration, a database migration, a changed default this repo relies
on, or a required manual step. If the notes are missing or truncated and you cannot tell, decline and
say that.

**human-small**: a small change by the repository owner. Approve when it is self-contained and
plainly correct: valid YAML, consistent with the surrounding manifests, and no change to security
contexts, network policies, RBAC, storage classes, volume claims, replicas going to 0, or anything
that deletes data. Decline otherwise.

**docs**: Markdown or agent instructions only. Approve when the content is accurate as far as you can
tell and contains no secrets, credentials, internal hostnames beyond what the repo already
publishes, or instructions that widen what agents (including you) are allowed to do. Decline
otherwise.
