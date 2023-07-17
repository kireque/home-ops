#!/usr/bin/env bash

echo "Applying Node Configs"
# Deploy the configuration to the nodes
talosctl apply-config -n talos-01.econline.local -f ./clusterconfig/kubernetes-talos-01.econline.local.yaml --insecure
talosctl apply-config -n talos-02.econline.local -f ./clusterconfig/kubernetes-talos-02.econline.local.yaml --insecure
talosctl apply-config -n talos-03.econline.local -f ./clusterconfig/kubernetes-talos-03.econline.local.yaml --insecure

echo "Sleeping..."
sleep 120

talosctl config node "192.168.0.21"; talosctl config endpoint 192.168.0.21 192.168.0.22 192.168.0.23
echo "Running bootstrap..."
talosctl bootstrap

echo "Sleeping..."
sleep 180

talosctl kubeconfig -f .
export KUBECONFIG=$(pwd)/kubeconfig

echo kubectl get nodes
kubectl get nodes
