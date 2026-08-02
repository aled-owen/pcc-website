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

Every page uses a CSS Grid layout defined on `.wrapper` with three named areas: `header` (nav bar), `border` (left decorative column), and `content` (main body), plus `footer`. On mobile (`max-width: 700px`) the grid collapses to a single column and the border column is hidden with `display: none`.

### CSS Files (`site/css/`)

| File | Contents |
|---|---|
| `style.css` | Entry point — `@import`s all other files |
| `base.css` | Google Fonts import, global reset |
| `layout.css` | Page grid, grid-area assignments, footer structure |
| `nav.css` | Nav bar, links (desktop inline row) |
| `hamburger.css` | CSS-only hamburger toggle — mobile only |
| `components.css` | Decorative border images, splash image |
| `responsive.css` | All mobile overrides (`max-width: 700px`) |

### Splash Image Overlay

`.splash-image` uses `grid-column: 1 / -1; grid-row: 2` to span both columns in row 2, overlapping `.main-content`. A `.splash-image-block` spacer (350px tall) inside `.main-content` pushes text below the image. Mobile uses `grid-template-rows: auto 1fr auto` so the content row absorbs spare viewport height rather than inflating the nav row.

### CSS-only Hamburger Menu (`hamburger.css`)

The nav toggle is **mobile-only** (`max-width: 700px`); desktop shows the links as an inline row. It uses no JavaScript: an `<input type="checkbox" id="menu-btn">` paired with a `<label for="menu-btn">` (the visible bars icon). The checkbox, label and `.nav-list` are siblings inside `.primary-nav`, so `.menu-btn:checked` restyles both — morphing the bars into an X and revealing the list, which drops beneath the bar as a full-width overlay via a `max-height` transition.

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

Two workflows, both calling shared composite actions in `.github/actions/`:

| Workflow | Trigger | Jobs |
|---|---|---|
| `on_pr.yaml` | Pull request opened/updated | `lint` (pre-commit) + `publish-preview` (Cloudflare preview) |
| `on_release.yaml` | Release published | `publish` (Cloudflare production) |

Deployment uses `cloudflare/wrangler-action@v3`. Required repository secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.

## Infrastructure (`iac/`)

Terraform with the Cloudflare provider (`~> 4.0`) manages the Cloudflare Pages project. Key variables: `cloudflare_api_token`, `cloudflare_account_id`, `project_name` (default: `pcc-website`), `production_branch` (default: `main`).

```
cd iac && terraform init && terraform apply
```
