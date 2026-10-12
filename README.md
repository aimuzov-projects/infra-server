# server-infra

Общий Caddy для сервера с проектами (`ssh projects`, 185.219.43.208). Держит 80/443, выпускает
сертификаты и раскидывает домены по контейнерам проектов.

## Как устроен сервер

```
/srv/
  infra/            ← этот репо
  <project>/        ← клон репо проекта, там же собирается и запускается
```

- Один проект — одна папка `/srv/<project>` и один compose-проект с явным `name:`. Контейнеры,
  тома и сети получают префикс проекта, поэтому проекты не пересекаются.
- Проекты не публикуют порты на хост. Они подключаются к внешней сети `edge`, Caddy ходит к ним
  по имени контейнера.
- Проект не пишет за пределы своей папки. Какой домен куда идёт, знает только `sites/` этого репо.
- Каждый репо тянется на сервер своим read-only deploy key.

## Выкладка

Пуш в `main` запускает GitHub Actions: проверка shellcheck и `caddy validate`, затем вход по SSH
на сервер. Там ключ привязан к [`deploy/remote.sh`](deploy/remote.sh): он подтягивает `main`,
обновляет VPN-выход и применяет конфиг Caddy. Повторить выкладку без пуша:
`gh workflow run deploy.yml`.

Ключ в `authorized_keys` сервера ограничен одной командой:

```
command="git -C /srv/infra pull --ff-only --quiet && /srv/infra/deploy/remote.sh",restrict ssh-ed25519 ... github-actions@server-infra
```

Приватная половина лежит в секрете `DEPLOY_SSH_KEY` репозитория.

## Новый проект

1. В compose проекта: `name: <project>`, у сервиса уникальный `container_name`, сеть `edge`
   как `external: true`, без `ports:`.
2. Deploy key на сервере:

   ```bash
   ssh projects 'ssh-keygen -q -t ed25519 -N "" -C "projects-server:<repo>" -f ~/.ssh/<repo> &&
     printf "Host github-<repo>\n\tHostName github.com\n\tUser git\n\tIdentityFile ~/.ssh/<repo>\n\tIdentitiesOnly yes\n\n" >> ~/.ssh/config &&
     cat ~/.ssh/<repo>.pub'
   ```

   Публичный ключ добавить в репо: `gh repo deploy-key add key.pub -R aimuzov-projects/<repo>`.
3. Клонировать: `ssh projects git clone github-<repo>:aimuzov-projects/<repo>.git /srv/<project>`
   и поднять проект.
4. Добавить `sites/<project>.caddy` с `reverse_proxy <container_name>:<port>`, направить DNS домена
   на сервер и запушить `main`.

## VPN-выход

Сервер стоит в РФ, и часть внешних API (OpenRouter, Telegram) отсюда недоступна. Для этого есть
контейнер `vpn`: Xray с HTTP-прокси `vpn:3128` и SOCKS `vpn:1080` на профиле "Всё и сразу" из
подписки Alesha Vpnov. Маршруты и балансировщики профиля остаются как есть: российские адреса
идут напрямую, остальное через европейские ноды, а если они лежат, через запасные цепочки.

Проект пользуется им по желанию. В его compose:

```yaml
services:
  app:
    environment:
      HTTPS_PROXY: http://vpn:3128
      NODE_USE_ENV_PROXY: '1' # только для Node 24+: без этого fetch прокси не видит
    networks:
      - vpn

networks:
  vpn:
    name: vpn
    external: true
```

Конфиг Xray собирает `vpn/update.sh` из подписки (`VPN_SUBSCRIPTION_URL` в `/srv/infra/.env`).
Его запускает каждая выкладка и раз в сутки systemd-таймер `vpn-update.timer`. Проверка с сервера:

```bash
docker run --rm --network vpn curlimages/curl -sx http://vpn:3128 https://www.cloudflare.com/cdn-cgi/trace
```

## Подготовка сервера с нуля

Docker Engine из репозитория docker.com, `apt install jq`, `ufw allow 22/tcp, 80/tcp, 443`, затем
`docker network create edge`, `docker network create vpn`, `.env` по образцу `.env.example` и `git clone github-server-infra:aimuzov-projects/server-infra.git /srv/infra`.
