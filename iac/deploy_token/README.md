# Cloudflare deploy token

Issues the Cloudflare API token that `on_pr.yaml` and `on_push_main.yaml` use
to publish the site, writes it into a GitHub Actions environment, and replaces
it on a schedule.

## How the rotation works

```
time_rotating (rotation clock, in state)
      │  rotation date passed → Terraform replaces it
      ▼
cloudflare_account_token          create_before_destroy: new token exists
      │  replace_triggered_by     before the old one is revoked
      ▼
github_actions_environment_secret → CLOUDFLARE_API_TOKEN
```

`.github/workflows/rotate_cloudflare_token.yaml` runs `terraform apply` daily.
Nearly every run is a no-op; the first run after the rotation date is the one
that issues a new token and updates the secret.

Two details do the real work, and both are load-bearing:

- **`replace_triggered_by`** — renaming a Cloudflare token is a PATCH, which
  leaves the secret value untouched. Only replacing the resource issues a new
  credential.
- **The timestamp in the token name** — Cloudflare rejects two tokens sharing a
  name, so without it `create_before_destroy` could not overlap old and new.

The issued token carries an `expires_on` of the rotation date plus
`token_grace_days` (7 by default). A single failed rotation run is therefore
harmless, but a rotation that stays broken ends in a dead token rather than a
live one nobody is watching. Set `token_grace_days = 0` for a non-expiring
token.

## One-time bootstrap

Terraform manages the deploy token, but not the credentials used to mint it —
those are the root of trust and are rotated by hand.

### 1. State bucket

Remote state is mandatory here: without it every scheduled run would mint a
fresh token and orphan the last one.

```sh
npx wrangler r2 bucket create pcc-terraform-state
```

Then create an R2 API token (Cloudflare dashboard → R2 → *Manage API tokens*)
with **Object Read & Write** on that bucket, and keep the Access Key ID and
Secret Access Key it prints.

### 2. Cloudflare bootstrap token

Cloudflare dashboard → *My Profile* → *API Tokens* → custom token, account
scoped to this account:

| Permission | Level |
|---|---|
| Account API Tokens | Edit |
| Cloudflare Pages | Edit |

Pages is needed because Cloudflare will not let a token grant a permission it
does not itself hold.

### 3. GitHub token

A fine-grained PAT (or GitHub App installation) on `aled-owen/pcc-website`:

| Repository permission | Level |
|---|---|
| Metadata | Read |
| Environments | Read and write |

`Environments: write` covers both creating the environment and writing its
secrets.

### 4. GitHub environments

Create `cloudflare-token-rotation` by hand and add the secrets below. The
`cloudflare-pages` environment is created by Terraform on first apply.

| Environment | Name | Kind | Value |
|---|---|---|---|
| `cloudflare-token-rotation` | `TF_CLOUDFLARE_API_TOKEN` | secret | Step 2 |
| `cloudflare-token-rotation` | `TF_GITHUB_TOKEN` | secret | Step 3 |
| `cloudflare-token-rotation` | `TF_STATE_ACCESS_KEY_ID` | secret | Step 1 |
| `cloudflare-token-rotation` | `TF_STATE_SECRET_ACCESS_KEY` | secret | Step 1 |
| `cloudflare-token-rotation` | `CLOUDFLARE_ACCOUNT_ID` | secret | Cloudflare account ID |
| repository | `TF_STATE_BUCKET` | variable | `pcc-terraform-state` |

Restricting `cloudflare-token-rotation` to the `main` branch is worth doing —
it stops a pull request branch from reaching the token-minting credentials.

### 5. First apply

```sh
cd iac/deploy_token

export CLOUDFLARE_API_TOKEN=...        # step 2
export GITHUB_TOKEN=...                # step 3
export AWS_ACCESS_KEY_ID=...           # step 1
export AWS_SECRET_ACCESS_KEY=...       # step 1
export AWS_ENDPOINT_URL_S3="https://<account_id>.r2.cloudflarestorage.com"

terraform init -backend-config="bucket=pcc-terraform-state"
terraform apply -var="cloudflare_account_id=<account_id>"
```

Commit the generated `.terraform.lock.hcl` so CI resolves the same provider
versions. Once this has run, delete the old repository-level
`CLOUDFLARE_API_TOKEN` secret — the environment secret shadows it, so leaving it
in place just keeps an unrotated credential alive.

## Operating it

Rotate immediately (after a suspected leak, say) — *Actions* → *Rotate
Cloudflare token* → *Run workflow* → tick **force**. Or locally:

```sh
terraform apply -replace=time_rotating.deploy_token -var="cloudflare_account_id=<account_id>"
```

Change the cadence with `token_rotation_days`. Note that this only takes effect
at the next rotation: the clock already in state keeps its existing rotation
date.

## Gotchas

- **GitHub disables scheduled workflows after 60 days of repository
  inactivity.** On a site that goes quiet over winter, that silently stops
  rotation, and `expires_on` then takes the deploy token down with it. Either
  re-enable the workflow from the Actions tab when you next push, or set
  `token_grace_days = 0`.
- **Fork pull requests get no secrets**, so preview deploys from forks fail.
  That was already true of the repository-level secrets.
- **The rotation cannot run on the token it issues.** Pointing the workflow at
  `CLOUDFLARE_API_TOKEN` and granting the issued token `Account API Tokens
  Write` looks like it would remove the separate bootstrap credential, but
  Cloudflare rejects the token creation outright:

  ```
  1001: sub-token is not allowed to have permissions to manage other tokens
  ```

  A token minted through the API by another token may never manage tokens
  itself. Only a human-created token (dashboard, or the API with the Global API
  Key) can hold that permission, so the two credentials stay separate and
  `TF_CLOUDFLARE_API_TOKEN` stays hand-rotated.
- **The token value lives in Terraform state.** Treat the R2 bucket as secret
  material: private, and access-keyed to this workflow only.
- There is a brief window during rotation where a workflow that already read the
  secret is still using the previous token. `create_before_destroy` shrinks it
  to the gap between the secret update and the old token's revocation, but it is
  not zero.
