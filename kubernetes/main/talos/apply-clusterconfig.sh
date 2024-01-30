#!/usr/bin/env bash

# Deploy the configuration to the nodes
talosctl apply-config -i -n 10.1.1.31 -f ./clusterconfig/main-delta.home.econline.nl.yaml
talosctl apply-config -i -n 10.1.1.32 -f ./clusterconfig/main-enigma.home.econline.nl.yaml
talosctl apply-config -i -n 10.1.1.33 -f ./clusterconfig/main-felix.home.econline.nl.yaml