# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a GitOps-managed home Kubernetes cluster using Talos Linux, Flux CD, and Helm. All cluster state is declared in this repository and reconciled by Flux.

## Development Tools

Tools are managed via `mise`. Run `mise install` to install all required tools. Key tools:
- `just` — task runner (run `just` or `just -l` to list all tasks)
- `flux` — GitOps reconciliation
- `kubectl` / `k9s` — cluster interaction
- `talosctl` — Talos OS management
- `sops` / `age` — secret encryption
- `minijinja-cli` — Jinja2 template rendering
- `helmfile` — Helm chart management during bootstrap

Environment variables (`KUBECONFIG`, `TALOSCONFIG`, `MINIJINJA_CONFIG_FILE`) are auto-set by `.mise.toml` when `mise` is active.

## Common Commands

```bash
just -l                         # List all available tasks
just kube:sync-ks <ns> <name>   # Force Flux to reconcile a Kustomization
just kube:sync-hr <ns> <name>   # Force Flux to reconcile a HelmRelease
just kube:apply-ks <ns> <ks>    # Apply a Flux Kustomization locally
just kube:view-secret <ns> <name> # Decrypt and view a secret
just kube:browse-pvc            # Interactive PVC browser
just talos:apply-node <node>    # Apply Talos config to a node (enigma/delta/felix)
just talos:render-config <node> # Render Talos config from Jinja2 templates
```

### Local manifest validation (mirrors CI)

```bash
flux-local test \
  --all-namespaces \
  --enable-helm \
  --path kubernetes/flux/cluster \
  --verbose
```

This is what the `Flux Local` CI workflow runs on every PR touching `kubernetes/**`. Run it locally before pushing to catch HelmRelease and Kustomization errors.

## Cluster Architecture

### GitOps Flow

Flux watches this repo and reconciles the cluster state:
1. Root entry point: `kubernetes/flux/cluster/ks.yaml`
2. Each namespace has its own Kustomization listing apps
3. Each app has a `ks.yaml` (Flux Kustomization) pointing to `./app/`
4. The `./app/` directory contains the actual K8s resources

### Application Structure

Every application under `kubernetes/apps/{namespace}/{app}/` follows this pattern:

```
{app}/
├── ks.yaml                 # Flux Kustomization (namespace-level entry point)
└── app/
    ├── kustomization.yaml  # Lists all resources in this directory
    ├── ocirepository.yaml  # Helm chart source (OCI registry)
    ├── helmrelease.yaml    # Helm release configuration
    └── externalsecret.yaml # Optional: secret references from 1Password
```

The `ks.yaml` at the app level uses `postBuild.substitute` with `APP: {appname}` so that shared components (like `volsync`) can use `${APP}` as a variable.

### Secret Management

All secrets come from **1Password** via External Secrets Operator:
- `ClusterSecretStore` named `onepassword` is the root store
- `ExternalSecret` resources reference secrets as `op://kubernetes/{item}/{field}`
- Bootstrap secrets (before External Secrets is running) use `op inject` at apply time
- Never commit plaintext secrets

### Storage

- **Rook-Ceph**: Distributed block/object storage for stateful apps
- **OpenEBS**: Hostpath volumes for single-node workloads
- **Volsync**: PVC backup/replication — apps opt in via `components: [../../../../components/volsync]` in `ks.yaml`

### Networking

- **Cilium**: CNI with eBPF, kube-proxy replacement
- **Envoy Gateway**: Kubernetes Gateway API implementation for external access
- **Cloudflared**: Tunnel for exposing services externally without open ports
- **External-DNS**: Automatically creates Cloudflare DNS records

## YAML Conventions

Sorting rules are defined in `.claude/instructions/sorting.instructions.md` and are automatically applied by Claude Code. That file is the authoritative source — consult it when in doubt.

### Helm chart sources

All charts use `OCIRepository` (not `HelmRepository`). Chart versions are pinned to exact tags. Container images are pinned to digest hashes where possible.

## Talos Nodes

The cluster has 3 nodes (all controller nodes): `enigma`, `delta`, `felix`

Talos configs are generated from Jinja2 templates in `talos/` using `minijinja-cli` + `op inject`.
