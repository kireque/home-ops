#!/bin/bash

if ! [ -f talconfig.yaml ]; then
    echo "Missing talconfig.yaml!"
    exit 1
fi

if ! [ -f talenv.yaml ]; then
    echo "Missing talenv.sops.yaml!"
    exit 1
fi

if ! [ -f talsecret.sops.yaml ]; then
    talhelper gensecret > talsecret.sops.yaml
    sops --encrypt --in-place talenv.sops.yaml
fi

if ! [ -f clusterconfig/talosconfig ]; then
    talhelper genconfig -e talenv.yaml -s talsecret.sops.yaml -c talconfig.yaml
fi

echo "Applying talos configs"

talosctl config merge ./clusterconfig/talosconfig

# Deploy the configuration to the nodes
talosctl apply-config --insecure --nodes talos-01.econline.local --file ./clusterconfig/home-cluster-talos-01.yaml
talosctl apply-config --insecure --nodes talos-02.econline.local --file ./clusterconfig/home-cluster-talos-02.yaml
talosctl apply-config --insecure --nodes talos-03.econline.local --file ./clusterconfig/home-cluster-talos-03.yaml

echo "Waiting for installation"
sleep 120

talosctl config node talos-01.econline.local talos-02.econline.local talos-03.econline.local
talosctl config endpoint talos-01.econline.local talos-02.econline.local talos-03.econline.local

echo Running bootstrap..
talosctl bootstrap -n talos-01.econline.local
sleep 180

talosctl kubeconfig -f .
export KUBECONFIG=$(pwd)/kubeconfig

echo kubectl get no
kubectl get no

echo "Apply CNI and CSR Approver"
kustomize build --enable-helm | kubectl apply -f -