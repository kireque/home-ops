#!/usr/bin/env bash

# Deploy the configuration to the nodes
talosctl apply-config --insecure --nodes talos-01.econline.local --file ./clusterconfig/kubernetes-talos-01.yaml
talosctl apply-config --insecure --nodes talos-02.econline.local --file ./clusterconfig/kubernetes-talos-02.yaml
talosctl apply-config --insecure --nodes talos-03.econline.local --file ./clusterconfig/kubernetes-talos-03.yaml