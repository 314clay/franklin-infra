#!/usr/bin/env bash
set -euo pipefail

# Generate a new chainable microservice project from template
# Usage: ./scripts/new-service.sh <service-name> [target-dir]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../template/chainable"

usage() {
  echo "Usage: $0 <service-name> [target-dir]"
  echo "  service-name: lowercase alphanumeric + hyphens (e.g. \"deepgram-transcriber\")"
  echo "  target-dir:   defaults to ~/p/<service-name>"
  exit 1
}

# --- 1. Validate service name ---
SERVICE_NAME="${1:-}"
[ -z "$SERVICE_NAME" ] && usage

if ! [[ "$SERVICE_NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
  echo "Error: service name must match ^[a-z][a-z0-9-]*$ (lowercase, starts with letter, alphanumeric + hyphens)"
  exit 1
fi

# --- 2. Set target dir ---
TARGET_DIR="${2:-$HOME/p/$SERVICE_NAME}"

# --- 3. Check target doesn't already exist ---
if [ -d "$TARGET_DIR" ]; then
  echo "Error: $TARGET_DIR already exists. Aborting."
  exit 1
fi

echo "Creating service: $SERVICE_NAME"
echo "Target directory: $TARGET_DIR"

# --- 4. Create target directory ---
mkdir -p "$TARGET_DIR"

# --- 5. Copy template files (including dotfiles) ---
cp -a "$TEMPLATE_DIR"/. "$TARGET_DIR"/

# --- 6. Run sed replacements on all copied files ---
find "$TARGET_DIR" -type f | while read -r f; do
  sed -i '' "s/__SERVICE_NAME__/$SERVICE_NAME/g" "$f"
  sed -i '' "s/__PORT__/3099/g" "$f"
done

# --- 7. Create .infra.yml ---
cat > "$TARGET_DIR/.infra.yml" <<EOF
project:
  name: $SERVICE_NAME
  port: "3099"
  health_endpoint: /api/state
  health_url: http://100.112.120.2:3099/api/state
  deploy_path: ~/$SERVICE_NAME
  runtime: python
EOF

# --- 8. Git init ---
git init "$TARGET_DIR"

# --- 9. Run onboard.sh (port allocation, Makefile, CI/CD, Caddyfile, GitHub secrets) ---
echo ""
echo "Running onboard.sh..."
"$SCRIPT_DIR/onboard.sh" "$TARGET_DIR"

# --- 10. Summary ---
echo ""
echo "=== Service created: $SERVICE_NAME ==="
echo "  Directory: $TARGET_DIR"
echo "  Template:  chainable microservice"
echo ""
echo "Next steps:"
echo "  1. cd $TARGET_DIR"
echo "  2. Edit process.py — implement handle_chunk and/or handle_event"
echo "  3. Add dependencies to requirements.txt"
echo "  4. Edit .env with any API keys or config"
echo "  5. git add -A && git commit -m 'Initial scaffold'"
echo "  6. Create GitHub repo and push to main"
