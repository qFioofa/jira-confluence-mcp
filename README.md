# ruby-jira-mcp

Read-only Jira и Confluence для AI-агента. Один проект, один набор токенов,
только `GET`-запросы. Есть три способа запуска:

| Режим          | Что запускается                  | Когда нужен                      |
| -------------- | -------------------------------- | -------------------------------- |
| **Standalone** | `mcp/` на Rack + Puma, без Rails | локальный MCP по URL             |
| **Docker**     | тот же standalone в контейнере   | изоляция, compose                |
| **Rails**      | web UI + персональные MCP-токены | несколько пользователей/проектов |

## Минимальные старт

Один раз создайте `.env`:

```bash
cp .env.example .env
```

Jira Cloud — замените только значения:

```dotenv
MCP_PROJECT_ID=alpha
JIRA_BASE_URL=https://acme.atlassian.net
JIRA_DEPLOYMENT=cloud
JIRA_EMAIL=dev@acme.io
JIRA_API_TOKEN=xxxxxxxxxxxxxxxx
JIRA_KEYS=CLD
```

Jira Data Center — вместо `JIRA_API_TOKEN`:

```dotenv
JIRA_DEPLOYMENT=dc
JIRA_PAT=xxxxxxxxxxxxxxxx
```

Confluence:

```dotenv
CONFLUENCE_BASE_URL=https://acme.atlassian.net/wiki
CLD_SPACE=CLD
```

Дальше — выберите один вариант.

**Standalone:**

```bash
make install
make local-mcp
# MCP: http://127.0.0.1:8765/mcp
```

**Docker, один контейнер:**

```bash
make docker-mcp-up
# MCP: http://127.0.0.1:8765/mcp
make docker-mcp-down
```

**Docker Compose (MCP + Rails):**

```bash
make compose-up
# MCP:   http://127.0.0.1:8765/mcp
# Rails: http://127.0.0.1:3000
make compose-down
```

**Rails локально:**

```bash
make web-setup
make web
# Rails: http://127.0.0.1:3000
# Логин: ADMIN_EMAIL / ADMIN_PASSWORD (по умолчанию admin@example.com / password)
# Далее: /user_credentials -> /mcp_endpoints -> http://127.0.0.1:3000/mcp/<token>
```

Проверка в любом режиме:

```bash
curl -s http://127.0.0.1:8765/health
```

## Слои

| Каталог  | Что это                                                         |
| -------- | --------------------------------------------------------------- |
| `lib/`   | `jira_core`: HTTP-клиенты, Atlassian-адаптеры, репозитории, кэш |
| `mcp/`   | `jira_mcp`: 19 tools, prompts, resources + standalone endpoint  |
| `rails/` | Web UI, пользователи, проекты, выпуск токенов MCP               |
| `docs/`  | дизайн standalone endpoint                                      |

## Требования

- Ruby 4.0+, Bundler 4.0+
- Linux/macOS
- Для Docker: Docker 24+ и (опционально) Docker Compose v2
- Токен Jira: API token (Cloud) или PAT (Data Center/Server)

---

# 1. Standalone MCP (без Rails)

## Подготовка

```bash
make env          # создаст .env из .env.example, если его нет
vi .env           # заполнить обязательные переменные
make install      # bundle install для lib/, mcp/, rails/
```

Обязательные переменные:

| Переменная        | Что задаёт                             |
| ----------------- | -------------------------------------- |
| `MCP_PROJECT_ID`  | id проекта; один процесс = один проект |
| `JIRA_BASE_URL`   | `https://acme.atlassian.net`           |
| `JIRA_EMAIL`      | email для Jira Cloud                   |
| `JIRA_API_TOKEN`  | API token для Jira Cloud               |
| `JIRA_PAT`        | PAT вместо API token для Data Center   |
| `JIRA_DEPLOYMENT` | `cloud` (по умолчанию) или `dc`        |

`JIRA_API_TOKEN` и `JIRA_PAT` взаимоисключающие: нужен ровно один.

## Запуск

```bash
make local-mcp
# jira-mcp HTTP: http://127.0.0.1:8765/mcp
```

