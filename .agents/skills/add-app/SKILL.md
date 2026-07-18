---
name: add-app
description: Use when deploying a new application to the cluster — scaffolding a Flux Kustomization plus app-template HelmRelease under kubernetes/apps/ (new app, new service, "add X to the cluster")
---

# Add a New Application

Scaffolds `kubernetes/apps/<namespace>/<app>/` with a Flux Kustomization (`ks.yaml`) and an app-template HelmRelease. Every value below comes from current repo conventions — when in doubt, mirror a recent real app instead of inventing structure:

| Reference app | Shows |
|---|---|
| `kubernetes/apps/network/echo` | Minimal stateless app (dedicated chart, no persistence/secrets) |
| `kubernetes/apps/downloads/radarr` | Full pattern: kopiur persistence, nfs-scaler, secrets, route, digest-pinned image |

## Step 1: Gather details

Ask the user (AskUserQuestion) for anything not already given:

1. **App name** and **namespace** (existing dirs: `ls kubernetes/apps/`)
2. **Image** repository + tag (upstream's current release; prefer `ghcr.io/home-operations/*` images where one exists — they're digest-pinned by Renovate)
3. **Port** the app listens on, and whether it gets a **route** (hostname); internal (`envoy-internal`, default) or public (`envoy-external`)
4. **Persistence** — does the app store state? (→ kopiur backup component)
5. **Secrets** — env vars from 1Password? (→ ExternalSecret). Get the 1Password item name AND its exact field names — never guess field names
6. **Dependencies** — other Flux Kustomizations this app needs (e.g. `rook-ceph-cluster` for persistence)

## Step 2: Create the files

Layout:

```
kubernetes/apps/<namespace>/<app>/
├── ks.yaml
└── app/
    ├── kustomization.yaml
    ├── ocirepository.yaml
    ├── helmrelease.yaml
    └── externalsecret.yaml      # only if secrets
```

### ks.yaml

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <app>
spec:
  interval: 1h
  path: ./kubernetes/apps/<namespace>/<app>/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: <namespace>
  wait: false
```

**`wait`:** keep it explicit `wait: false` on normal leaf apps — that's this repo's convention (unlike upstream templates that omit it). Only set `wait: true` when another Kustomization will `dependsOn` this one and needs a real readiness gate (see `flux-operator`, `external-secrets`, `actions-runner-controller` for examples).

**If the app has persistence**, add these to `spec` (components use `${APP}` and `${KOPIUR_*}` substitutions — see `kubernetes/components/kopiur/backup/` for all knobs and their defaults):

```yaml
  components:
    - ../../../../components/kopiur/backup
  dependsOn:
    - name: rook-ceph-cluster
      namespace: rook-ceph
  postBuild:
    substitute:
      APP: <app>
      # Optional overrides, only when defaults don't fit:
      # KOPIUR_CAPACITY: 10Gi          # default: 5Gi
      # KOPIUR_STORAGECLASS: ceph-block # default shown
      # KOPIUR_ACCESSMODES: ReadWriteOnce # default shown
```

Add `../../../../components/nfs-scaler` alongside kopiur only if the app also mounts a shared NFS media/data path (see radarr). Add user-specified dependencies to `dependsOn`. Include `postBuild.substitute.APP` whenever any component is used; omit `components`/`postBuild` entirely otherwise.

### app/kustomization.yaml

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./externalsecret.yaml   # only if secrets
  - ./helmrelease.yaml
  - ./ocirepository.yaml
```

`namespace:` is set at the namespace-level `kubernetes/apps/<namespace>/kustomization.yaml`, not per-app — don't repeat it here unless the existing namespace's file already does (check first).

### app/ocirepository.yaml

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/source.toolkit.fluxcd.io/ocirepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: <app>
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: <version>
  url: oci://ghcr.io/bjw-s-labs/helm/app-template
