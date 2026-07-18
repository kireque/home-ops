# Correct schemas

Whenever requested to fix or correct schemas, follow these instructions:

** Default rules **
- only apply schemas to yaml files
- do not apply schemas to files in any directory named `resources`
- if you cannot find the right schema to apply to a file then apend "# TODO: apply schema"
- schemas should always follow `---`
- there is always a schema defined on the second line of a yaml file
- remove incorrect schemas and replace them with the correct schema comment

## apiVersion to schema mappings ##

Default domain for Kubernetes/Flux/CRD schemas in this repo is `https://k8s-schemas.home-operations.com/<apiGroup>/<kind-lowercase>_<version>.json` (e.g. `kustomize.toolkit.fluxcd.io/kustomize.toolkit.fluxcd.io/kustomization_v1.json`). Exceptions:

`kustomize.toolkit.fluxcd.io/v1` and `kind: Kustomization` -> `# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/kustomize.toolkit.fluxcd.io/kustomization_v1.json`
`helm.toolkit.fluxcd.io/v2` and `kind: HelmRelease`, chart is **app-template** (sidecar `ocirepository.yaml` has `url: oci://ghcr.io/bjw-s-labs/helm/app-template`) -> `# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json`
`helm.toolkit.fluxcd.io/v2` and `kind: HelmRelease`, any other chart -> `# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/helm.toolkit.fluxcd.io/helmrelease_v2.json`
`source.toolkit.fluxcd.io/v1` and `kind: OCIRepository` -> `# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/source.toolkit.fluxcd.io/ocirepository_v1.json`
`kustomize.config.k8s.io/v1beta1` -> `# yaml-language-server: $schema=https://json.schemastore.org/kustomization`
`external-secrets.io/v1` and `kind: ExternalSecret` -> `# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/external-secrets.io/externalsecret_v1.json`

For any other `apiGroup`/`kind` not listed above, derive the URL from the pattern (`https://k8s-schemas.home-operations.com/<apiGroup>/<kind-lowercase>_<version>.json`) rather than falling back to `raw.githubusercontent.com/fluxcd-community/flux2-schemas` or `datreeio/CRDs-catalog` — those are not used in this repo. If genuinely unsure whether the derived URL exists, append `# TODO: apply schema` instead of guessing.