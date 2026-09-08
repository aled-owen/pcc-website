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

  # Carries the match count, because zero and two are different problems: a
  # wrong name versus a name Cloudflare uses at more than one scope.
  unresolved_permission_groups = [
    for name, ids in local.permission_group_ids :
    "${name} (${length(ids)} matched)" if length(ids) != 1
  ]

  rotation_stamp = formatdate("YYYYMMDD-hhmmss", time_rotating.deploy_token.rfc3339)
}

# Account-owned rather than user-owned, so the deploy credential survives any
# one person leaving and is visible to every account admin.
#
# This token also mints its own successor: the rotation workflow authenticates
# with it, so a replacement is created, written to both environments, and only
# then is the old token revoked. The revocation is the one call made with a
# credential that is about to stop existing — if Cloudflare refuses it the apply
# fails *after* the new token is already in service, and the next run (now
# holding the new token) destroys the leftover.
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
      error_message = "No unique Cloudflare permission group matched: ${join(", ", local.unresolved_permission_groups)}. 0 matched means the name is wrong; 2 or more means Cloudflare publishes it at several scopes and this module cannot tell them apart. See the token_permission_groups variable for how to list the valid names."
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

# The rotation workflow authenticates to Cloudflare with the very token managed
# here, so the value has to be readable from the environment that workflow runs
# in as well. TF_CLOUDFLARE_API_TOKEN stays alongside it as break-glass: it
# seeds the first token carrying the token-minting permission, and recovers a
# rotation that ended without a usable credential.
#
# Only the secret is managed, not the environment — the rotation environment is
# created by hand (see README) and its branch protection is what keeps a pull
# request branch away from these credentials. Terraform must not be able to
# relax that.
resource "github_actions_environment_secret" "rotation_cloudflare_api_token" {
  repository  = var.github_repository
  environment = var.rotation_github_environment
  secret_name = var.api_token_secret_name
  value       = cloudflare_account_token.pages_deploy.value
}
