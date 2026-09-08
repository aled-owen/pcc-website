# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Static HTML/CSS website for Pembrokeshire Climbing Club. No build tools, no JavaScript framework, no package manager — open files directly in a browser to preview.

## Development

To preview locally, open any `.html` file in a browser from the `site/` directory. There is no build step, server, or dependency installation required.

Pre-commit hooks run Biome formatting checks. Install with:
```
pip install pre-commit && pre-commit install
```

## Repository Structure

```
site/          Static site — HTML, CSS, images
iac/           Terraform for Cloudflare Pages infrastructure
.github/
  actions/     Reusable composite actions
  workflows/   CI/CD workflows
```

## Site Architecture

### Page Layout

Every page uses a CSS Grid layout defined on `.wrapper` with three named areas: `header` (nav bar), `border` (left decorative column), and `content` (main body), plus `footer`. On mobile (`max-width: 48em`) the grid collapses to a single column and the border column is hidden with `display: none`.

### CSS Files (`site/css/`)

| File | Contents |
|---|---|
| `style.css` | Entry point — `@import`s all other files |
| `base.css` | Google Fonts import, global reset |
| `layout.css` | Page grid, grid-area assignments, footer structure |
| `nav.css` | Nav bar, links (desktop inline row) |
| `hamburger.css` | CSS-only hamburger toggle — mobile only |
| `components.css` | Decorative border images, splash image |
| `responsive.css` | All mobile overrides (`max-width: 48em`) |

### Splash Image Overlay

`.splash-image` uses `grid-column: 1 / -1; grid-row: 2` to span both columns in row 2, overlapping `.main-content`. A `.splash-image-block` spacer (350px tall) inside `.main-content` pushes text below the image. Mobile uses `grid-template-rows: auto 1fr auto` so the content row absorbs spare viewport height rather than inflating the nav row.

### CSS-only Hamburger Menu (`hamburger.css`)

The nav toggle is **mobile-only** (`max-width: 48em`); desktop shows the links as an inline row. It uses no JavaScript: an `<input type="checkbox" id="menu-btn">` paired with a `<label for="menu-btn">` (the visible bars icon). The checkbox, label and `.nav-list` are siblings inside `.primary-nav`, so `.menu-btn:checked` restyles both — morphing the bars into an X and revealing the list, which drops beneath the bar as a full-width overlay via a `max-height` transition.

Accessibility details:
- On mobile the checkbox is *visually hidden but kept in the accessibility tree / tab order* (clipped, not `display:none`), so it stays keyboard-operable; on desktop the whole toggle is `display:none`.
- A visually-hidden `<span class="sr-only">Menu</span>` inside the label gives the checkbox its accessible name; its checked/unchecked state signals open/closed. (Limitation of the CSS-only approach: it is announced as a *checkbox*, not a button with `aria-expanded`, and there is no Escape-to-close.)
- The closed list is `visibility: hidden`, keeping its links out of the tab order until opened.
- Animations are disabled under `prefers-reduced-motion`.
- `.sr-only` is a global visually-hidden utility in `base.css`.

## Brand

- PCC Blue: `#00a3cd`
- PCC Grey: `#cdcdcd`
- Font: Arvo (Google Fonts), falls back to serif

## Pages

| File | Status |
|---|---|
| `site/index.html` | Home page |
| `site/join_us.html` | Join page (stub — missing shared nav/styles) |
| `members.html` | Linked in nav, not yet created |
| `contact_us.html` | Linked in nav, not yet created |

## CI/CD

Three workflows; the deploy workflows call shared composite actions in `.github/actions/`:

| Workflow | Trigger | Jobs |
|---|---|---|
| `on_pr.yaml` | Pull request opened/updated | `lint` (pre-commit) + `publish-preview` (Cloudflare preview) |
| `on_push_main.yaml` | Push to `main` + manual | `publish` (Cloudflare production) |
| `rotate_cloudflare_token.yaml` | Daily cron + manual | `rotate` (applies `iac/deploy_token`) |

Deployment uses `cloudflare/wrangler-action@v3` against a direct-upload Pages project — Cloudflare's Git integration is deliberately not used, so the deploy trigger lives in GitHub Actions. Both deploy jobs declare `environment: cloudflare-pages` and read `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` from that environment, not from repository secrets.

The rotation job runs under the separate `cloudflare-token-rotation` environment, which holds `TF_GITHUB_TOKEN`, `TF_STATE_ACCESS_KEY_ID`, `TF_STATE_SECRET_ACCESS_KEY`, `CLOUDFLARE_ACCOUNT_ID` and the break-glass `TF_CLOUDFLARE_API_TOKEN`, plus the repository variable `TF_STATE_BUCKET`. Those are rotated by hand.

Cloudflare authentication for that job is the rotated token itself: Terraform writes `CLOUDFLARE_API_TOKEN` into this environment as well as `cloudflare-pages`, and the job reads it from there. `TF_CLOUDFLARE_API_TOKEN` is only reached via the workflow's `bootstrap` input — for the first apply, and to recover when the issued token is dead and cannot log in to replace itself.

## Infrastructure (`iac/`)

Two Terraform root modules, both on the Cloudflare provider `~> 5.19`.

### `deploy_site/`

Manages the Cloudflare Pages project and its custom domain. Local state. Variables: `cloudflare_account_id`, `project_name` (default: `pcc-website`), `production_branch` (default: `main`).

The project has no `source` block, which is deliberate — it is a direct-upload project, so `on_push_main.yaml` owns the deploy trigger and uploads `site/` with wrangler. Adding a `source` block would hand the trigger to Cloudflare's Git integration and leave the rotating token unused.

`production_branch` is load-bearing for the deploy: wrangler only files an upload as a production deployment when its `--branch` matches this value. `on_push_main.yaml` passes `main` literally, and `outputs.tf` exposes `project_name` / `production_branch` so those literals have a documented source.

```
cd iac/deploy_site && terraform init && terraform apply
```

### `deploy_token/`

Issues the Pages deploy token, writes it to the `cloudflare-pages` GitHub environment, and rotates it. Remote state in Cloudflare R2 via the S3 backend (`bucket` passed at init, endpoint from `AWS_ENDPOINT_URL_S3`) — local state would mint a new token every scheduled run.

Rotation chain: `time_rotating` (rotation clock in state) → `cloudflare_account_token` → `github_actions_environment_secret`. Two lifecycle settings are load-bearing:

- `replace_triggered_by = [time_rotating.deploy_token]` — a changed token `name` is only a PATCH, so without forced replacement the value never changes.
- `create_before_destroy` — needs the rotation timestamp in the token name, since Cloudflare rejects duplicate token names.

Permission groups are resolved by API name (`Pages Write`, not the dashboard's "Cloudflare Pages: Edit") through `cloudflare_account_api_token_permission_groups_list`, with a precondition that fails loudly on an unmatched name.

The issued token also carries `API Tokens Write` (the dashboard's "Account API Tokens: Edit"), which is what lets the rotation run on the token it manages — the apply mints the successor, updates both environment secrets, then revokes the credential it is authenticated with as its last call. A refused revocation fails the apply with the new token already live, and the next run cleans up the orphan. The cost is that the token used by PR preview deploys can mint account tokens; dropping the permission and pointing the workflow back at `TF_CLOUDFLARE_API_TOKEN` reverses it.

Full bootstrap and operational notes: `iac/deploy_token/README.md`.
