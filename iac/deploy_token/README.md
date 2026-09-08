# Cloudflare deploy token

Issues the Cloudflare API token that `on_pr.yaml` and `on_push_main.yaml` use
to publish the site, writes it into the GitHub Actions environments that need
it, and replaces it on a schedule. The rotation itself runs on that same token —
it mints its own successor.

## How the rotation works

```
time_rotating (rotation clock, in state)
      │  rotation date passed → Terraform replaces it
      ▼
cloudflare_account_token          create_before_destroy: new token exists
      │  replace_triggered_by     before the old one is revoked
      ▼
github_actions_environment_secret → CLOUDFLARE_API_TOKEN, written to both
                                    cloudflare-pages (deploys) and
                                    cloudflare-token-rotation (this workflow)
```

`.github/workflows/rotate_cloudflare_token.yaml` runs `terraform apply` daily.
Nearly every run is a no-op; the first run after the rotation date is the one
that issues a new token and updates the secret.

The workflow authenticates with `CLOUDFLARE_API_TOKEN` — the credential this
module manages — not with the bootstrap token. That is why the issued token
carries `API Tokens Write` as well as `Pages Write`: it has to be able to create
its replacement and revoke itself. The bootstrap token is still required, but
only for the first apply and for recovery; see [Break-glass](#break-glass).

Two details do the real work, and both are load-bearing:

- **`replace_triggered_by`** — renaming a Cloudflare token is a PATCH, which
  leaves the secret value untouched. Only replacing the resource issues a new
  credential.
- **The timestamp in the token name** — Cloudflare rejects two tokens sharing a
  name, so without it `create_before_destroy` could not overlap old and new.

Because the old token is revoked *last*, a rotating apply spends its final
Cloudflare call deleting the credential it is authenticated with. If that call
is refused, the apply fails with the new token already minted and both secrets
already updated — deploys are fine, and the next run, now holding the new token,
destroys the leftover. A rotation failure therefore leaves a live credential and
an orphan, never a dead one.

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

Both are needed because Cloudflare will not let a token grant a permission it
does not itself hold, and the issued token now carries both itself.

This credential is only used for the bootstrap apply and for recovery — the
scheduled runs use the token Terraform issues.

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

Terraform adds one more to `cloudflare-token-rotation` on first apply:
`CLOUDFLARE_API_TOKEN`, the same issued token the deploy environment gets. That
is what subsequent scheduled runs authenticate with. The environment itself is
left unmanaged so Terraform cannot loosen its branch protection.

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

### Break-glass

The scheduled run authenticates with the token in state, so if that token is
gone — expired after a long rotation outage, revoked by hand, or left dead by a
failed apply — the workflow can no longer log in to fix itself. Recover with
*Actions* → *Rotate Cloudflare token* → *Run workflow* → tick **bootstrap**,
which switches that run onto `TF_CLOUDFLARE_API_TOKEN`. Tick **force** as well
to replace the token rather than adopt whatever is in state.

The same tick is needed once when adopting this arrangement, because the token
currently in service predates the `API Tokens Write` permission and so cannot
mint its own replacement. Run it with **bootstrap** and **force** together, and
every run after that can go back to the issued credential.

## Gotchas

- **GitHub disables scheduled workflows after 60 days of repository
  inactivity.** On a site that goes quiet over winter, that silently stops
  rotation, and `expires_on` then takes the deploy token down with it. Since the
  rotation now signs in with that same token, recovering from this needs a
  break-glass run rather than just re-enabling the schedule. Either re-enable
  the workflow from the Actions tab when you next push, or set
  `token_grace_days = 0`.
- **The deploy token can mint account tokens.** `API Tokens Write` is what makes
  it able to replace itself, but the same value sits in `cloudflare-pages` for
  pull request previews, so a leak there is no longer limited to Pages. Keeping
  a separate, unrotated credential for the rotation job — the previous
  arrangement — is the trade being made here.
- **Fork pull requests get no secrets**, so preview deploys from forks fail.
  That was already true of the repository-level secrets.
- **The token value lives in Terraform state.** Treat the R2 bucket as secret
  material: private, and access-keyed to this workflow only.
- There is a brief window during rotation where a workflow that already read the
  secret is still using the previous token. `create_before_destroy` shrinks it
  to the gap between the secret update and the old token's revocation, but it is
  not zero.
