#!/usr/bin/env bash
set -euo pipefail

# Generate Caddyfile from ports.txt
# Usage: ./scripts/gen-caddyfile.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORTS_FILE="$SCRIPT_DIR/../infra/ports.txt"
CADDYFILE="$SCRIPT_DIR/../infra/Caddyfile"

cat > "$CADDYFILE" << 'EOF'
# Auto-generated from ports.txt — do not edit by hand
# Regenerate: ./scripts/gen-caddyfile.sh

# Serve the internal CA cert so any Tailnet device can install it
# Visit http://cert.f to download — one-time setup per device
http://cert.f {
	rewrite * /root.crt
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
