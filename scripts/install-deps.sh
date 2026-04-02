#!/usr/bin/env bash
set -euo pipefail

# Install golang-migrate and yq on macOS or Linux (Franklin)

OS=$(uname -s)

install_migrate() {
  if command -v migrate &>/dev/null; then
    echo "golang-migrate already installed: $(migrate -version 2>&1 || true)"
    return
  fi

  if [ "$OS" = "Darwin" ]; then
    echo "Installing golang-migrate via brew..."
    brew install golang-migrate
  else
    echo "Installing golang-migrate binary..."
    MIGRATE_VERSION="v4.17.0"
    curl -L "https://github.com/golang-migrate/migrate/releases/download/${MIGRATE_VERSION}/migrate.linux-amd64.tar.gz" | tar xz
    sudo mv migrate /usr/local/bin/migrate
    sudo chmod +x /usr/local/bin/migrate
    echo "Installed migrate to /usr/local/bin/migrate"
  fi
}

install_yq() {
  if command -v yq &>/dev/null; then
    echo "yq already installed: $(yq --version)"
    return
  fi

  if [ "$OS" = "Darwin" ]; then
    echo "Installing yq via brew..."
    brew install yq
  else
    echo "Installing yq binary..."
    YQ_VERSION="v4.40.5"
    curl -L "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -o /tmp/yq
    sudo mv /tmp/yq /usr/local/bin/yq
    sudo chmod +x /usr/local/bin/yq
    echo "Installed yq to /usr/local/bin/yq"
  fi
}

install_migrate
install_yq

echo ""
echo "All dependencies installed."
