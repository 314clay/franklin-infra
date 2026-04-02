# franklin-infra

Reusable CI/CD infrastructure for projects deployed to Franklin (home server) via Tailscale + Docker Compose.

## What's included

- **Reusable CI/CD workflow** — test (Postgres 16 + Python/Node) → deploy via Tailscale SSH → health check → deploy tag → ntfy notification
- **Reusable backup workflow** — pg_dump to `~/backups/{db_name}/` with 7-day retention
- **OAuth canary** — weekly test of Tailscale OAuth token exchange
- **Makefile** — deploy, rollback, migrate, logs, backup, restore, status, health
- **Onboard script** — bootstrap any project in ~5 minutes

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

## Makefile commands

| Command | Description |
|---------|-------------|
| `make deploy` | SSH pull + rebuild on Franklin |
| `make rollback` | Checkout a previous deploy tag |
| `make migrate` | Run migrations locally |
| `make migrate-franklin` | Run migrations on Franklin |
| `make migrate-create` | Create new migration files |
| `make logs` | Tail Franklin container logs |
| `make backup` | Manual pg_dump on Franklin |
| `make restore` | Restore from a backup |
| `make status` | Docker compose ps on Franklin |
| `make health` | Curl the health endpoint |
