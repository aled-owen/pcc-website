# Pembrokeshire Climbing Club Website

Static website hosted on Cloudflare Pages.

## Structure

| Directory | Contents |
|---|---|
| `site/` | Static site contents |
| `iac/` | Terraform for the infrastructure used to host the website |
| `.github/` | CI/CD workflows and reusable composite actions |

## CI/CD

Pull requests get a Cloudflare preview deployment. Merging to `main` deploys
`site/` to production. Both read `CLOUDFLARE_API_TOKEN` and
`CLOUDFLARE_ACCOUNT_ID` from the `cloudflare-pages` GitHub Actions environment.

A third workflow rotates that token on a schedule — see
[`iac/deploy_token/`](iac/deploy_token/README.md).

## Infrastructure

Two Terraform root modules:

| Module | Manages | State |
|---|---|---|
| [`iac/deploy_site/`](iac/deploy_site) | Cloudflare Pages project and custom domain | Local |
| [`iac/deploy_token/`](iac/deploy_token) | The rotating Pages deploy token and the GitHub environment holding it | Remote (R2) |

```sh
cd iac/deploy_site && terraform init && terraform apply \
  -var="cloudflare_account_id=<account_id>"
```

`deploy_token` is applied by CI on a schedule; its one-time bootstrap is
documented in [its README](iac/deploy_token/README.md).
