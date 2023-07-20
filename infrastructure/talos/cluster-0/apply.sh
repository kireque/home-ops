#!/usr/bin/env bash

# Deploy the configuration to the nodes
talosctl apply-config -n 192.168.0.21 -f ./clusterconfig/cluster-0-delta.econline.local.yaml --insecure
talosctl apply-config -n 192.168.0.22 -f ./clusterconfig/cluster-0-enigma.econline.local.yaml --insecure
talosctl apply-config -n 192.168.0.23 -f ./clusterconfig/cluster-0-felix.econline.local.yaml --insecure
