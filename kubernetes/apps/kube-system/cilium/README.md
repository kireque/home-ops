# Cilium

## UniFi BGP

```sh
router bgp 64513
  bgp router-id 10.1.0.1
  no bgp ebgp-requires-policy

  neighbor k8s peer-group
  neighbor k8s remote-as 64514

  neighbor 10.1.1.31 peer-group k8s
  neighbor 10.1.1.32 peer-group k8s
  neighbor 10.1.1.33 peer-group k8s

  ! gladius FRR announces the docker apps IP 10.1.6.21/32 (docker/gladius/00-frr)
  neighbor 10.1.1.11 remote-as 64515

  address-family ipv4 unicast
    neighbor k8s next-hop-self
    neighbor k8s soft-reconfiguration inbound
  exit-address-family
exit

```
