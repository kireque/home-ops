locals {
  networks = yamldecode(chomp(data.http.kireque_common_networks.response_body))
}
