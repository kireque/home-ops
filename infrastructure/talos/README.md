# Talos cluster initialization

## Install talhelper

```bash
curl -sSfL   https://raw.githubusercontent.com/aquaproj/aqua-installer/v1.0.0/aqua-installer |   bash
export PATH="${AQUA_ROOT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua}/bin:$PATH"
aqua init
aqua generate
aqua g -i cli/cli budimanjojo/talhelper
aqua i
```

## Generate Talos configuration
```bash
./run-talos.sh
```


## Copy talosconfig to homedir
```bash
cp ./clusterconfig/talosconfig ~/.talos/config
```

## Create cluster 
### Apply configuration
```bash 
# Master nodes
talosctl apply-config --insecure --nodes talos-mstr-01.econline.local --file ./clusterconfig/home-cluster-talos-mstr-01.yaml
talosctl apply-config --insecure --nodes talos-mstr-02.econline.local --file ./clusterconfig/home-cluster-talos-mstr-02.yaml
talosctl apply-config --insecure --nodes talos-mstr-03.econline.local --file ./clusterconfig/home-cluster-talos-mstr-03.yaml

# Worker nodes
talosctl apply-config --insecure --nodes talos-wrkr-01.econline.local --file ./clusterconfig/home-cluster-talos-wrkr-01.yaml
talosctl apply-config --insecure --nodes talos-wrkr-02.econline.local --file ./clusterconfig/home-cluster-talos-wrkr-02.yaml
```

### Bootstrap Etcd
```bash
talosctl --talosconfig ./clusterconfig/talosconfig --nodes talos-mstr-01.econline.local bootstrap
```

## Label worker nodes as workers
```bash
kubectl label node talos-wrkr-01 node-role.kubernetes.io/worker=worker
kubectl label node talos-wrkr-02 node-role.kubernetes.io/worker=worker
```


## Install Cilium CNI
All cluster nodes are unavailable until CNI is installed

```bash
kubectl kustomize --enable-helm ./ | kubectl apply -f -
```

talosctl dashboard -n talos-mstr-01,talos-mstr-02,talos-mstr-03,talos-wrkr-01,talos-wrkr-02
kubectl get csr  --sort-by=.metadata.creationTimestamp
kubectl certificate  approve  <csr-id>
