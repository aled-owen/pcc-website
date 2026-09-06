terraform {
  # 1.10 is the first release with native S3 state locking (`use_lockfile`).
  required_version = ">= 1.10"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.19"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}

# Credentials are read from CLOUDFLARE_API_TOKEN.
provider "cloudflare" {}

# Credentials are read from GITHUB_TOKEN.
provider "github" {
  owner = var.github_owner
}
