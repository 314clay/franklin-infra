# franklin-infra

Reusable CI/CD infrastructure for projects deployed to Franklin (home server) via Tailscale + Docker Compose.

## What's included

- **Reusable CI/CD workflow** — test (Postgres 16 + Python/Node) → deploy via Tailscale SSH → DB existence check → migrations → health check → deploy tag → ntfy notification
- **Reusable backup workflow** — pg_dump to `~/backups/{db_name}/` with 7-day retention
- **OAuth canary** — weekly test of Tailscale OAuth token exchange
- **Shared infrastructure** — dnsmasq (DNS) + Caddy (reverse proxy) for short `*.f` URLs across the tailnet
- **Branch deploys** — `make deploy-branch BRANCH=staging` for preview environments at `<project>-<branch>.f`
- **Makefile** — deploy, rollback, migrate, logs, backup, restore, status, health, branch deploy/teardown
- **Onboard script** — bootstrap any project in ~5 minutes with automatic port allocation

## Quick start

```bash
# 1. Clone this repo
git clone git@github.com:ericcarnold/franklin-infra.git

# 2. Install dependencies (macOS + Franklin)
./scripts/install-deps.sh
ssh franklin "./franklin-infra/scripts/install-deps.sh"

# 3. Onboard a project
./scripts/onboard.sh ~/p/my-project

# 4. Edit .infra.yml and workflow files, set secrets, push
```

## Per-project config (`.infra.yml`)

```yaml
project:
  name: cat-tracker
  port: "3099"
  db_name: cat_tracker
  health_endpoint: /api/state
  health_url: https://cattracks.claypersonalprojects.cc/api/state
  test_command: python test_cat_tracker.py
  deploy_path: ~/cat-tracker
  runtime: python
```

## Required GitHub secrets

Set per-repo (personal account, no org-level secrets):

| Secret | Description |
|--------|-------------|
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client ID |
| `TS_OAUTH_SECRET` | Tailscale OAuth client secret |
| `FRANKLIN_SSH_KEY` | SSH private key for Franklin |
| `NTFY_TOPIC` | ntfy.sh topic for notifications (optional) |

## Optional workflow inputs

Both `ci-cd.yml` and `backup.yml` accept these optional inputs to override defaults:

| Input | Default | Description |
|-------|---------|-------------|
| `franklin_host` | `100.112.120.2` | Tailscale IP of the deploy target |
| `franklin_user` | `clayarnold` | SSH user on the deploy target |
| `health_timeout` | `15` | Timeout in seconds for the health check curl (CI/CD only) |

## Deploy safety checks

- **DB existence check** — before running migrations, the CI/CD workflow verifies the target database exists on Franklin (port 5433). If missing, the deploy fails early with a clear error message.
- **Rollback tag validation** — `make rollback` now confirms the entered tag exists before attempting checkout.

## Makefile commands

| Command | Description |
|---------|-------------|
| `make deploy` | SSH pull + rebuild on Franklin |
| `make rollback` | Checkout a previous deploy tag (validates tag exists) |
| `make migrate` | Run migrations locally |
| `make migrate-franklin` | Run migrations on Franklin |
| `make migrate-create` | Create new migration files |
| `make logs` | Tail Franklin container logs |
| `make backup` | Manual pg_dump on Franklin |
| `make restore` | Restore from a backup |
| `make status` | Docker compose ps on Franklin |
| `make health` | Curl the health endpoint |
| `make deploy-branch BRANCH=x` | Deploy a branch to `<project>-x.f` |
| `make teardown-branch BRANCH=x` | Remove a branch deploy |

## Shared infrastructure (dnsmasq + Caddy)

Franklin runs dnsmasq and Caddy as shared services to provide short `*.f` URLs:

- **dnsmasq** — resolves all `*.f` → Franklin's Tailscale IP (`100.112.120.2`)
- **Caddy** — reverse proxies `<name>.f:80` → `localhost:<port>`
- **Tailscale split DNS** — all tailnet devices query Franklin for `.f` domains

### URLs

| URL | What |
|-----|------|
| `http://questionnaire.f` | questionnaire on port 3099 |
| `http://cattracks.f` | cat-tracker on port 3100 |
| `http://questionnaire-staging.f` | questionnaire staging branch |

### Managing shared infra

From the franklin-infra repo root:

```bash
make infra-deploy    # Pull + start dnsmasq and Caddy on Franklin
make infra-status    # Check container status
make infra-logs      # Tail dnsmasq + Caddy logs
make caddy-reload    # Pull config changes and reload Caddy
make gen-caddyfile   # Regenerate Caddyfile from ports.txt
```

### Port registry (`infra/ports.txt`)

Single source of truth for port allocation. Format: `<name> <port>`, one per line. New projects get the next available port automatically via `onboard.sh`. The Caddyfile is generated from this file — never edit the Caddyfile by hand.

### First-time setup

1. Ensure port 53 is free on Franklin (`sudo ss -tulnp | grep :53`). If systemd-resolved is using it:
   ```bash
   # On Franklin:
   sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
   sudo systemctl restart systemd-resolved
   ```
2. Ensure port 80 is free (`sudo ss -tulnp | grep :80`)
3. Deploy: `make infra-deploy`
4. Verify: `dig questionnaire.f @127.0.0.1` should return `100.112.120.2`
5. Configure Tailscale split DNS: Admin Console → DNS → add split DNS entry: domain `f`, nameserver `100.112.120.2`
6. Verify from any tailnet device: `curl http://questionnaire.f`

## Branch deploys

Deploy any branch to a preview URL:

```bash
# From your project directory:
make deploy-branch BRANCH=staging
# → deploys to http://questionnaire-staging.f

make teardown-branch BRANCH=staging
# → removes everything
```

Branch deploys automatically:
- Allocate a port in `ports.txt`
- Clone the branch to a separate directory on Franklin
- Generate a `docker-compose.override.yml` with the branch port
- Regenerate the Caddyfile and reload Caddy
- Commit and push the config changes to franklin-infra
