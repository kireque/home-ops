resource "cloudflare_account" "bjw_s" {
  name              = "kireque's Account"
  type              = "standard"
  enforce_twofactor = false
}
