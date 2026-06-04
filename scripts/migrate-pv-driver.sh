#!/usr/bin/env bash
# Migrates a single PVC's PV from rook-ceph.rbd.csi.ceph.com → rbd.csi.ceph.com.
# Usage: ./migrate-pv-driver.sh <namespace> <pvc-name>
set -euo pipefail

NS="${1:?Usage: $0 <namespace> <pvc-name>}"
PVC="${2:?Usage: $0 <namespace> <pvc-name>}"
OLD_DRIVER="rook-ceph.rbd.csi.ceph.com"
NEW_DRIVER="rbd.csi.ceph.com"

echo "==> Checking $NS/$PVC"
PV=$(kubectl get pvc "$PVC" -n "$NS" -o jsonpath='{.spec.volumeName}')
CURRENT_DRIVER=$(kubectl get pv "$PV" -o jsonpath='{.spec.csi.driver}')

if [[ "$CURRENT_DRIVER" == "$NEW_DRIVER" ]]; then
  echo "    Already on new driver, skipping."
  exit 0
fi
if [[ "$CURRENT_DRIVER" != "$OLD_DRIVER" ]]; then
  echo "    Unexpected driver: $CURRENT_DRIVER" >&2
  exit 1
fi

echo "==> Exporting PV $PV with new driver"
kubectl get pv "$PV" -o yaml \
  | sed "s|$OLD_DRIVER|$NEW_DRIVER|g" \
  | grep -v '^\s*\(creationTimestamp\|resourceVersion\|uid\|deletionTimestamp\|deletionGracePeriodSeconds\|generation\):\|kubernetes.io/pv-protection' \
  > "/tmp/pv-migrated-${PV}.yaml"

# Find pod and owner workload
POD=$(kubectl get pods -n "$NS" -o json \
  | jq -r --arg pvc "$PVC" \
    '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == $pvc) | .metadata.name' \
  | head -1)

SCALE_RESOURCE=""
REPLICAS=0
if [[ -n "$POD" ]]; then
  OWNER_KIND=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.metadata.ownerReferences[0].kind}')
  OWNER_NAME=$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.metadata.ownerReferences[0].name}')

  if [[ "$OWNER_KIND" == "ReplicaSet" ]]; then
    OWNER_NAME=$(kubectl get rs "$OWNER_NAME" -n "$NS" -o jsonpath='{.metadata.ownerReferences[0].name}')
    OWNER_KIND="Deployment"
  fi

  if [[ "$OWNER_KIND" == "Job" ]]; then
    echo "    Pod owner is a Job and status is not Running — skipping scale down"
    POD=""
  else
    SCALE_RESOURCE="${OWNER_KIND,,}/${OWNER_NAME}"
    REPLICAS=$(kubectl get "${OWNER_KIND,,}" "$OWNER_NAME" -n "$NS" -o jsonpath='{.spec.replicas}')

    echo "==> Scaling down $SCALE_RESOURCE (replicas: $REPLICAS)"
    kubectl scale "${OWNER_KIND,,}" "$OWNER_NAME" -n "$NS" --replicas=0
    kubectl wait --for=delete pod "$POD" -n "$NS" --timeout=120s
  fi
else
  echo "    No active pod found, skipping scale down"
fi

echo "==> Deleting PV and clearing all finalizers"
kubectl delete pv "$PV" --wait=false
kubectl patch pv "$PV" -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl wait --for=delete pv "$PV" --timeout=60s

echo "==> Applying new PV"
kubectl apply -f "/tmp/pv-migrated-${PV}.yaml"

echo "==> Patching PVC bind annotation"
kubectl patch pvc "$PVC" -n "$NS" --type=json \
  -p '[{"op":"remove","path":"/metadata/annotations/pv.kubernetes.io~1bind-completed"}]' 2>/dev/null || true

kubectl wait --for=jsonpath='{.status.phase}'=Bound "pvc/$PVC" -n "$NS" --timeout=60s
echo "    PVC bound"

if [[ -n "$SCALE_RESOURCE" ]]; then
  echo "==> Scaling $SCALE_RESOURCE back to $REPLICAS"
  kubectl scale "$SCALE_RESOURCE" -n "$NS" --replicas="$REPLICAS"

  if [[ "${OWNER_KIND,,}" == "deployment" ]]; then
    kubectl wait --for=condition=Available "$SCALE_RESOURCE" -n "$NS" --timeout=120s
  else
    kubectl rollout status "$SCALE_RESOURCE" -n "$NS" --timeout=120s
  fi
fi

echo "==> Done: $NS/$PVC migrated to $NEW_DRIVER"
