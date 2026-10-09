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

```bash
./deploy.sh
```

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
   на сервер и запустить `./deploy.sh`.

## Подготовка сервера с нуля

Docker Engine из репозитория docker.com, `ufw allow 22/tcp, 80/tcp, 443`, затем
`docker network create edge` и `git clone github-server-infra:aimuzov-projects/server-infra.git /srv/infra`.
