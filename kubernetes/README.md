## :memo:&nbsp; Bootstrap

3. Deploy [flux](https://github.com/fluxcd/flux2) `kubectl apply --server-side --kustomize ./kubernetes/bootstrap`
4. Create flux github secret `sops --decrypt ./kubernetes/bootstrap/github-deploy-key.sops.yaml | kubectl apply -f -`
5. Create sops secret `cat ~/.config/sops/age/keys.txt | kubectl create secret generic sops-age --namespace=flux-system --from-file=age.agekey=/dev/stdin`
6. Apply flux cluster variables `kubectl apply -k ./kubernetes/flux/vars/cluster-settings.yaml`
6. Apply flux cluster secrets `sops --decrypt ./kubernetes/flux/vars/cluster-secrets.sops.yaml | kubectl apply -f -`
7. Apply prometheus CRDs `kubectl apply -f https://raw.githubusercontent.com/prometheus-community/helm-charts/main/charts/kube-prometheus-stack/crds/crd-prometheuses.yaml`
7. Apply flux kustomization `kubectl apply --server-side --kustomize ./kubernetes/flux/config`  