Проверка:

```bash
curl -s http://127.0.0.1:8765/health
# {"status":"ok","project":"alpha"}

curl -s -X POST http://127.0.0.1:8765/mcp \
  -H 'content-type: application/json' \
  -H 'accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Запуск без `make` (переменные должны быть в окружении, `.env` сам не читается):

```bash
cd mcp
set -a; . ../.env; set +a
bundle exec ruby bin/jira-mcp-http --host 127.0.0.1 --port 8765 --path /mcp
```

## Флаги раннера

Флаги важнее переменных окружения.

| Флаг          | Env                      | По умолчанию | Назначение                                     |
| ------------- | ------------------------ | ------------ | ---------------------------------------------- |
| `--host HOST` | `MCP_HTTP_HOST`          | `127.0.0.1`  | адрес прослушивания                            |
| `--port PORT` | `MCP_HTTP_PORT`          | `8765`       | порт                                           |
| `--path PATH` | `MCP_HTTP_PATH`          | `/mcp`       | путь JSON-RPC endpoint                         |
| —             | `MCP_HTTP_ALLOWED_HOSTS` | пусто        | дополнительные `Host` для DNS-rebinding защиты |

`/health` всегда доступен рядом с MCP-путём. Сервер работает **stateless**:
каждый POST самодостаточен, сессии и БД не используются, кэш — в памяти
(перезапуск очищает). Ответы отдаются JSON; клиент должен присылать
`Accept: application/json, text/event-stream`.

## Подключение клиента

`opencode.json`:

```json
{
    "mcp": {
        "servers": {
            "jira-alpha": {
                "type": "remote",
                "url": "http://127.0.0.1:8765/mcp",
                "enabled": true
            }
        }
    }
}
```

---

# 2. Docker

## Один контейнер

```bash
make docker-mcp-build   # docker build -f mcp/Dockerfile -t jira-mcp:local .
make docker-mcp-up      # запуск + ожидание /health
make docker-mcp-status  # контейнер + health
make docker-mcp-logs    # логи (stderr, JSON)
make docker-mcp-down    # остановить и удалить
```

Что делает `docker-mcp-up`:

- читает переменные из `.env` (`--env-file`);
- пробрасывает `MCP_PROJECT_ID` (можно переопределить `make docker-mcp-up PROJECT=beta`);
- слушает внутри `0.0.0.0:8765`, наружу публикует `127.0.0.1:8765`;
- задаёт `MCP_HTTP_PATH=/mcp` и `MCP_HTTP_ALLOWED_HOSTS=localhost,127.0.0.1`;
- ждёт `http://127.0.0.1:8765/health`.

Переопределения:

```bash
make docker-mcp-up HTTP_PORT=9000 PROJECT=beta
```

Ручной запуск:

```bash
docker run --rm \
  --env-file .env \
  -e MCP_HTTP_HOST=0.0.0.0 \
  -p 127.0.0.1:8765:8765 \
  jira-mcp:local
```

Образ: `ruby:4.0-slim`, non-root (`uid 10001`), entrypoint —
`bundle exec ruby bin/jira-mcp-http`. Внутри контейнера есть `HEALTHCHECK`
на `/health`.

## Compose

```bash
make compose-up      # mcp + rails
make compose-down
docker compose logs -f mcp
docker compose up mcp
```

В `compose.yml` два сервиса:

| Сервис  | Порт             | Назначение                              |
| ------- | ---------------- | --------------------------------------- |
| `mcp`   | `127.0.0.1:8765` | standalone MCP; внутри `0.0.0.0:8765`   |
| `rails` | `3000`           | web UI; SQLite в volume `rails_storage` |

Compose сам читает `.env` для подстановки переменных.

---

# 3. Rails web UI

Standalone Rails не требует. Этот режим нужен, если несколько пользователей,
свои токены и управление проектами через браузер.

```bash
make web-setup   # bundle install + db:prepare + db:seed
make web         # http://127.0.0.1:3000
```

Seed создаёт администратора из `ADMIN_EMAIL` / `ADMIN_PASSWORD`
(по умолчанию `admin@example.com` / `password`), команду `demo`,
проект `demo-project` и примеры connections.

