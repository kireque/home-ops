#!/usr/bin/env bash

# Deploy the configuration to the nodes
talosctl apply-config -n talos-01.econline.local -f ./clusterconfig/kubernetes-talos-01.econline.local.yaml
talosctl apply-config -n talos-02.econline.local -f ./clusterconfig/kubernetes-talos-02.econline.local.yaml
talosctl apply-config -n talos-03.econline.local -f ./clusterconfig/kubernetes-talos-03.econline.local.yaml
