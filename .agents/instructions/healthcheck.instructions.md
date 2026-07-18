# Cluster health check instructions

When the user asks for a cluster health check — in any language (e.g. "healthcheck", "check the cluster", "hoe staat het cluster ervoor", "wat is er mis met het cluster") — run the following audit pipeline top-down. Failures at lower layers often explain failures at higher ones, so work in order.

After completing all checks, produce a [Health Report](#health-report-format) summarising every finding.

---

## 0. Orientation

Confirm the environment is operational before running any checks.

```bash
kubectl cluster-info
kubectl get nodes --no-headers | wc -l   # expect 3 (enigma, delta, felix)
```

Note the current date and time in the report header.

---

## 1. Talos node health

```bash
# Overall node health via Talos API
talosctl -n enigma,delta,felix health

# Kernel-level errors
talosctl -n enigma,delta,felix dmesg --tail 200 | grep -i "error\|panic\|oom"

# Kubernetes node status and version
kubectl get nodes -o wide

# Node conditions: MemoryPressure, DiskPressure, PIDPressure, NetworkUnavailable
kubectl describe nodes | grep -A 8 "Conditions:"
```

Flag any node that is **NotReady** or has a condition set to `True` (other than `Ready`).

---

## 2. Flux reconciliation health

Check every Flux object type for non-Ready status. A single failing Kustomization can block an entire namespace of apps.

```bash
flux get sources git --all-namespaces
flux get sources oci --all-namespaces
flux get kustomizations --all-namespaces
flux get helmreleases --all-namespaces
```

Flag every row where **READY** is not `True`.

For each failing resource, dig into the cause:

```bash
# Kustomization details
kubectl describe ks <name> -n <namespace>

# HelmRelease details
kubectl describe hr <name> -n <namespace>
```

Look at `.status.conditions[*].message` and `.status.lastAttemptedRevision`. Check whether the failure is a chart download error, a render error, a dependency not being ready, or a Helm upgrade failure.

### HelmRelease remediation runbook

**Stalled / RetriesExceeded**

When a HelmRelease shows `Stalled=True / RetriesExceeded`, the failure counter is locked and the controller will refuse all further attempts — even after annotating with `reconcile.fluxcd.io/resetAt` or patching `upgradeFailures` to 0. Those approaches are unreliable once the controller has marked the release as a terminal error.

**StatefulSet immutable field upgrade failure**

The most common cause of a permanent stall in this cluster is a chart upgrade that changes an immutable StatefulSet field (e.g. `volumeClaimTemplates`, `selector`). Kubernetes rejects the `PATCH` and Helm rolls back. On the next attempt the rollback-created StatefulSet is present again, causing the same rejection — an infinite loop.

Fix (preserves the PVC):

```bash
NS=<namespace>
HR=<helmrelease-name>

# 1. Stop Flux from touching the release
flux suspend hr $HR -n $NS

# 2. Delete all Helm release history so the next apply is a fresh install
kubectl delete secrets -n $NS -l name=$HR,owner=helm

# 3. Delete the StatefulSet (PVC is not touched)
kubectl delete sts <statefulset-name> -n $NS --ignore-not-found

# 4. Let Flux do a fresh `helm install` instead of `helm upgrade`
flux resume hr $HR -n $NS
```

A fresh install creates the StatefulSet from scratch, bypassing the immutable-field restriction. The PVC is reattached automatically (same claim name).

---

## 3. Pod health

```bash
# Non-running, non-completed pods
kubectl get pods --all-namespaces | grep -Ev '(Running|Completed|Succeeded)'

# Pods with high restart counts (> 5)
kubectl get pods --all-namespaces --no-headers \
  | awk '$5 > 5 {print $1, $2, $5}'

# CrashLoopBackOff pods
kubectl get pods --all-namespaces | grep CrashLoop

# OOMKilled events
kubectl get events --all-namespaces | grep -i OOMKill
```

For each problematic pod:

```bash
kubectl describe pod <name> -n <namespace>
kubectl logs <name> -n <namespace> --previous --tail 100
```

---

## 4. Kubernetes events

```bash
# Warning events sorted by most recent first
kubectl get events --all-namespaces \
  --sort-by='.lastTimestamp' \
  --field-selector type=Warning \
  | tail -60
```

Pay extra attention to these event reasons: `BackOff`, `FailedScheduling`, `Evicted`, `FailedMount`, `Unhealthy`, `FailedCreate`, `OOMKilling`, `NodeNotReady`.

---

## 5. Storage health

### Rook-Ceph

```bash
# Overall cluster health (expect HEALTH_OK)
kubectl -n rook-ceph get cephcluster

# Full Ceph status
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status

# OSD status (all OSDs should be up and in)
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd status

# Disk usage (warn if any pool is > 75%)
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph df

# Block pools, filesystems, object stores
kubectl get cephblockpool,cephfilesystem,cephobjectstore -n rook-ceph
```

### PVCs and PVs

```bash
# PVCs not bound
kubectl get pvc --all-namespaces | grep -v Bound

# PVs not bound or in failed state
kubectl get pv | grep -v Bound
```

### Kopiur backups

```bash
# Snapshot policies and their retention/verification schedules
kubectl get snapshotpolicy --all-namespaces

# Snapshot schedules: check for errors
kubectl get snapshotschedule --all-namespaces

# Restore objects (PVC data sources) — should be Ready
kubectl get restore --all-namespaces

# kopiur controller itself
kubectl -n kopiur-system get pods
```

Flag any `Restore` that isn't `Ready`, or a `SnapshotSchedule`/`SnapshotPolicy` with an error condition or no recent successful run.

---

## 6. Certificate health

```bash
# ClusterIssuers (expect Ready=True)
kubectl get clusterissuer

# All certificates with expiry dates
kubectl get certificate --all-namespaces \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter'
```

Flag any certificate:
- With `READY` != `True`
- Expiring within **30 days** from today

---

## 7. External Secrets

```bash
# ClusterSecretStore connectivity (onepassword store)
kubectl get clustersecretstore

# All ExternalSecrets — expect STATUS=SecretSynced
kubectl get externalsecret --all-namespaces
```

Flag any ExternalSecret not in `SecretSynced` status. Check the store connectivity first — a broken 1Password connection will cause all secrets to fail.

---

## 8. Networking health

### Cilium CNI

```bash
# Cilium agent and operator status
cilium status

# All Cilium pods (one per node expected)
kubectl -n kube-system get pods -l app.kubernetes.io/name=cilium
```

### CoreDNS

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns

# Quick DNS resolution test
kubectl run -it --rm dnstest --image=busybox:1 --restart=Never \
  -- nslookup kubernetes.default 2>/dev/null | grep -A2 "Name:"
```

### Gateway API / Envoy Gateway

```bash
# Gateways should show Programmed=True
kubectl get gateway --all-namespaces

# HTTPRoutes with non-ready status
kubectl get httproute --all-namespaces

# Envoy proxy pods
kubectl -n network get pods -l gateway.envoyproxy.io/owning-gateway-name
```

### Cloudflared tunnel

```bash
kubectl -n network get pods -l app.kubernetes.io/name=cloudflare-tunnel

# Recent tunnel logs (look for reconnects or auth failures)
kubectl -n network logs deploy/cloudflare-tunnel --tail 30
```

---

## 9. Active Prometheus alerts

```bash
# Firing alerts from Prometheus API
kubectl -n observability exec -it \
  $(kubectl -n observability get pod -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}') \
  -- wget -qO- 'http://localhost:9090/api/v1/alerts' \
  | jq -r '.data.alerts[] | select(.state=="firing") | "\(.labels.severity | ascii_upcase) \(.labels.alertname) — \(.annotations.summary // .annotations.description // "")"'
```

List each firing alert with its severity and description. Critical alerts take priority.

---

## 10. Observability stack self-health

```bash
# All observability pods should be Running
kubectl get pods -n observability

# Sanity-check rule and monitor counts
kubectl get prometheusrule --all-namespaces --no-headers | wc -l
kubectl get servicemonitor --all-namespaces --no-headers | wc -l
```

---

## 11. Critical infrastructure — deep check

These components underpin everything else. Any issue here cascades widely.

| Namespace | Components to check |
|-----------|---------------------|
| `flux-system` | flux-operator, flux-instance |
| `cert-manager` | controller, webhook, cainjector |
| `external-secrets` | controller, webhook, onepassword-connect |
| `rook-ceph` | operator, mgr, 3× mon, osd pods |
| `kube-system` | coredns (2 replicas), metrics-server, cilium-operator, descheduler |
| `network` | envoy-gateway, cloudflare-tunnel, external-dns |
| `kopiur-system` | kopiur |

```bash
for ns in flux-system cert-manager external-secrets rook-ceph kube-system network kopiur-system; do
  echo "=== $ns ==="
  kubectl get pods -n $ns --no-headers | grep -v Running
done
```

---

## 12. System upgrade status

```bash
# tuppr manages Talos and Kubernetes upgrades
kubectl -n system-upgrade get pods
kubectl -n system-upgrade get plans 2>/dev/null || true
```

Flag any plan that is in progress or stalled.

---

## Health report format

After completing all checks above, output a report using this structure:

```markdown
## Cluster Health Report — {YYYY-MM-DD HH:MM}

### Summary
| Layer | Status | Notes |
|-------|--------|-------|
| Nodes | 🟢/🟡/🔴 | |
| Flux | 🟢/🟡/🔴 | |
| Pods | 🟢/🟡/🔴 | |
| Storage (Ceph) | 🟢/🟡/🔴 | |
| Certificates | 🟢/🟡/🔴 | |
| External Secrets | 🟢/🟡/🔴 | |
| Networking | 🟢/🟡/🔴 | |
| Alerts | 🟢/🟡/🔴 | |
| Observability | 🟢/🟡/🔴 | |

🟢 Healthy  🟡 Warning (degraded but functional)  🔴 Critical (action required)

---

### Issues found

| Severity | Area | Resource | Issue |
|----------|------|----------|-------|
| 🔴 | ... | ... | ... |
| 🟡 | ... | ... | ... |

### Healthy components
(brief bullet list of areas with no issues)

### Recommended actions
1. ...
2. ...
```

Always include the recommended actions section — even if everything is healthy, confirm that and suggest any preventive steps observed during the audit.
