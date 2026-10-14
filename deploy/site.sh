#!/usr/bin/env bash
# Deploy of a site, run by its key from GitHub Actions through authorized_keys:
#   command="/srv/infra-server/deploy/site.sh <project>",restrict ssh-ed25519 ...
# The build itself runs in site-deploy@<project>.service: if the SSH connection
# drops, systemd finishes it. This script starts the unit, shows its log and
# exits with its result.
set -euo pipefail

# The body is a block: bash reads it whole before a pull of this repo replaces the file.
{
	project=${1:-}
	if [[ ! $project =~ ^[a-z0-9-]+$ || ! -d /srv/$project/.git ]]; then
		echo "usage: site.sh <project>, a clone in /srv/<project>" >&2
		exit 2
	fi

	unit="site-deploy@$project.service"

	# A build of this site is still running, e.g. after a dropped connection: let it
	# finish and build again, so the newest main gets out too.
	while [[ $(systemctl show -p ActiveState --value "$unit") == activating ]]; do
		echo "waiting for the running $unit"
		sleep 5
	done

	journalctl -u "$unit" -f -n 0 -o cat &
	log=$!
	trap 'kill "$log" 2>/dev/null' EXIT

	# Blocks until the build ends and fails with it. The job belongs to systemd, so it
	# lives on if this client dies with the connection.
	status=0
	systemctl start "$unit" || status=$?

	# journalctl may lag a little behind the unit.
	sleep 1
	exit "$status"
}
