provider "unifi" {
  alias = "home"

  username       = module.onepassword_item_unifi_controller.fields.username
  password       = module.onepassword_item_unifi_controller.fields.password
  api_url        = "https://10.5.0.10:8443"
  allow_insecure = true
}