Порядок в UI:

1. **Login** — `/login`.
2. **Connections** — реальные `base_url` Jira/Confluence и `deployment`
   (нужны права администратора команды).
3. **Projects** — slug, Jira/Confluence connection, `jira_keys`, `spaces`, `style`.
4. **User credentials** — `/user_credentials`: персональный токен на каждое
   connection (`api_token` + email либо `pat`). Можно проверить кнопкой verify.
5. **MCP endpoints** — `/mcp_endpoints`: выбрать проект, создать endpoint.
   Токен показывается один раз; URL для клиента:

    ```text
    http://127.0.0.1:3000/mcp/<token>
    ```

Rails-эндpoint: `match "/mcp/:token"`, rate limit `120` запросов/минуту на токен,
токен можно отозвать. Если у пользователя нет credential для connection,
вернётся `403` с `code: user_credential_missing` и ссылкой на `/user_credentials/new`.

Переменные Rails:

| Переменная                             | Назначение                                |
| -------------------------------------- | ----------------------------------------- |
| `SECRET_KEY_BASE`                      | секрет Rails (в dev можно не задавать)    |
| `ADMIN_EMAIL`, `ADMIN_PASSWORD`        | seed администратора                       |
| `MCP_ALLOWED_HOSTS`                    | разрешённые `Host` для Rails MCP-endpoint |
| `SEED_JIRA_URL`, `SEED_CONFLUENCE_URL` | демо-connections                          |
| `SEED_JIRA_KEY`, `SEED_SPACE`          | allowlist демо-проекта                    |
| `DATABASE_URL`                         | PostgreSQL в production; локально SQLite  |

---

# Параметры проекта и данных

Эти переменные общие для standalone и Docker (Rails хранит то же в БД).

| Переменная                                                   | По умолчанию                  | Что делает                                                 |
| ------------------------------------------------------------ | ----------------------------- | ---------------------------------------------------------- |
| `MCP_PROJECT_ID`                                             | —                             | id проекта, попадает в `project_list` и логи               |
| `MCP_PROJECT_NAME`                                           | `MCP_PROJECT_ID`              | отображаемое имя                                           |
| `MCP_PROJECT_STYLE`                                          | `scrum`                       | `scrum` или `kanban`                                       |
| `MCP_PROJECT_ALIASES`                                        | пусто                         | алиасы для `project_resolve`                               |
| `JIRA_KEYS`                                                  | `MCP_PROJECT_ID` в upper case | allowlist Jira-ключей; в JQL всегда `project IN (...)`     |
| `CLD_SPACE`                                                  | пусто                         | allowlist пространств Confluence; пусто отключает KB-tools |
| `CONFLUENCE_BASE_URL`                                        | `<Jira>/wiki`                 | URL Confluence                                             |
| `CONFLUENCE_EMAIL`, `CONFLUENCE_API_TOKEN`, `CONFLUENCE_PAT` | наследуют Jira                | отдельные креды Confluence                                 |

Важно: `JIRA_KEYS` должен содержать реальные ключи Jira. Если `MCP_PROJECT_ID`
это slug (`alpha`), а ключ проекта `CLD`, без `JIRA_KEYS=CLD` поиск будет
ограничен несуществующим `ALPHA`.

# Поведение и вывод

