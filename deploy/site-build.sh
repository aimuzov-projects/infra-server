#!/usr/bin/env bash
# Build of a site on the server: check out the requested release tag (or the
# newest main without one) and rebuild its containers.
# Runs inside site-deploy@<project>.service, started by site.sh, so a dropped
# SSH connection doesn't kill a build halfway.
set -euo pipefail

# The body is a block: bash reads it whole before a pull of this repo replaces the file.
{
	project=${1:-}
	if [[ ! $project =~ ^[a-z0-9-]+$ || ! -d /srv/$project/.git ]]; then
		echo "usage: site-build.sh <project>, a clone in /srv/<project>" >&2
		exit 2
	fi

	# Written by site.sh. Checked again: the file is the only input from outside here.
	ref=$(cat "/run/site-deploy/$project.ref" 2>/dev/null || true)
	if [[ -n $ref && ! $ref =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo "not a release tag: $ref" >&2
		exit 2
	fi

	# One deploy at a time for all the sites: parallel builds choke the small server,
	# so a deploy of any site waits here for the previous one. The fetch goes after the
	# lock, so a waiting deploy sees the newest tags and main.
	exec 9>/tmp/sites-deploy.lock
	flock 9

	cd "/srv/$project"
	git fetch --quiet --tags origin
	target=origin/main
	[[ -n $ref ]] && target=refs/tags/$ref
	git checkout --quiet --detach "$target"
	git log -1 --format="%h %s ($(git describe --tags --always))"

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
