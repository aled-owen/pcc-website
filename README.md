# Pembrokeshire Climbing Club Website

Static website hosted on Cloudflare Pages.

## Structure

| Directory | Contents |
|---|---|
| `site/` | Static site contents |
| `iac/` | Terraform for the infrastructure used to host the website |

## Infrastructure

```sh
cd iac && terraform init && terraform apply \
  -var="cloudflare_account_id=<account_id>"
```
