resource "cloudflare_account" "kireque" {
  name              = "kireque-s account"
  type              = "standard"
  enforce_twofactor = false
}
