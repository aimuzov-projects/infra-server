#!/usr/bin/env bash
# Deploy on the server itself: pull main, update the VPN egress and apply the Caddy config.
# GitHub Actions runs it on every push to main and on a manual workflow run.
# It's the only command allowed for the Actions key (command= in authorized_keys).
set -euo pipefail

# The body is a block: bash reads it whole before git pull replaces this file.
{
	cd /srv/infra-server

	# Two pushes in a row must not deploy at the same time: the second waits for the first.
	exec 9>/tmp/infra-deploy.lock
	flock 9

	git pull --ff-only --quiet
	git log -1 --oneline

	vpn/update.sh
	systemctl link --quiet /srv/infra-server/vpn/vpn-update.service /srv/infra-server/vpn/vpn-update.timer
	systemctl link --quiet /srv/infra-server/docker/docker-prune.service /srv/infra-server/docker/docker-prune.timer
	systemctl daemon-reload
	systemctl enable --now --quiet vpn-update.timer docker-prune.timer

	# A broken config stops here and Caddy keeps running the old one. The check goes before
	# up -d, which recreates Caddy whenever its service in compose.yml changes. It runs in a
	# throwaway container because that one sees the fresh files.
	docker compose run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile

	docker compose up -d --quiet-pull

	# Caddyfile is mounted as a single file, and git pull puts a new file in place of the old
	# one: the running container sees the previous version until it's recreated. The sites/
	# directory is fine with a reload.
	if docker exec caddy cat /etc/caddy/Caddyfile | cmp -s - Caddyfile; then
		docker exec caddy caddy reload --config /etc/caddy/Caddyfile
	else
		docker compose up -d --force-recreate --no-deps caddy
	fi
	exit
}
