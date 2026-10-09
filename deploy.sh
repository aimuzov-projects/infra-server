#!/usr/bin/env bash
# Выкладка маршрутов: пушим main, сервер подтягивает его и перечитывает Caddyfile.
# Битый конфиг до reload не доходит: Caddy продолжает работать со старым.
set -euo pipefail

cd "$(dirname "$0")"

HOST="${INFRA_HOST:-projects}"

if [[ -n "$(git status --porcelain)" ]]; then
	echo "Есть незакоммиченные изменения, сначала закоммитьте их" >&2
	exit 1
fi
if [[ "$(git branch --show-current)" != main ]]; then
	echo "Выкладывается только main" >&2
	exit 1
fi

git push --quiet origin main
ssh "$HOST" 'set -e
cd /srv/infra
git pull --ff-only --quiet
git log -1 --oneline
docker compose up -d --quiet-pull
docker exec caddy caddy validate --config /etc/caddy/Caddyfile
docker exec caddy caddy reload --config /etc/caddy/Caddyfile'
