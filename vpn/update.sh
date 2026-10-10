#!/usr/bin/env bash
# Собирает vpn/config.json для Xray из подписки Alesha Vpnov и перезапускает
# контейнер vpn, если конфиг поменялся. Берём профиль "Всё и сразу" как есть:
# у него свои балансировщики и цепочка запасных нод, если основные не отвечают.
# Меняем только адреса прокси, чтобы до них дотягивались контейнеры из сети vpn.
set -euo pipefail

cd "$(dirname "$0")"

# shellcheck source=/dev/null
[[ -f ../.env ]] && source ../.env
: "${VPN_SUBSCRIPTION_URL:?VPN_SUBSCRIPTION_URL не задан, см. .env.example}"

sub="$(mktemp)"
next="$(mktemp)"
trap 'rm -f "$sub" "$next"' EXIT

curl -fsS --max-time 30 -o "$sub" "$VPN_SUBSCRIPTION_URL"

jq '
	first(.[] | select(.remarks | test("Всё и сразу")))
	// error("в подписке нет профиля \"Всё и сразу\"")
	| del(.remarks, .meta)
	| .log = {loglevel: "warning"}
	| .inbounds |= map(
		if .tag == "http" then .listen = "0.0.0.0" | .port = 3128
		elif .tag == "socks" then .listen = "0.0.0.0" | .port = 1080
		else . end
	)
' "$sub" >"$next"

# Подписка при каждом запросе выдаёт ноде другой serverName, так что таймер почти
# всегда перезапускает контейнер. Это пара секунд без прокси раз в сутки.
if cmp -s "$next" config.json; then
	echo "vpn: конфиг не изменился ($(jq '[.outbounds[] | select(.protocol == "vless")] | length' config.json) нод)"
	exit 0
fi

# Xray в контейнере работает не от root, ему нужно право на чтение.
install -m 644 "$next" config.json
echo "vpn: конфиг обновлён ($(jq '[.outbounds[] | select(.protocol == "vless")] | length' config.json) нод)"

if docker compose ps --status running --services 2>/dev/null | grep -qx vpn; then
	docker compose restart vpn
fi
