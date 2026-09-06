# The rotation clock. Terraform proposes replacing this resource once the
# rotation timestamp has passed, which is what turns a plain scheduled
# `terraform apply` into a rotation: most runs are a no-op, and the run after
# the rotation date issues a new token.
resource "time_rotating" "deploy_token" {
  rotation_days = var.token_rotation_days
}

# Permission group IDs are account-specific, so look them up by name rather
# than hardcoding opaque hex IDs.
data "cloudflare_account_api_token_permission_groups_list" "available" {
  account_id = var.cloudflare_account_id
}

locals {
  permission_group_ids = {
    for name in var.token_permission_groups :
    name => distinct([
      for group in data.cloudflare_account_api_token_permission_groups_list.available.result :
      group.id if group.name == name
    ])
  }

  unresolved_permission_groups = [
    for name, ids in local.permission_group_ids : name if length(ids) != 1
  ]

  rotation_stamp = formatdate("YYYYMMDD-hhmmss", time_rotating.deploy_token.rfc3339)
}

# Account-owned rather than user-owned, so the deploy credential survives any
# one person leaving and is visible to every account admin.
resource "cloudflare_account_token" "pages_deploy" {
  account_id = var.cloudflare_account_id

  # Cloudflare rejects two tokens sharing a name, so the timestamp is what makes
  # create_before_destroy possible. It also makes the rotation history readable
  # in the dashboard.
  name = "${var.token_name_prefix}-${local.rotation_stamp}"

  policies = [{
    effect = "allow"
    permission_groups = [
      for name in var.token_permission_groups : { id = one(local.permission_group_ids[name]) }
    ]
    resources = jsonencode({
      "com.cloudflare.api.account.${var.cloudflare_account_id}" = "*"
    })
  }]

  # Outliving the rotation date by the grace period means one failed rotation
  # run does not break deploys, while a rotation that stays broken still ends in
  # a dead token rather than a live one nobody is watching.
  expires_on = var.token_grace_days > 0 ? timeadd(
    time_rotating.deploy_token.rotation_rfc3339,
    "${var.token_grace_days * 24}h",
  ) : null

  lifecycle {
    # Mint the replacement before revoking the old token, so a deploy that is
    # already in flight never loses its credential mid-run.
    create_before_destroy = true

    # Without this the rotation is cosmetic: a changed `name` is a PATCH, which
    # leaves the secret value untouched. Only a replacement issues a new one.
    replace_triggered_by = [time_rotating.deploy_token]

    precondition {
      condition     = length(local.unresolved_permission_groups) == 0
      error_message = "No unique Cloudflare permission group matched: ${join(", ", local.unresolved_permission_groups)}. See the token_permission_groups variable for how to list the valid names."
    }
  }
}

resource "github_repository_environment" "deploy" {
  repository  = var.github_repository
  environment = var.github_environment
}

resource "github_actions_environment_secret" "cloudflare_api_token" {
  repository  = github_repository_environment.deploy.repository
  environment = github_repository_environment.deploy.environment
  secret_name = var.api_token_secret_name
  value       = cloudflare_account_token.pages_deploy.value
}

resource "github_actions_environment_secret" "cloudflare_account_id" {
  repository  = github_repository_environment.deploy.repository
  environment = github_repository_environment.deploy.environment
  secret_name = var.account_id_secret_name
  value       = var.cloudflare_account_id
}
