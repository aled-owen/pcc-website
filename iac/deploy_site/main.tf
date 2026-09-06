# Deliberately a direct-upload project: there is no `source` block, so
# Cloudflare does not watch the repository. GitHub Actions owns the deploy
# trigger (.github/workflows/on_push_main.yaml) and uploads ./site/ with
# wrangler, authenticating with the rotating token issued by iac/deploy_token.
# Adding a `source` block here would move the trigger to Cloudflare's Git
# integration and leave that token unused.
resource "cloudflare_pages_project" "site" {
  account_id = var.cloudflare_account_id
  name       = var.project_name

  # wrangler publishes to production only when it deploys with `--branch` equal
  # to this value. Anything else lands as a preview, which is what keeps pull
  # request deploys off the live site.
  production_branch = var.production_branch
}

resource "cloudflare_pages_domain" "site_domain" {
  account_id = var.cloudflare_account_id
  name       = "pembrokeshireclimbingclub.co.uk"

  # Referencing the project rather than var.project_name gives Terraform the
  # real dependency edge, so no explicit depends_on is needed.
  project_name = cloudflare_pages_project.site.name
}
