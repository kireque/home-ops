module "cf_domain_ingress" {
  source     = "./modules/cf_domain"
  domain     = module.onepassword_item_cloudflare.fields["domain_name"]
  account_id = cloudflare_account.kireque.id
  dns_entries = [
    {
      name  = "ipv4"
      value = local.home_ipv4
    },
    {
      id      = "vpn"
      name    = module.onepassword_item_cloudflare.fields["vpn-subdomain"]
      value   = "ipv4.${module.onepassword_item_cloudflare.fields["domain_name"]}"
      type    = "CNAME"
      proxied = false
    },
    {
      name    = "authelia"
      value   = "ipv4.${module.onepassword_item_cloudflare.fields["domain_name"]}"
      type    = "CNAME"
    },
    {
      name    = "files-cees"
      value   = "ipv4.${module.onepassword_item_cloudflare.fields["domain_name"]}"
      type    = "CNAME"
    },
    {
      name    = "sabnzbd-cees"
      value   = "ipv4.${module.onepassword_item_cloudflare.fields["domain_name"]}"
      type    = "CNAME"
    },
    # Generic settings
    {
      name  = "_dmarc"
      value = "v=DMARC1; p=quarantine; adkim=s; aspf=s"
      type  = "TXT"
    },
    # E-mail settings
    {
      id       = "google_mx_1"
      name     = "@"
      priority = 200
      value    = "aspmx2.googlemail.com"
      type     = "MX"
    },
    {
      id       = "google_mx_2"
      name     = "@"
      priority = 200
      value    = "alt2.aspmx.l.google.com"
      type     = "MX"
    },
    {
      id       = "google_mx_3"
      name     = "@"
      priority = 20
      value    = "alt1.aspmx.l.google.com"
      type     = "MX"
    },
    {
      id       = "google_mx_4"
      name     = "@"
      priority = 10
      value    = "aspmx.l.google.com"
      type     = "MX"
    },
    {
      id    = "google_spf"
      name  = "@"
      value = "v=spf1 include:_spf.google.com ~all"
      type  = "TXT"
    },
    {
      id    = "google_domainkey"
      name  = "google._domainkey"
      value = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAr1cm2+o7jB3WGXZbIqPHnlXzaIP+mP0zrFiNDszrOeCL0CFgRr7SIgwjpI6lA9jrgeWMY3gdIDfdBMzwL1H1H82F0sul/ddFLT6lR7IstF6PPpGo/1hkDMqSLS0G0D/6KIfpdoh+whlhXH9bg4iwtc4kzeyj7A02f4ApUTLS3OKVfx03LU5OUJrEL8ka4Tt7vz/y5+6tloeLn4if49JpyEWFrSuIgfPYbLKsykBFYzcAPFQgKKWljRCd1uFsotGn+9mBOACrTODkz1vaaWJc94JXWVwuWhBhJ104d0Ya/11+dg6RLlL4hx1ThTF1IAYo3fQdpTklX8cCAEDCIQawoQIDAQAB"
      type  = "TXT"
    }
  ]

  waf_custom_rules = [
    {
      enabled     = true
      description = "Expression to allow UptimeRobot IP addresses"
      expression  = "(http.user_agent contains \"UptimeRobot/2.0\" and ip.src in $uptimerobot)"
      action      = "skip"
      action_parameters = {
        ruleset = "current"
      }
      logging = {
        enabled = false
      }
    },
    {
      enabled     = true
      description = "Allow GitHub flux API"
      expression  = "ip.geoip.asnum eq 36459 and http.user_agent contains \"GitHub-Hookshot\" and http.host eq \"flux-receiver-main.${module.onepassword_item_cloudflare.fields["domain_name"]}\""
      action      = "skip"
      action_parameters = {
        ruleset = "current"
      }
      logging = {
        enabled = false
      }
    },
    {
      enabled     = true
      description = "Firewall rule to block bots and threats determined by CF"
      expression  = "(cf.client.bot) or (cf.threat_score gt 14)"
      action      = "block"
    },
    {
      enabled     = false
      description = "Expression to allow Shields.io"
      expression  = "(http.user_agent contains \"Shields.io\" and http.host eq \"kromgo.econline.nl\")"
      action      = "skip"
      action_parameters = {
        ruleset = "current"
      }
      logging = {
        enabled = false
      }
    },
    {
      enabled     = true
      description = "Firewall rule to block all countries except NL/BE/DE"
      expression  = "(ip.geoip.country ne \"NL\") and (ip.geoip.country ne \"BE\") and (ip.geoip.country ne \"DE\")"
      action      = "block"
    }
  ]
}
