## :memo:&nbsp; Bootstrap

1. Deploy [flux](https://github.com/fluxcd/flux2) `kubectl apply --server-side --kustomize ./kubernetes/bootstrap`
2. Create flux github secret `sops --decrypt ./kubernetes/bootstrap/github-deploy-key.sops.yaml | kubectl apply -f -`
3. Create sops secret `cat ~/.config/sops/age/keys.txt | kubectl create secret generic sops-age --namespace=flux-system --from-file=age.agekey=/dev/stdin`
4. Apply flux cluster variables `kubectl apply -f ./kubernetes/flux/vars/cluster-settings.yaml`
5. Apply flux cluster secrets `sops --decrypt ./kubernetes/flux/vars/cluster-secrets.sops.yaml | kubectl apply -f -`
6. Apply prometheus CRDs `kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-community/helm-charts/main/charts/kube-prometheus-stack/crds/crd-prometheuses.yaml`
7. Apply flux kustomization `kubectl apply --server-side --kustomize ./kubernetes/flux/config`  