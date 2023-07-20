resource "auth0_email" "mailgun_provider" {
  name    = "mailgun"
  enabled = true

  default_from_address = "kireque authentication <noreply@mg.kireque.dev>"

  credentials {
    domain    = "mg.kireque.dev"
    region    = "eu"
    smtp_port = 0
    api_key   = var.secrets["mailgun"]["api_key"]
  }
}
