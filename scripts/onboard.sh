#!/usr/bin/env bash
set -euo pipefail

# Onboard a project to use franklin-infra
# Usage: ./scripts/onboard.sh /path/to/project

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../template"

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <project-path>"
  echo "Example: $0 ~/p/my-project"
  exit 1
fi

PROJECT_DIR="$(cd "$1" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../infra"
PORTS_FILE="$INFRA_DIR/ports.txt"

echo "Onboarding: $PROJECT_DIR"

# Copy template files
[ ! -f "$PROJECT_DIR/.infra.yml" ] && cp "$TEMPLATE_DIR/.infra.yml" "$PROJECT_DIR/.infra.yml"
[ ! -f "$PROJECT_DIR/Makefile" ] && cp "$TEMPLATE_DIR/Makefile" "$PROJECT_DIR/Makefile"
mkdir -p "$PROJECT_DIR/.github/workflows"
cp "$TEMPLATE_DIR/.github/workflows/ci-cd.yml" "$PROJECT_DIR/.github/workflows/ci-cd.yml"
cp "$TEMPLATE_DIR/.github/workflows/backup.yml" "$PROJECT_DIR/.github/workflows/backup.yml"

# Create migrations directory
mkdir -p "$PROJECT_DIR/migrations"

# If schema.sql exists, create initial migration from it
if [ -f "$PROJECT_DIR/schema.sql" ]; then
  echo "Found schema.sql — creating initial migration"
  cp "$PROJECT_DIR/schema.sql" "$PROJECT_DIR/migrations/000001_initial.up.sql"
  echo "-- WARNING: This drops all tables. Use with caution." > "$PROJECT_DIR/migrations/000001_initial.down.sql"
  echo "-- Add DROP TABLE statements here" >> "$PROJECT_DIR/migrations/000001_initial.down.sql"
else
  echo "  ⚠ [WARN] No schema.sql found in $PROJECT_DIR — skipping initial migration creation"
fi

# --- Port allocation ---
PROJECT_NAME=$(yq '.project.name' "$PROJECT_DIR/.infra.yml")

if grep -q "^${PROJECT_NAME} " "$PORTS_FILE" 2>/dev/null; then
  ASSIGNED_PORT=$(grep "^${PROJECT_NAME} " "$PORTS_FILE" | awk '{print $2}')
  echo "Port already assigned: $ASSIGNED_PORT"
else
  MAX_PORT=$(grep -v '^#' "$PORTS_FILE" | grep -v '^$' | awk '{print $2}' | sort -n | tail -1)
  NEXT_PORT=$(( ${MAX_PORT:-3099} + 1 ))
  echo "${PROJECT_NAME} ${NEXT_PORT}" >> "$PORTS_FILE"
  ASSIGNED_PORT=$NEXT_PORT
  echo "Assigned port: $ASSIGNED_PORT"
fi

# Update .infra.yml with assigned port
yq -i ".project.port = \"${ASSIGNED_PORT}\"" "$PROJECT_DIR/.infra.yml"

# Regenerate Caddyfile
"$SCRIPT_DIR/gen-caddyfile.sh"

# Set GitHub secrets from Keychain
echo ""
echo "Setting GitHub secrets from Keychain (service: franklin-infra)..."
SECRETS=("TS_OAUTH_CLIENT_ID" "TS_OAUTH_SECRET" "FRANKLIN_SSH_KEY")
if ! git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
  echo "  ⚠ [WARN] No .git directory found in $PROJECT_DIR — cannot detect GitHub repo or set secrets"
fi

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)

if [ -n "$REPO" ]; then
  for SECRET in "${SECRETS[@]}"; do
    VALUE=$(security find-generic-password -s franklin-infra -a "$SECRET" -w 2>/dev/null)
    if [ -n "$VALUE" ]; then
      echo "$VALUE" | gh secret set "$SECRET" -R "$REPO" 2>/dev/null \
        && echo "  ✓ $SECRET" \
        || echo "  ✗ $SECRET (failed to set)"
    else
      echo "  ⚠ [WARN] $SECRET not found in Keychain (service: franklin-infra) — skipping gh secret set"
    fi
  done
  # Optional: NTFY_TOPIC
  NTFY=$(security find-generic-password -s franklin-infra -a NTFY_TOPIC -w 2>/dev/null)
  if [ -n "$NTFY" ]; then
    echo "$NTFY" | gh secret set NTFY_TOPIC -R "$REPO" 2>/dev/null && echo "  ✓ NTFY_TOPIC"
  fi
else
  echo "  ⚠ No GitHub repo detected — set secrets manually:"
  echo "    gh secret set TS_OAUTH_CLIENT_ID"
  echo "    gh secret set TS_OAUTH_SECRET"
  echo "    gh secret set FRANKLIN_SSH_KEY"
fi

echo ""
echo "Done! Next steps:"
echo "  1. Edit .infra.yml with your project values"
echo "  2. Edit .github/workflows/ci-cd.yml with your project values"
echo "  3. Edit .github/workflows/backup.yml (if using a database)"
echo "  4. Create DB on Franklin if needed:"
echo "     ssh franklin \"psql -p 5433 -U postgres -c 'CREATE DATABASE my_db;'\""
echo "  5. Commit ports.txt + Caddyfile changes in franklin-infra"
echo "  6. Deploy shared infra: cd ~/p/franklin-infra && make infra-deploy && make caddy-reload"
echo "  7. Push to main — pipeline runs automatically"
