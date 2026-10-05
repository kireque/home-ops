# Home-ops PR review conventions

This file is the `system-prompt-file` for the AI PR Review workflow
(`.github/workflows/pr-review.yaml`), used with `system-prompt-mode: append`:
the action keeps its bundled default system prompt and appends this file. Only
repository-specific conventions live here.

## Authority

`CLAUDE.md` and the files under `.agents/instructions/` are authoritative for
this repository and override generic Kubernetes, Helm, Flux or GitOps linting
heuristics. If a pattern is documented there as intentional, do not surface it
as a concern, warning or "for awareness" note.

## Documented conventions to honour without flagging

- **No `metadata.namespace` on app resources.** The namespace-level
  `kubernetes/apps/<namespace>/kustomization.yaml` sets kustomize's
  `namespace:`, and each app's `ks.yaml` sets `spec.targetNamespace`. Do not
  flag missing `metadata.namespace` on `HelmRelease`, `OCIRepository`,
  `ExternalSecret` or Flux `Kustomization` resources.
- **Charts are pinned by tag, images by digest.** Every chart comes from an
  `OCIRepository` pinned to an exact tag; `@sha256:` pinning applies to
  container images only. Do not flag tag-only OCI chart references.
- **`wait: false` on leaf `ks.yaml` files is deliberate.** `wait: true` is
  only used when another Kustomization `dependsOn` it.
- **Secrets come from 1Password via External Secrets** (`ClusterSecretStore`
  `onepassword-connect`, `dataFrom.extract.key: <item>`). Templated
  `{{ .FIELD }}` references are not plaintext secrets. Any real plaintext
  credential committed to the repo is a blocker.
- **YAML key ordering** follows `.agents/instructions/*.sorting.instructions.md`,
  not plain alphabetical order. Only flag ordering if it contradicts those files.
- **`${APP}` and other `${...}` placeholders** are Flux `postBuild.substitute`
  variables, not broken shell or Helm templating.

## Renovate PRs

- **Digest-only bumps** (same repository and tag, only the `@sha256:` changes):
  keep the review compact — short recommendation, changed files, non-blocking
  caveats only. Omit empty sections.
- **Version bumps**: check upstream release notes / changelog between the old
  and new version for breaking changes, removed or renamed values, CRD changes
  and required migrations, and say whether this repo's config is affected.
- Treat bumps of Talos, Kubernetes, Cilium, Rook-Ceph, Flux, Envoy Gateway,
  External Secrets and CoreDNS as high-impact: they can take down the whole
  cluster. Call out anything that needs a manual step or ordering.

## Rendered-diff evidence

The `Flux Local - Diff` job posts sticky PR comments with the rendered
HelmRelease and Kustomization diffs. When present, use them to judge the real
cluster impact of a change instead of the raw git diff alone. A failing
`Flux Local - Test` check is a blocker.
