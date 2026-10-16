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
    # Pre-flight: validate everything before touching the app
    if [[ "{{ previous }}" =~ ^(0|[1-9][0-9]*)$ ]]; then
        source="$(jq -nc --arg app '{{ app }}' --argjson offset '{{ previous }}' \
            '{fromPolicy: {name: $app, offset: $offset}}')"
    else
        kubectl -n {{ ns }} get snapshots.kopiur.home-operations.com '{{ previous }}' -o name
        source="$(jq -nc --arg snapshot '{{ previous }}' '{snapshotRef: {name: $snapshot}}')"
    fi
    kubectl -n {{ ns }} get pvc {{ app }} -o name
    kubectl -n {{ ns }} get snapshotpolicies.kopiur.home-operations.com {{ app }} -o name
    if [[ -n "$(kubectl -n {{ ns }} get restores.kopiur.home-operations.com {{ app }}-manual -o name --ignore-not-found)" ]]; then
        echo "Restore {{ ns }}/{{ app }}-manual already exists (left over from an earlier run?); inspect and delete it first" >&2
        exit 1
    fi
    held="{{ ns }}/{{ app }} left suspended, scaled down, KEDA-paused, CronJobs and SnapshotSchedule suspended"

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
    # Suspend the backup schedule (unless already suspended) so it can't snapshot a half-restored PVC
    schedule="$(kubectl -n {{ ns }} get snapshotschedules.kopiur.home-operations.com {{ app }} -o json --ignore-not-found \
        | jq -r 'select(.spec.schedule.suspend != true) | "snapshotschedule.kopiur.home-operations.com/\(.metadata.name)"')"
    if [[ -n "$schedule" ]]; then
        kubectl -n {{ ns }} patch "$schedule" --type merge -p '{"spec":{"schedule":{"suspend":true}}}'
    fi
    kubectl -n {{ ns }} get deploy,sts -l app.kubernetes.io/name={{ app }} -o name \
        | xargs -r -I{} kubectl -n {{ ns }} scale {} --replicas=0

    # Wait until no running pod mounts the PVC. Fails closed: only a successful query that
    # finds no such pod lets the restore start. Finished Job pods linger, so ignore those.
    stop_deadline=$((SECONDS + 300))
    while true; do
        if pods="$(kubectl -n {{ ns }} get pods -o json)"; then
            busy="$(jq -r --arg pvc '{{ app }}' '.items[]
                | select(.status.phase != "Succeeded" and .status.phase != "Failed")
                | select(any(.spec.volumes[]?; .persistentVolumeClaim.claimName == $pvc))
                | .metadata.name' <<<"$pods")"
            if [[ -z "$busy" ]]; then
                break
            fi
        else
            busy="(pod query failed)"
        fi
        if (( SECONDS >= stop_deadline )); then
            echo "PVC {{ ns }}/{{ app }} still in use by: ${busy//$'\n'/, }" >&2
            echo "$held" >&2
            exit 1
        fi
        sleep 5
    done

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
    restore_uid="$(kubectl -n {{ ns }} get restores.kopiur.home-operations.com {{ app }}-manual -o jsonpath='{.metadata.uid}')"
    # Kopiur reports Failed after every failed mover attempt, even while the mover Job still
    # retries, so only give up once Failed has held for 30s with no owned Job left to retry
    phase=""
    failed_since=""
    deadline=$((SECONDS + 7200))
    while true; do
        if (( SECONDS >= deadline )); then
            phase="TimedOut"
            break
        fi
        sleep 10
        if ! phase="$(kubectl -n {{ ns }} get restores.kopiur.home-operations.com {{ app }}-manual -o jsonpath='{.status.phase}')"; then
            phase=""
            echo "Failed to read Restore status; retrying" >&2
            continue
        fi
        if [[ "$phase" == "Completed" ]]; then
            break
        fi
        if [[ "$phase" == "Failed" ]] && jobs="$(kubectl -n {{ ns }} get jobs -o json)"; then
            retrying="$(jq --arg uid "$restore_uid" '[.items[]
                | select(any(.metadata.ownerReferences[]?; .uid == $uid))
                | select(all(.status.conditions[]?; .type != "Failed" or .status != "True"))] | length' <<<"$jobs")"
            if [[ "$retrying" == "0" ]]; then
                failed_since="${failed_since:-$SECONDS}"
                if (( SECONDS - failed_since >= 30 )); then
                    break
                fi
                continue
            fi
        fi
        failed_since=""
    done
    if [[ "$phase" != "Completed" ]]; then
        kubectl -n {{ ns }} get restores.kopiur.home-operations.com {{ app }}-manual -o yaml | yq '.status' || true
        echo "Restore ${phase}; $held" >&2
        exit 1
    fi

    kubectl -n {{ ns }} delete restores.kopiur.home-operations.com {{ app }}-manual
    if [[ -n "$schedule" ]]; then
        kubectl -n {{ ns }} patch "$schedule" --type merge -p '{"spec":{"schedule":{"suspend":false}}}'
    fi
    for cronjob in $cronjobs; do
        kubectl -n {{ ns }} patch "$cronjob" --type merge -p '{"spec":{"suspend":false}}'
    done
    if [[ -n "$scaledobject" ]]; then
        kubectl -n {{ ns }} annotate "$scaledobject" autoscaling.keda.sh/paused-replicas-
    fi
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
