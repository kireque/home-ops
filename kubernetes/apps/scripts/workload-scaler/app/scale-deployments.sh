#!/bin/bash
for ns in $(kubectl get ns --no-headers | cut -d " " -f1); do
    # Check if there are deployments to scale
    if kubectl get deployments -n $ns -l automaticSchedular=true --no-headers | grep -q '.'; then
        echo "Scaling deployments in namespace '$ns'..."
        kubectl scale deployments --namespace=$ns -l automaticSchedular=true --replicas=$1
        echo "Deployments scaled in namespace '$ns'."
    fi
done
