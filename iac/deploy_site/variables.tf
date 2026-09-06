variable "cloudflare_account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "project_name" {
  description = "Cloudflare Pages project name."
  type        = string
  default     = "pcc-website"
}

variable "production_branch" {
  description = "Git branch deployed to production."
  type        = string
  default     = "main"
}
