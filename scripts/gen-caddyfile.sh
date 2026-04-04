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
{
	auto_https off
}
EOF

grep -v '^#' "$PORTS_FILE" | grep -v '^$' | while read -r name port; do
  cat >> "$CADDYFILE" << EOF

${name}.f {
	reverse_proxy localhost:${port}
}
EOF
done

echo "Generated Caddyfile with $(grep -c '\.f {' "$CADDYFILE") routes"
