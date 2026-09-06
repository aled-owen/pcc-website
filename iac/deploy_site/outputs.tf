output "site_url" {
  description = "Cloudflare Pages production URL."
  value       = "https://${cloudflare_pages_project.site.subdomain}"
}

# The deploy workflow passes these to wrangler as literals. They are exposed
# here so the values it must match have a single documented source.
output "project_name" {
  description = "Pages project name to deploy into."
  value       = cloudflare_pages_project.site.name
}

output "production_branch" {
  description = "Branch name that makes a wrangler deploy a production deploy."
  value       = cloudflare_pages_project.site.production_branch
}
