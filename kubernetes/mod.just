set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[private]
default:
    just -l kube

[doc('Apply local Flux Kustomization')]
apply-ks ns ks:
    just kube render-local-ks "{{ ns }}" "{{ ks }}" | kubectl apply --server-side --force-conflicts --field-manager=kustomize-controller -f -

[doc('Browse a PVC')]
browse-pvc ns claim:
    kubectl run -n {{ ns }} browse-pvc-{{ claim }} -it --rm --restart=Never \
        --image=mirror.gcr.io/alpine:latest \
        --overrides='{"spec":{"containers":[{"name":"browse-pvc-{{ claim }}","image":"mirror.gcr.io/alpine:latest","stdin":true,"tty":true,"command":["/bin/sh"],"workingDir":"/mnt","volumeMounts":[{"mountPath":"/mnt","name":"data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"{{ claim }}"}}]}}'

[doc('Debug a node')]
[script]
debug-node node:
    trap 'kubectl delete pod -n default -l app.kubernetes.io/managed-by=kubectl-debug --field-selector spec.nodeName={{ node }} --ignore-not-found --wait=false' EXIT
    kubectl debug node/{{ node }} -n default -it --image=mirror.gcr.io/alpine:latest --profile=sysadmin

[doc('Delete local Flux Kustomization')]
delete-ks ns ks:
    just kube render-local-ks "{{ ns }}" "{{ ks }}" | kubectl delete -f -

[doc('Prune pods in Failed, Pending, or Succeeded state')]
[script]
prune-pods:
    for phase in Failed Pending Succeeded; do
        kubectl delete pods -A --field-selector status.phase="$phase" --ignore-not-found=true
    done

[doc('Restore a PVC from Kopiur (previous: 0 = latest; or a Snapshot name)')]
[script]
restore ns app previous='0':
    if [[ "{{ previous }}" =~ ^[0-9]+$ ]]; then
        source='{"fromPolicy":{"name":"{{ app }}","offset":{{ previous }}}}'
    else
        source='{"snapshotRef":{"name":"{{ previous }}"}}'
    fi
    flux -n {{ ns }} suspend kustomization {{ app }}
    flux -n {{ ns }} suspend helmrelease {{ app }}
    # Hold any KEDA ScaledObject (e.g. nfs-scaler) at 0 so it can't bring the app back mid-restore
    scaledobject="$(kubectl -n {{ ns }} get scaledobjects.keda.sh {{ app }} -o name --ignore-not-found)"
    if [[ -n "$scaledobject" ]]; then
        kubectl -n {{ ns }} annotate "$scaledobject" --overwrite autoscaling.keda.sh/paused-replicas=0
    fi
    # Suspend CronJobs (e.g. recyclarr) that aren't already suspended, so no new Job mounts the PVC
    cronjobs="$(kubectl -n {{ ns }} get cronjobs -l app.kubernetes.io/name={{ app }} -o json \
        | jq -r '.items[] | select(.spec.suspend != true) | "cronjob/\(.metadata.name)"')"
    for cronjob in $cronjobs; do
        kubectl -n {{ ns }} patch "$cronjob" --type merge -p '{"spec":{"suspend":true}}'
    done
    kubectl -n {{ ns }} get deploy,sts -l app.kubernetes.io/name={{ app }} -o name \
        | xargs -r -I{} kubectl -n {{ ns }} scale {} --replicas=0
    # Finished Job pods linger, so only wait for pods that are still running
    kubectl -n {{ ns }} wait pod --for=delete --selector="app.kubernetes.io/name={{ app }}" \
        --field-selector=status.phase!=Succeeded,status.phase!=Failed --timeout=5m
    jq -n --argjson source "$source" '{
        apiVersion: "kopiur.home-operations.com/v1alpha1",
        kind: "Restore",
        metadata: {name: "{{ app }}-manual", namespace: "{{ ns }}"},
        spec: {
            options: {enableFileDeletion: true},
            policy: {onMissingSnapshot: "Fail"},
            source: $source,
            target: {pvcRef: {name: "{{ app }}"}}
        }
    }' | kubectl create -f -
    phase=""
    deadline=$((SECONDS + 7200))
    while [[ "$phase" != "Completed" && "$phase" != "Failed" ]]; do
        if (( SECONDS >= deadline )); then
            phase="TimedOut"
            break
        fi
        sleep 10
        phase="$(kubectl -n {{ ns }} get restores.kopiur.home-operations.com {{ app }}-manual -o jsonpath='{.status.phase}')" \
            || echo "Failed to read Restore status; retrying" >&2
    done
    if [[ "$phase" != "Completed" ]]; then
        kubectl -n {{ ns }} get restores.kopiur.home-operations.com {{ app }}-manual -o yaml | yq '.status' || true
        echo "Restore ${phase}; {{ ns }}/{{ app }} left suspended, scaled down, KEDA-paused and CronJobs suspended" >&2
        exit 1
    fi
    kubectl -n {{ ns }} delete restores.kopiur.home-operations.com {{ app }}-manual
    if [[ -n "$scaledobject" ]]; then
        kubectl -n {{ ns }} annotate "$scaledobject" autoscaling.keda.sh/paused-replicas-
    fi
    for cronjob in $cronjobs; do
        kubectl -n {{ ns }} patch "$cronjob" --type merge -p '{"spec":{"suspend":false}}'
    done
    flux -n {{ ns }} resume kustomization {{ app }}
    flux -n {{ ns }} resume helmrelease {{ app }}
    flux -n {{ ns }} reconcile helmrelease {{ app }} --force
    kubectl -n {{ ns }} get deploy,sts -l app.kubernetes.io/name={{ app }} -o name \
        | xargs -r -I{} kubectl -n {{ ns }} rollout status {} --timeout=5m

