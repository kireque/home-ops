#!/usr/bin/env bash
cd ~/git/home-ops/infrastructure/talos/
talhelper genconfig -c talconfig.yaml -e talenv.sops.yaml -s talsecret.sops.yaml

cp ./clusterconfig/talosconfig ~/.talos/config

talosctl config node "192.168.0.21"

echo Applying master..
# Master nodes
talosctl apply-config --insecure --nodes talos-01.econline.local --file ./clusterconfig/home-cluster-talos-01.yaml
talosctl apply-config --insecure --nodes talos-02.econline.local --file ./clusterconfig/home-cluster-talos-02.yaml
talosctl apply-config --insecure --nodes talos-03.econline.local --file ./clusterconfig/home-cluster-talos-03.yaml

echo Sleep..
sleep 120

echo Running bootstrap..
talosctl bootstrap

echo Sleep..
sleep 180

talosctl kubeconfig -f .
export KUBECONFIG=$(pwd)/kubeconfig

echo kubectl get no
kubectl get no

echo Running kustomize
kubectl kustomize --enable-helm ./ | kubectl apply -f -

