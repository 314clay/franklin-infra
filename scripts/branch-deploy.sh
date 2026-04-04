#!/usr/bin/env bash
set -euo pipefail

# Deploy or teardown a branch instance
# Usage: branch-deploy.sh <deploy|teardown> <project-dir> <branch>

ACTION="${1:?Usage: $0 <deploy|teardown> <project-dir> <branch>}"
PROJECT_DIR="$(cd "${2:?}" && pwd)"
BRANCH="${3:?}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../infra"
INFRA_REPO="$SCRIPT_DIR/.."
PORTS_FILE="$INFRA_DIR/ports.txt"
FRANKLIN="clayarnold@100.112.120.2"

# Read project config
PROJECT_NAME=$(yq '.project.name' "$PROJECT_DIR/.infra.yml")
SANITIZED_BRANCH=$(echo "$BRANCH" | tr '/' '-' | tr '[:upper:]' '[:lower:]')
BRANCH_NAME="${PROJECT_NAME}-${SANITIZED_BRANCH}"
BASE_DEPLOY_PATH=$(yq '.project.deploy_path' "$PROJECT_DIR/.infra.yml" | sed 's|^~/||')
DEPLOY_PATH="~/${BASE_DEPLOY_PATH}-${SANITIZED_BRANCH}"
HEALTH_ENDPOINT=$(yq '.project.health_endpoint' "$PROJECT_DIR/.infra.yml")

allocate_port() {
  if grep -q "^${BRANCH_NAME} " "$PORTS_FILE"; then
    grep "^${BRANCH_NAME} " "$PORTS_FILE" | awk '{print $2}'
  else
    local max_port
    max_port=$(grep -v '^#' "$PORTS_FILE" | grep -v '^$' | awk '{print $2}' | sort -n | tail -1)
    local next_port=$(( ${max_port:-3099} + 1 ))
    echo "${BRANCH_NAME} ${next_port}" >> "$PORTS_FILE"
    echo "$next_port"
  fi
}

case "$ACTION" in
  deploy)
    PORT=$(allocate_port)
    echo "==> ${BRANCH_NAME} on port ${PORT}"

    # Clone or update branch on Franklin
    REMOTE_URL=$(cd "$PROJECT_DIR" && git remote get-url origin)
    ssh "$FRANKLIN" bash << REMOTE
      set -e
      if [ ! -d "${DEPLOY_PATH}" ]; then
        git clone --branch "${BRANCH}" "${REMOTE_URL}" "${DEPLOY_PATH}"
      else
        cd "${DEPLOY_PATH}"
        git fetch origin
        git checkout "${BRANCH}"
        git pull origin "${BRANCH}"
      fi
REMOTE

    # Generate docker-compose.override.yml for branch-specific port + container name
    ssh "$FRANKLIN" bash << REMOTE
      set -e
      cat > "${DEPLOY_PATH}/docker-compose.override.yml" << 'OVERRIDE'
services:
  app:
    container_name: ${BRANCH_NAME}
    environment:
      - PORT=${PORT}
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:${PORT}${HEALTH_ENDPOINT}"]
OVERRIDE
REMOTE

    # Build and start
    ssh "$FRANKLIN" "cd ${DEPLOY_PATH} && PORT=${PORT} docker compose up -d --build"

    # Regenerate Caddyfile, push, and reload
    "$SCRIPT_DIR/gen-caddyfile.sh"
    cd "$INFRA_REPO"
    git add infra/ports.txt infra/Caddyfile
    git commit -m "Branch deploy: ${BRANCH_NAME} on port ${PORT}"
    git push origin main
    ssh "$FRANKLIN" "cd ~/franklin-infra && git pull origin main && docker exec caddy caddy reload --config /etc/caddy/Caddyfile"

    echo ""
    echo "Live at: http://${BRANCH_NAME}.f"
    ;;

  teardown)
    echo "==> Tearing down ${BRANCH_NAME}"

    # Stop container and remove deploy directory
    ssh "$FRANKLIN" "cd ${DEPLOY_PATH} && docker compose down --rmi local --volumes 2>/dev/null || true"
    ssh "$FRANKLIN" "rm -rf ${DEPLOY_PATH}"

    # Remove from ports.txt
    sed -i '' "/^${BRANCH_NAME} /d" "$PORTS_FILE"

    # Regenerate Caddyfile, push, and reload
    "$SCRIPT_DIR/gen-caddyfile.sh"
    cd "$INFRA_REPO"
    git add infra/ports.txt infra/Caddyfile
    git commit -m "Teardown branch deploy: ${BRANCH_NAME}"
    git push origin main
    ssh "$FRANKLIN" "cd ~/franklin-infra && git pull origin main && docker exec caddy caddy reload --config /etc/caddy/Caddyfile"

    echo "Torn down: ${BRANCH_NAME}"
    ;;

  *)
    echo "Unknown action: $ACTION"
    echo "Usage: $0 <deploy|teardown> <project-dir> <branch>"
    exit 1
    ;;
esac
