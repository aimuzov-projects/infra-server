#!/usr/bin/env bash
# Собирает vpn/config.json для Xray из подписки Alesha Vpnov и перезапускает
# контейнер vpn, если конфиг поменялся. Профиль "Всё и сразу" берём как есть:
# в нём свои балансировщики и запасные ноды на случай, если основные лежат.
# Мы только выкидываем метаданные, приглушаем лог и переносим прокси на 0.0.0.0
# с фиксированными портами, чтобы до них достучались контейнеры из сети vpn.
set -euo pipefail

cd "$(dirname "$0")"

# shellcheck source=/dev/null
[[ -f ../.env ]] && source ../.env
: "${VPN_SUBSCRIPTION_URL:?VPN_SUBSCRIPTION_URL is not set, see .env.example}"

sub="$(mktemp)"
next="$(mktemp)"
trap 'rm -f "$sub" "$next"' EXIT

curl -fsS --max-time 30 -o "$sub" "$VPN_SUBSCRIPTION_URL"

jq '
	first(.[] | select(.remarks | test("Всё и сразу")))
	// error("no \"Всё и сразу\" profile in the subscription")
	| del(.remarks, .meta)
	| .log = {loglevel: "warning"}
	| .inbounds |= map(
		if .tag == "http" then .listen = "0.0.0.0" | .port = 3128
		elif .tag == "socks" then .listen = "0.0.0.0" | .port = 1080
		else . end
	)
' "$sub" >"$next"

# Подписка на каждый запрос отдаёт ноде другой serverName, поэтому таймер почти всегда
# перезапускает контейнер. Это пара секунд без прокси раз в сутки.
if cmp -s "$next" config.json; then
	echo "vpn: config unchanged ($(jq '[.outbounds[] | select(.protocol == "vless")] | length' config.json) nodes)"
	exit 0
fi

# Xray в контейнере работает не от root, поэтому ему нужно право на чтение.
install -m 644 "$next" config.json
echo "vpn: config updated ($(jq '[.outbounds[] | select(.protocol == "vless")] | length' config.json) nodes)"

if docker compose ps --status running --services 2>/dev/null | grep -qx vpn; then
	docker compose restart vpn
fi
