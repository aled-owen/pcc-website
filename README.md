# Pembrokeshire Climbing Club Website

Static website hosted on Cloudflare Pages.

## Structure

| Directory | Contents |
|---|---|
| `site/` | Static site contents |
| `iac/` | Terraform for the infrastructure used to host the website |
| `.github/` | CI/CD workflows and reusable composite actions |

## CI/CD

Pull requests get a Cloudflare preview deployment. Publishing a release deploys
to production.

Requires repository secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.

## Infrastructure


```sh
cd iac && terraform init && terraform apply \
  -var="cloudflare_account_id=<account_id>"
```
