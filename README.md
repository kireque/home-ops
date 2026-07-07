<div align="center">

### 🚀 My Home Operations Repository 🚧

_... managed with Flux, Renovate, and GitHub Actions_ 🤖

</div>

<div align="center">

[![Talos](https://kromgo.econline.nl/talos_version)](https://talos.dev)&nbsp;&nbsp;
[![Kubernetes](https://kromgo.econline.nl/kubernetes_version)](https://kubernetes.io)&nbsp;&nbsp;
[![Flux](https://kromgo.econline.nl/flux_version)](https://fluxcd.io)&nbsp;&nbsp;
[![Renovate](https://img.shields.io/github/actions/workflow/status/kireque/home-ops/renovate.yaml?branch=main&label&logo=renovate&color=blue)](https://github.com/kireque/home-ops/actions/workflows/renovate.yaml)

</div>

<div align="center">

[![Age](https://kromgo.econline.nl/cluster_age_days)](https://github.com/home-operations/kromgo)&nbsp;&nbsp;
[![Uptime](https://kromgo.econline.nl/cluster_uptime_days)](https://github.com/home-operations/kromgo)&nbsp;&nbsp;
[![Nodes](https://kromgo.econline.nl/cluster_node_count)](https://github.com/home-operations/kromgo)&nbsp;&nbsp;
[![Pods](https://kromgo.econline.nl/cluster_pod_count)](https://github.com/home-operations/kromgo)&nbsp;&nbsp;
[![CPU](https://kromgo.econline.nl/cluster_cpu_usage)](https://github.com/home-operations/kromgo)&nbsp;&nbsp;
[![Memory](https://kromgo.econline.nl/cluster_memory_usage)](https://github.com/home-operations/kromgo)&nbsp;&nbsp;
[![Alerts](https://kromgo.econline.nl/cluster_alert_count)](https://github.com/home-operations/kromgo)

</div>

---

## 💡 Overview

This is a mono repository for my home infrastructure and Kubernetes cluster. I try to adhere to Infrastructure as Code (IaC) and GitOps practices using tools like [Kubernetes](https://kubernetes.io/), [Flux](https://github.com/fluxcd/flux2), [Renovate](https://github.com/renovatebot/renovate), and [GitHub Actions](https://github.com/features/actions).

This repository started from [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template) and has since diverged into my own setup — check out that template (or [onedr0p/home-ops](https://github.com/onedr0p/home-ops) and [bjw-s-labs/home-ops](https://github.com/bjw-s-labs/home-ops) for further inspiration) if you want to build something similar.

---

## 🌱 Kubernetes

My cluster is a 3-node [Talos Linux](https://www.talos.dev) cluster, currently on Kubernetes `v1.36.2`. All three nodes are control-plane nodes and also run workloads — there are no dedicated workers. Compute, storage and networking are all hyper-converged on the same three boxes.

### Core Components

- **GitOps**: [flux-operator](https://github.com/controlplaneio-fluxcd/flux-operator) manages the [Flux](https://github.com/fluxcd/flux2) installation itself (via a `FluxInstance` resource) rather than bootstrapping Flux directly, which lets Flux's own version be reconciled and upgraded like any other component.
- **Networking**: [Cilium](https://github.com/cilium/cilium) provides eBPF-based CNI with kube-proxy replacement and [Multus](https://github.com/k8snetworkplumbingwg/multus-cni) enables secondary network interfaces for pods that need them (e.g. Frigate/Zigbee2MQTT). [Envoy Gateway](https://github.com/envoyproxy/gateway) implements the Kubernetes Gateway API for both internal and external HTTP routing.
- **Ingress & DNS**: Two `HTTPRoute` classes — `internal` and `external` — are synced by two separate [external-dns](https://github.com/kubernetes-sigs/external-dns) instances: one to a local UniFi controller via the [UniFi webhook provider](https://github.com/kashalls/external-dns-unifi-webhook), the other to Cloudflare (DNS-only, unproxied records). External access is served through [Towonel](https://towonel.dev) via TLS-passthrough into Envoy Gateway; [Cloudflare Tunnel](https://github.com/cloudflare/cloudflared) is still deployed but idle, kept only as a fast rollback path.
- **Secrets**: [external-secrets](https://github.com/external-secrets/external-secrets) with an [1Password Connect](https://github.com/1Password/connect) `ClusterSecretStore` injects secrets from 1Password at reconcile time — nothing sensitive is committed in plaintext.
- **Storage & Data Protection**: [Rook-Ceph](https://github.com/rook/rook) provides replicated block/filesystem storage across all three nodes, [OpenEBS](https://github.com/openebs/openebs) hostpath handles single-node local volumes, and [Volsync](https://github.com/backube/volsync) plus a custom backup/restore component called [kopiur](./kubernetes/components/kopiur) handle PVC backup and restore.
- **Certificates**: [cert-manager](https://github.com/cert-manager/cert-manager) issues and renews TLS certificates automatically.
- **Image mirroring**: [Spegel](https://github.com/spegel-org/spegel) runs a stateless, cluster-local OCI image mirror so nodes don't all hit the same upstream registry.
- **CI/CD**: [actions-runner-controller](https://github.com/actions/actions-runner-controller) runs self-hosted GitHub Actions runners inside the cluster.
- **Upgrades**: [tuppr](https://github.com/home-operations/tuppr) automates Talos and Kubernetes version upgrades.
- **GPU**: an Intel iGPU on every node is exposed cluster-wide via Kubernetes [Dynamic Resource Allocation](https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/) (`intel-gpu-resource-driver`), used for Quick Sync hardware transcoding (Jellyfin/Plex) and local LLM inference (Ollama).

### GitOps

[Flux](https://github.com/fluxcd/flux2) watches this Git repository and reconciles the cluster to match its declared state. The root `Kustomization` ([`kubernetes/flux/cluster/ks.yaml`](./kubernetes/flux/cluster/ks.yaml)) points at `kubernetes/apps`, which Flux recursively scans for per-app `ks.yaml` files. Each of those creates a namespaced `Kustomization` pointing at that app's `./app` directory, which typically contains an `OCIRepository`, a `HelmRelease`, and any supporting resources (`ExternalSecret`, etc).

[Renovate](https://github.com/renovatebot/renovate) watches the entire repository for dependency updates (Helm charts, container images, GitHub Actions, Talos/Kubernetes versions) and opens PRs automatically. `flux-local` runs in CI on every PR touching `kubernetes/**` to validate `Kustomization`/`HelmRelease` builds before merge.

### Directories

```sh
📁 kubernetes
├── 📁 apps       # applications, grouped by namespace
├── 📁 components # re-usable kustomize components (volsync/kopiur backups, alerting, nfs-scaler)
└── 📁 flux       # Flux system + root Kustomization
```

### Namespaces

| Namespace | Contents |
|---|---|
| `flux-system` | flux-operator, FluxInstance, konflate |
| `kube-system` | Cilium, CoreDNS, Multus, metrics-server, descheduler, spegel, reloader, k8tz, snapshot-controller, intel-gpu-resource-driver, drm-exporter |
| `cert-manager` | cert-manager |
| `external-secrets` | external-secrets, onepassword-connect |
| `rook-ceph` | rook-ceph operator, rook-ceph-cluster, ceph-csi-drivers |
| `openebs-system` | OpenEBS (hostpath local storage) |
| `kopiur-system` | kopiur, kopiur-repository (backup/restore) |
| `network` | Cilium ingress bits, Envoy Gateway, cloudflare-tunnel, cloudflare-dns, unifi-dns, towonel-agent, echo |
| `observability` | kube-prometheus-stack, Grafana, VictoriaLogs, fluent-bit, Gatus, kromgo, Headlamp, KEDA, silence-operator, unpoller, smartctl-exporter, blackbox-exporter |
| `home-automation` | Home Assistant, Zigbee2MQTT, ESPHome, Frigate, Mosquitto |
| `media` | Jellyfin, Plex, seerr, Tautulli, watchstate, agregarr |
| `downloads` | sabnzbd, Prowlarr, Sonarr, Radarr, Bazarr, Recyclarr, chaski |
| `llm-system` | Ollama, Open WebUI, OpenClaw, ToolHive operator + MCP servers (context7, flux, home-assistant, kubectl) |
| `actions-runner-system` | actions-runner-controller + runners |
| `system-upgrade` | tuppr |

---

## ⚙️ Hardware

### Compute

**Intel Core i5-10210U (4c/8t) × 3** · 64 GB RAM each · Talos / Kubernetes

| Node | CPU | RAM | Ceph OSD (NVMe) | System disk (SATA SSD) |
|---|---|---|---|---|
| `enigma` | Intel i5-10210U | 64 GB | 1 TB Intel SSDPEKNW010T9 | 500 GB Crucial MX500 |
| `delta` | Intel i5-10210U | 64 GB | 500 GB Kingston SA2000M8 | 500 GB Crucial MX500 |
| `felix` | Intel i5-10210U | 64 GB | 500 GB Kingston SA2000M8 | 480 GB SATA SSD |

Each node's NVMe drive is dedicated entirely to Rook-Ceph as an OSD (`devicePathFilter: nvme0n1`); the SATA SSD serves as the Talos system disk. Every node also carries the Intel UHD Graphics iGPU built into the i5-10210U, used for hardware-accelerated video transcoding and local LLM inference.

### Storage (Rook-Ceph)

3 OSDs, one per node, ~1.84 TiB raw NVMe capacity pooled for replicated block (RBD) and CephFS storage backing all stateful workloads.

### Networking

- UniFi network gear (controller reachable via `unifi-dns` for internal DNS sync).
- External ingress: [Towonel](https://towonel.dev) (primary, TLS-passthrough into Envoy) with Cloudflare Tunnel kept deployed idle as a fast-rollback path.

---

## 🌎 DNS

Two [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) instances run in the cluster. One syncs `internal`-class `HTTPRoute`s to the local UniFi controller via the [UniFi webhook provider](https://github.com/kashalls/external-dns-unifi-webhook); the other syncs `external`-class routes to Cloudflare as DNS-only (unproxied) records — Cloudflare is used purely as the DNS zone here, traffic no longer passes through Cloudflare's edge. Ingress is done purely via Gateway API `HTTPRoute` resources through Envoy Gateway — no legacy `Ingress` objects.

---

## 🔐 Secrets

All secrets are stored in 1Password and pulled into the cluster at reconcile time by [external-secrets](https://external-secrets.io/) via a 1Password Connect `ClusterSecretStore`. Nothing sensitive is committed to this repository in plaintext.

---

## 🌟 Stargazers

<div align="center">

<a href="https://star-history.com/#kireque/home-ops&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=kireque/home-ops&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=kireque/home-ops&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=kireque/home-ops&type=Date" />
  </picture>
</a>

</div>

---

## 🙏 Gratitude and Thanks

This repository would not exist without [onedr0p](https://github.com/onedr0p)'s [cluster-template](https://github.com/onedr0p/cluster-template) and [home-ops](https://github.com/onedr0p/home-ops), and [bjw-s](https://github.com/bjw-s-labs)'s [home-ops](https://github.com/bjw-s-labs/home-ops) and [helm-charts](https://github.com/bjw-s-labs/helm-charts) (the `app-template` chart used throughout this repo). Thanks also to everyone in the [Home Operations](https://discord.gg/home-operations) Discord community — [kubesearch.dev](https://kubesearch.dev/) is a great place to see how others deploy their apps.

---

## 🔏 License

See [LICENSE](./LICENSE)
