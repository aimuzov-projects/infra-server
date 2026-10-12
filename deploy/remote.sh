#!/usr/bin/env bash
# Выкладка на самом сервере: подтянуть main, обновить VPN-выход и применить конфиг Caddy.
# Её вызывают GitHub Actions на каждый пуш в main и при ручном запуске workflow.
# Для ключа из Actions это единственная разрешённая команда (command= в authorized_keys).
set -euo pipefail

# Тело в блоке: bash дочитает его целиком до того, как git pull подменит этот файл.
{
	cd /srv/infra-server

	# Два пуша подряд не должны выкладываться одновременно: второй ждёт первого.
	exec 9>/tmp/infra-deploy.lock
	flock 9

	git pull --ff-only --quiet
	git log -1 --oneline

	vpn/update.sh
	systemctl link --quiet /srv/infra-server/vpn/vpn-update.service /srv/infra-server/vpn/vpn-update.timer
	systemctl daemon-reload
	systemctl enable --now --quiet vpn-update.timer

	docker compose up -d --quiet-pull

	# Битый конфиг дальше проверки не идёт: Caddy продолжает работать со старым.
	# Проверяет одноразовый контейнер, он видит свежие файлы.
	docker compose run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile

	# Caddyfile смонтирован файлом, а git pull кладёт новый файл вместо старого: работающий
	# контейнер видит прежнюю версию, пока его не пересоздать. Папке sites/ хватает reload.
	if docker exec caddy cat /etc/caddy/Caddyfile | cmp -s - Caddyfile; then
		docker exec caddy caddy reload --config /etc/caddy/Caddyfile
	else
		docker compose up -d --force-recreate --no-deps caddy
	fi
	exit
}
