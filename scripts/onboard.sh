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
echo "Onboarding: $PROJECT_DIR"

# Copy template files
cp "$TEMPLATE_DIR/.infra.yml" "$PROJECT_DIR/.infra.yml"
cp "$TEMPLATE_DIR/Makefile" "$PROJECT_DIR/Makefile"
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
fi

echo ""
echo "Done! Next steps:"
echo "  1. Edit .infra.yml with your project values"
echo "  2. Edit .github/workflows/ci-cd.yml with: block"
echo "  3. Edit .github/workflows/backup.yml with: block"
echo "  4. Set GitHub secrets:"
echo "     gh secret set TS_OAUTH_CLIENT_ID"
echo "     gh secret set TS_OAUTH_SECRET"
echo "     gh secret set FRANKLIN_SSH_KEY"
echo "     gh secret set NTFY_TOPIC"
echo "  5. Create DB on Franklin if needed:"
echo "     ssh franklin \"psql -p 5433 -U postgres -c 'CREATE DATABASE my_db;'\""
echo "  6. Push to main — pipeline runs automatically"
