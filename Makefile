FRANKLIN := clayarnold@100.112.120.2
INFRA_PATH := ~/franklin-infra/infra

.PHONY: infra-deploy infra-status infra-logs caddy-reload gen-caddyfile

infra-deploy:
	ssh $(FRANKLIN) "cd ~/franklin-infra && git pull origin main && cd infra && docker compose up -d"

infra-status:
	ssh $(FRANKLIN) "cd $(INFRA_PATH) && docker compose ps"

infra-logs:
	ssh $(FRANKLIN) "cd $(INFRA_PATH) && docker compose logs --tail=100 -f"

caddy-reload:
	ssh $(FRANKLIN) "cd ~/franklin-infra && git pull origin main && docker exec caddy caddy reload --config /etc/caddy/Caddyfile"

gen-caddyfile:
	./scripts/gen-caddyfile.sh
