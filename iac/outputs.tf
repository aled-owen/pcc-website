output "site_url" {
  description = "Cloudflare Pages production URL."
  value       = "https://${cloudflare_pages_project.site.subdomain}"
}
