#!/usr/bin/env bash
# Builds vpn/config.json for Xray from the Alesha Vpnov subscription and restarts
# the vpn container if the config changed. The "Всё и сразу" profile is taken as is:
# it has its own balancers and fallback nodes for when the main ones are down.
# We only drop metadata, quiet the log and move the proxies to 0.0.0.0 on fixed ports,
# so that containers on the vpn network can reach them.
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

# The subscription gives a node a different serverName on every request, so the timer
# almost always restarts the container. That's a couple of seconds without a proxy once a day.
if cmp -s "$next" config.json; then
	echo "vpn: config unchanged ($(jq '[.outbounds[] | select(.protocol == "vless")] | length' config.json) nodes)"
	exit 0
fi

# Xray in the container doesn't run as root, so it needs read permission.
install -m 644 "$next" config.json
echo "vpn: config updated ($(jq '[.outbounds[] | select(.protocol == "vless")] | length' config.json) nodes)"

if docker compose ps --status running --services 2>/dev/null | grep -qx vpn; then
	docker compose restart vpn
fi
