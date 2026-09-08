variable "cloudflare_account_id" {
  description = "Cloudflare account ID that owns the Pages project and the issued token."
  type        = string
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repository."
  type        = string
  default     = "aled-owen"
}

variable "github_repository" {
  description = "Repository whose Actions environment receives the deploy credentials."
  type        = string
  default     = "pcc-website"
}

variable "github_environment" {
  description = "GitHub Actions environment the deploy credentials are written to."
  type        = string
  default     = "cloudflare-pages"
}

variable "rotation_github_environment" {
  description = <<-EOT
    Environment the rotation workflow runs in. The issued token is written here
    as well, because that workflow now authenticates with it rather than with
    the bootstrap credential. Created by hand, not by Terraform.
  EOT
  type        = string
  default     = "cloudflare-token-rotation"
}

variable "api_token_secret_name" {
  description = "Environment secret holding the issued Cloudflare token."
  type        = string
  default     = "CLOUDFLARE_API_TOKEN"
}

variable "account_id_secret_name" {
  description = "Environment secret holding the Cloudflare account ID."
  type        = string
  default     = "CLOUDFLARE_ACCOUNT_ID"
}

variable "token_name_prefix" {
  description = "Prefix for the issued token's name. A rotation timestamp is appended."
  type        = string
  default     = "pcc-website-pages-deploy"
}

variable "token_permission_groups" {
  description = <<-EOT
    Cloudflare permission group names granted to the issued token. These are the
    API names, which differ from the dashboard labels — "Cloudflare Pages: Edit"
    in the dashboard is "Pages Write" here, and "Account API Tokens: Edit" is
    "API Tokens Write". List the valid names with:

      curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "https://api.cloudflare.com/client/v4/accounts/<account_id>/tokens/permission_groups"

    "API Tokens Write" is what lets the token replace itself, and so what lets
    the rotation workflow run on the issued credential instead of the bootstrap
    one. It is also a genuine widening: this is the same value pull request
    preview deploys use, so anything able to read the cloudflare-pages
    environment can now mint account tokens. To undo, drop it and point
    rotate_cloudflare_token.yaml back at TF_CLOUDFLARE_API_TOKEN.
  EOT
  type        = list(string)
  default     = ["Pages Write", "Account API Tokens Write"]

  validation {
    condition     = length(var.token_permission_groups) > 0
    error_message = "At least one permission group is required, otherwise the token can do nothing."
  }
}

variable "token_rotation_days" {
  description = "How long an issued token stays in service before the next apply replaces it."
  type        = number
  default     = 30

  validation {
    condition     = var.token_rotation_days >= 1
    error_message = "Rotation period must be at least one day."
  }
}

variable "token_grace_days" {
  description = <<-EOT
    Days beyond the rotation date that the issued token remains valid. This is
    the cushion for a rotation run that fails or is missed; set it to 0 to issue
    a non-expiring token instead.
  EOT
  type        = number
  default     = 7

  validation {
    condition     = var.token_grace_days >= 0
    error_message = "Grace period cannot be negative."
  }
}
