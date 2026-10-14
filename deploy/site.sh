#!/usr/bin/env bash
# Deploy of a site on the server: pull its main and rebuild its containers.
# The deploy key of each site is bound to it in authorized_keys:
#   command="/srv/infra-server/deploy/site.sh <project>",restrict ssh-ed25519 ...
# so the logic lives here once instead of a copy in every site.
set -euo pipefail

# The body is a block: bash reads it whole before a pull of this repo replaces the file.
{
	project=${1:-}
	if [[ ! $project =~ ^[a-z0-9-]+$ || ! -d /srv/$project/.git ]]; then
		echo "usage: site.sh <project>, a clone in /srv/<project>" >&2
		exit 2
	fi

	# One deploy at a time for all the sites: parallel builds choke the small server,
	# so a deploy of any site waits here for the previous one. The pull goes after the
	# lock, so a waiting deploy builds the newest main.
	exec 9>/tmp/sites-deploy.lock
	flock 9

	cd "/srv/$project"
	git pull --ff-only --quiet
	git log -1 --oneline

	# .env is made once by hand from .env.example and never comes from git.
	if [[ -f .env.example && ! -f .env ]]; then
		echo "no /srv/$project/.env: fill one in from .env.example" >&2
		exit 1
	fi

	# --remove-orphans drops containers of services the compose file no longer has.
	docker compose -f deploy/docker-compose.yml up -d --build --quiet-pull --remove-orphans
	docker image prune -f >/dev/null
	exit
}