```

**Never hardcode `<version>` from memory** — use the version the rest of the repo is on:

```bash
grep -h "tag:" kubernetes/apps/*/*/app/ocirepository.yaml | sort | uniq -c | sort -rn | head -1
```

### app/helmrelease.yaml

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <app>
spec:
  chartRef:
    kind: OCIRepository
    name: <app>
  interval: 1h
  values:
    controllers:
      <app>:
        annotations:
          reloader.stakater.com/auto: "true"
        containers:
          app:
            image:
              repository: <image-repo>
              tag: <image-tag>@<sha256-digest>
            probes:
              liveness:
                enabled: true
                spec:
                  periodSeconds: 30
                  timeoutSeconds: 5
                  failureThreshold: 5
              readiness:
                enabled: true
                spec:
                  periodSeconds: 10
                  timeoutSeconds: 5
                  failureThreshold: 5
              startup:
                enabled: true
                spec:
                  failureThreshold: 30
                  periodSeconds: 10
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities: {drop: ["ALL"]}
            resources:
              requests:
                cpu: 10m
                memory: 128Mi
              limits:
                memory: 256Mi
    defaultPodOptions:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
    service:
      app:
        ports:
          http:
            port: <port>
```

Look up upstream's current release tag **and** resolve it to a `@sha256:` digest (`docker manifest inspect` or the registry's tag page) — CLAUDE.md requires digest pinning where possible. Adjust `runAsUser`/`runAsGroup`/`fsGroup` (and capabilities) to what the image requires; drop `defaultPodOptions.securityContext` only if the image genuinely can't run non-root.

**Optional value blocks** (top-level under `values`, alphabetical: `controllers`, `persistence`, `route`, `service`):

Route (web UI/API):

```yaml
    route:
      app:
        hostnames:
          - "{{ .Release.Name }}.econline.nl"
        parentRefs:
          - name: envoy-internal    # envoy-external for public apps
            namespace: network
```

Persistence (pairs with the kopiur block in ks.yaml):

```yaml
    persistence:
      config:
        existingClaim: "{{ .Release.Name }}"
      tmp:
        type: emptyDir
        globalMounts:
          - path: /tmp
```

Secrets: add to the container:

```yaml
            envFrom:
              - secretRef:
                  name: "{{ .Release.Name }}-secret"
```

### app/externalsecret.yaml (only if secrets)

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <app>
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: <app>-secret
    template:
      data:
        SOME_ENV_VAR: "{{ .<app>_field_name }}"
  dataFrom:
    - extract:
        key: <1password-item>
```

Convention: `metadata.name` is `<app>`, the generated Secret is `<app>-secret`, and `dataFrom.extract` pulls all fields of the named 1Password item (reference them directly as `{{ .<field_name> }}` in `template.data`, or add a `rewrite` block to prefix them — see other apps for examples). The referenced field names must match the item's real field names (from Step 1) — a wrong field name renders an empty value with no error. If field names weren't provided and you can't ask, insert `<FIXME: 1password field name>` placeholders and call them out.

## Step 3: Register in the namespace kustomization

Add `./<app>/ks.yaml` to `kubernetes/apps/<namespace>/kustomization.yaml` `resources`, in alphabetical position among the app entries (`namespace.yaml` stays first; leave existing entries where they are).

**New namespace?** Create `kubernetes/apps/<namespace>/` with a `namespace.yaml` and `kustomization.yaml` copied from an existing namespace (e.g. `downloads`) — keep the `components/alerts` and `components/kopiur/secret` components and the literal `name: _` in namespace.yaml (kustomize renames it).

## Step 4: Verify

```bash
kustomize build kubernetes/apps/<namespace>/<app>/app   # must render; ${APP} vars staying literal is expected
flux-local test --all-namespaces --enable-helm --path kubernetes/flux/cluster --verbose
```

Show the user the created files and get confirmation before committing.

## Common mistakes

- **Copying a chart version or image tag/digest from this skill or memory** — always read the current version from the repo (Step 2 command) and upstream.
- **Skipping digest pinning** — CLAUDE.md requires images pinned to `@sha256:` digests where possible; a bare tag is a gap to flag, not the default.
- **Forgetting `reloader.stakater.com/auto`** — without it, secret/config changes don't restart pods.
- **`readOnlyRootFilesystem: true` without writable scratch space** — apps that write to `/tmp` will crash; mount an emptyDir via `persistence.tmp`.
- **Skipping the sorting conventions** — HelmRelease values follow `.agents/instructions/flux.sorting.instructions.md`.
- **Using `volsync`** — CLAUDE.md's storage section still mentions it, but new apps use the `kopiur` components (`components/kopiur/backup`, `components/kopiur/secret`); check which is actually current before relying on either doc.
