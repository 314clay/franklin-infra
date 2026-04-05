#!/usr/bin/env bash
set -euo pipefail

# Generate Caddyfile from ports.txt
# Usage: ./scripts/gen-caddyfile.sh
#
# All *.f sites use tls internal (Caddy's built-in CA).
# Devices need the root CA installed once — see infra/franklin-ca.mobileconfig

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORTS_FILE="$SCRIPT_DIR/../infra/ports.txt"
CADDYFILE="$SCRIPT_DIR/../infra/Caddyfile"

cat > "$CADDYFILE" << 'EOF'
# Auto-generated from ports.txt — do not edit by hand
# Regenerate: ./scripts/gen-caddyfile.sh

# Serve the CA cert profile for easy device setup (over HTTP so it's accessible before trust)
http://cert.f {
	root * /data/caddy/pki/authorities/local
	file_server
}
EOF

grep -v '^#' "$PORTS_FILE" | grep -v '^$' | while read -r name port host; do
  host=${host:-localhost}
  cat >> "$CADDYFILE" << EOF

${name}.f {
	tls internal
	reverse_proxy ${host}:${port}
}
EOF
done

echo "Generated Caddyfile with $(grep -c '\.f {' "$CADDYFILE") routes"
