# Локальный UI

Отдельный процесс для настройки и просмотра состояния. Не входит в MCP-процесс и
не влияет на stdio. По умолчанию слушает `127.0.0.1`; в Docker — `0.0.0.0` внутри
контейнера, но порт публикуется только на loopback хоста.

## Запуск

```bash
(cd src && bundle install)    # с группой :ui
make ui
```

Или:

```bash
src/bin/jira-cld ui --open
```

По умолчанию порт эфемерный (`UI_PORT=0`), в консоль печатается URL с одноразовым
токеном. Он сохраняется в HttpOnly cookie. Без браузера:

```bash
JIRA_CLD_NO_OPEN=1 src/bin/jira-cld ui
```

Остановка — `Ctrl-C` / SIGTERM.

## Что внутри

- **Overview** — запросы, cache hit rate, ошибки, p95, последние вызовы.
- **Projects** — добавить/изменить/удалить проект, выбрать активный.
- **Cache** — размеры, очистка `expired`/`all` по проекту.
- **Checks** — конфиг, подключения, целостность SQLite.
- **Settings** — язык, тема, лимиты кэша.

## Правила

- CRUD и очистка — только `POST` + CSRF; активный проект удалить нельзя.
- Удаление проекта — soft-delete в `.trash/`, `stats.db` сохраняется.
- Секреты показываются только маской.
- GET ничего не меняет.

## Docker

Фон:

```bash
make docker-up-ui                 # порт 9292
make docker-up-ui UI_DOCKER_PORT=9393
```

Команда печатает готовый URL с одноразовым токеном. Он же есть в логах:

```bash
make docker-logs-ui
make docker-status-ui
make docker-down-ui
```

На переднем плане (для отладки):

```bash
make docker-run-ui
```

`docker-up-ui` собирает full-образ (`:full`), монтирует **каталог** конфига
read-write (UI меняет проекты и настройки) и каталог данных. Порт публикуется
только на `127.0.0.1`. Внутри контейнера UI слушает `UI_HOST=0.0.0.0`,
`UI_PORT=$(UI_DOCKER_PORT)`.

Ручной запуск:

```bash
make docker-full
docker run --rm -p 127.0.0.1:9292:9292 \
  -e UI_HOST=0.0.0.0 -e UI_PORT=9292 -e UI_OPEN=0 \
  -v /abs/config-dir:/home/jira/.config/jira-cld \
  -v /abs/data:/home/jira/.local/share/jira-cld \
  jira-cld:local-full ui
```

Каталог данных должен быть writable для uid, от которого запущен контейнер.

Всё то же доступно из CLI: [NO-UI.md](NO-UI.md).
