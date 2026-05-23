resource "cloudflare_pages_project" "site" {
  account_id        = var.cloudflare_account_id
  name              = var.project_name
  production_branch = var.production_branch
}

resource "cloudflare_pages_domain" "site_domain" {
  account_id = var.cloudflare_account_id
  project_name = var.project_name
  name = "pembrokeshireclimbingclub.co.uk"

  depends_on = [
    cloudflare_pages_project.site
  ]
}