[doc('Snapshot Kopiur PVCs (all, or filter by namespace/app)')]
[script]
snapshot ns='' app='':
    kubectl get snapshotschedules.kopiur.home-operations.com \
        {{ if ns == '' { '--all-namespaces' } else { '--namespace ' + ns } }} -o json \
        | jq --arg app '{{ app }}' --arg ts "$(date +%s)" '{
            apiVersion: "v1",
            kind: "List",
            items: [.items[] | select($app == "" or .metadata.name == $app) | {
                apiVersion: "kopiur.home-operations.com/v1alpha1",
                kind: "Snapshot",
                metadata: {
                    name: "\(.metadata.name)-manual-\($ts)",
                    namespace: .metadata.namespace,
                    labels: {
                        "kopiur.home-operations.com/config": .spec.policyRef.name,
                        "kopiur.home-operations.com/origin": "manual"
                    }
                },
                spec: {policyRef: .spec.policyRef}
            }]
        }' \
        | kubectl create -f -

[arg('state', pattern='suspend|resume')]
[doc('Suspend or resume VolSync')]
volsync state:
    flux -n volsync-system {{ state }} kustomization volsync
    flux -n volsync-system {{ state }} helmrelease volsync
    kubectl -n volsync-system scale deployment volsync --replicas {{ if state != "suspend" { "1" } else { "0" } }}

[arg('resource', pattern='hr|ks|gitrepo|ocirepo|es')]
[doc('Sync a resource')]
[script]
sync resource:
    kubectl get {{ resource }} --no-headers -A | while read -r ns name _; do
        kubectl -n "$ns" annotate --field-manager flux-client-side-apply --overwrite {{ resource }} "$name" \
            "force-sync=$(date +%s)" \
            "reconcile.fluxcd.io/requestedAt=$(date +%s)" \
            "reconcile.fluxcd.io/forceAt=$(date +%s)"
    done

[doc('View a secret')]
view-secret ns secret:
    kubectl view-secret -n {{ ns }} {{ secret }}

[private]
render-local-ks ns ks:
    flux-local build ks --namespace "{{ ns }}" --path "{{ source_directory() }}/flux/cluster" "{{ ks }}"