| Переменная                | По умолчанию   | Что делает                                  |
| ------------------------- | -------------- | ------------------------------------------- |
| `MCP_LOCALE`              | `ru`           | локаль сообщений сервера (`ru`/`en`)        |
| `OUTPUT_LANG`             | `MCP_LOCALE`   | язык ответов tools                          |
| `OUTPUT_CHAR_LIMIT`       | `24000`        | лимит символов ответа, дальше `truncated`   |
| `QUERY_MAX_CHARS`         | `2000`         | максимум длины JQL/CQL                      |
| `TEAM_SHOW_EMAIL`         | `0`            | показывать email в `team_*`                 |
| `TEAM_WINDOW_DAYS`        | `180`          | окно активности для `team_who_knows`        |
| `HTTP_TIMEOUT_MS`         | `20000`        | таймаут запросов к Atlassian                |
| `HTTP_KEEP_ALIVE`         | `1`            | persistent connections                      |
| `HTTP_KEEP_ALIVE_TIMEOUT` | `30`           | idle timeout keep-alive                     |
| `CACHE_ENABLED`           | `1`            | кэш ответов                                 |
| `CACHE_SEARCH`            | `0`            | кэшировать поисковые ответы                 |
| `CACHE_STALE_GRACE`       | `600`          | сек. отдачи устаревших данных при ошибке    |
| `STATS_ENABLED`           | `0` standalone | сбор статистики вызовов                     |
| `STATS_RETENTION_DAYS`    | `7`            | срок хранения статистики                    |
| `LOG_LEVEL`               | `info`         | `debug`/`info`/`warn`/`error`; лог в stderr |

Булевы значения: `1`, `true`, `yes`, `on` — включено; пусто/`0` — выключено.

# Make-команды

| Команда                                              | Что делает                                   |
| ---------------------------------------------------- | -------------------------------------------- |
| `make env`                                           | создаёт `.env` из `.env.example`             |
| `make install`                                       | bundle install для `lib/`, `mcp/`, `rails/`  |
| `make local-mcp`                                     | standalone MCP на `127.0.0.1:8765/mcp`       |
| `make docker-mcp-up`                                 | собрать и запустить контейнер + health-check |
| `make docker-mcp-down`                               | остановить контейнер                         |
| `make docker-mcp-logs`                               | логи контейнера                              |
| `make docker-mcp-status`                             | статус + `/health`                           |
| `make compose-up` / `make compose-down`              | весь стек через Compose                      |
| `make web-setup`                                     | подготовить Rails DB и seed                  |
| `make web`                                           | Rails на `http://127.0.0.1:3000`             |
| `make web-migrate`                                   | миграции Rails                               |
| `make test`                                          | тесты `lib/` + `mcp/` + `rails/`             |
| `make core-test` / `make mcp-test` / `make web-test` | тесты по слоям                               |

# Tools

`project_list`, `project_describe`, `project_resolve`,
`jira_my_work`, `jira_search_issues`, `jira_get_issue`, `jira_brief_issue`,
`jira_get_changelog`, `jira_list_attachments`, `jira_unblock_issue`,
`jira_list_sprints`, `jira_get_sprint_issues`,
`kb_search`, `kb_get_page`, `kb_list_children`,
`team_who_knows`, `team_prepare_question`,
`atlassian_whoami`, `atlassian_cache_stats`.

# Частые проблемы

| Симптом                                  | Причина и решение                                                       |
| ---------------------------------------- | ----------------------------------------------------------------------- |
| `MCP_PROJECT_ID is required`             | не задан проект: `.env` или `MCP_PROJECT_ID=...`                        |
| `JIRA_API_TOKEN or JIRA_PAT is required` | не задан токен Jira                                                     |
| `Connection refused`                     | процесс не запущен или другой порт (`--port`)                           |
| `406 Not Acceptable` на `/mcp`           | клиент не прислал `Accept: application/json, text/event-stream`         |
| `403` от транспорта                      | `Host` не разрешён: добавьте его в `MCP_HTTP_ALLOWED_HOSTS`             |
| Пустые результаты JQL                    | `JIRA_KEYS` не совпадает с реальными ключами проекта                    |
| Rails `user_credential_missing`          | добавьте credential на `/user_credentials/new`                          |
| Rails `invalid or revoked MCP token`     | токен отозван или скопирован неверно; создайте новый в `/mcp_endpoints` |

# Безопасность

- **Read-only by design**: нет записи в Jira/Confluence и отправки сообщений.
- `project`, `space`, `ORDER BY` и `;` в пользовательских JQL/CQL отклоняются;
  запросы ограничены allowlist проекта.
- Standalone endpoint слушает loopback и не имеет встроенной аутентификации:
  не публикуйте порт наружу.
- Секреты передаются только через env (или зашифрованы в Rails БД); логи идут
  в stderr и не содержат токенов.

Лицензия: [MIT](LICENSE).
