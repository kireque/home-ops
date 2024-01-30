module "vyos_config" {
  source = "github.com/bjw-s/terraform-github-repository?ref=v1.2.0"

  name        = "vyos-config"
  description = "My VyOS configuration"
  topics      = ["vyos", "iac"]
  visibility  = "public"

  auto_init              = true
  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_auto_merge       = true
  delete_branch_on_merge = true

  has_issues   = true
  has_wiki     = false
  has_projects = false

  plaintext_secrets = merge(
    {},
    local.kireque_bot_secrets
  )

  issue_labels_manage_default_github_labels = false
  issue_labels = concat(
    [
      { name = "renovate/container", color = "ffc300", description = "Issue relates to a Renovate container update" },
    ],
    local.issue_labels_semver,
    local.issue_labels_category
  )
}
