output "token_id" {
  description = "Cloudflare identifier of the token currently in service."
  value       = cloudflare_account_token.pages_deploy.id
}

output "token_name" {
  description = "Name of the token currently in service."
  value       = cloudflare_account_token.pages_deploy.name
}

output "token_expires_on" {
  description = "When the token currently in service stops working."
  value       = coalesce(cloudflare_account_token.pages_deploy.expires_on, "never")
}

output "rotation_due" {
  description = "The first apply on or after this time replaces the token."
  value       = time_rotating.deploy_token.rotation_rfc3339
}

output "github_environment" {
  description = "GitHub Actions environment holding the deploy credentials."
  value       = "${var.github_owner}/${var.github_repository}:${var.github_environment}"
}

output "rotation_github_environment" {
  description = "GitHub Actions environment the rotation workflow reads the same token from."
  value       = "${var.github_owner}/${var.github_repository}:${var.rotation_github_environment}"
}
