# Подключение к opencode

Два режима: сервер в Docker (клиент знает только URL, токена в opencode нет) или
локальный stdio-процесс (токен в окружении opencode).

## Вариант A: Docker + URL (без токена в opencode)

Подготовьте окружение один раз:

```bash
make env
vi .env                    # токен и email/PAT
make install
make setup PROJECT=alpha
make doctor PROJECT=alpha
```

Запустите контейнер в фоне:

```bash
make docker-up PROJECT=alpha HTTP_PORT=8765
```

Статус, логи и остановка:

```bash
make docker-status PROJECT=alpha
make docker-logs PROJECT=alpha
make docker-down PROJECT=alpha
```

Он слушает `127.0.0.1:8765` на хосте; `MCP_PROJECT_ID` и секреты передаются
контейнеру из `.env`, а не opencode. В `opencode.json`:

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

Сгенерировать сниппет: `make print-opencode PROJECT=alpha`.

Эндпоинты:

- `POST /mcp` — Streamable HTTP (JSON-RPC).
- `GET /health` — проверка живости.

## Вариант B: локальный stdio

```json
{
  "mcp": {
    "servers": {
      "jira-alpha": {
        "type": "local",
        "command": ["bundle", "exec", "bin/jira-cld", "mcp"],
        "cwd": "/absolute/path/to/ruby-jira-mcp/src",
        "pool": false,
        "environment": {
          "MCP_PROJECT_ID": "alpha",
          "JIRA_API_TOKEN": "{env:JIRA_API_TOKEN}"
        }
      }
    }
  }
}
```

Обязательно: `cwd` — папка `src/` с `Gemfile`, `MCP_PROJECT_ID` без него сервер
не стартует. Токен — через `{env:...}`, не литералом.

## Без Docker: HTTP вручную

```bash
make mcp-http PROJECT=alpha HTTP_PORT=8765
# или
cd src && MCP_PROJECT_ID=alpha MCP_HTTP_PORT=8765 bundle exec ruby bin/jira-cld mcp-http
```

`MCP_HTTP_HOST` по умолчанию `127.0.0.1`. Не выставляйте `0.0.0.0` без
дополнительной защиты: у HTTP-транспорта нет встроенной аутентификации.
`MCP_HTTP_STATELESS=1` отключает сессии (каждый POST самодостаточен).

## Несколько проектов

Каждый проект — свой сервер, процесс и порт:

```json
"jira-alpha": { "type": "remote", "url": "http://127.0.0.1:8765/mcp", "enabled": true },
"jira-beta":  { "type": "remote", "url": "http://127.0.0.1:8766/mcp", "enabled": true }
```

Запуск: `make docker-up PROJECT=alpha HTTP_PORT=8765` и
`make docker-up PROJECT=beta HTTP_PORT=8766`. Контейнеры получают разные имена
`jira-cld-alpha` и `jira-cld-beta`.
`project_resolve` не переключает привязку. Для другого проекта нужен другой сервер.

## Проверка

```bash
opencode mcp list
```

Ожидается `connected`. Ручной smoke по HTTP:

```bash
curl -s http://127.0.0.1:8765/health
```

stdio smoke:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"opencode","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | (cd src && MCP_PROJECT_ID=alpha bundle exec ruby bin/jira-cld mcp)
```

## Частые проблемы

| Симптом | Решение |
|---|---|
| `MCP_PROJECT_ID is required` | Добавьте `environment.MCP_PROJECT_ID` (stdio) или `-e MCP_PROJECT_ID=...` (Docker) |
| `unknown project` | `make setup` или `projects add` |
| `auth_failed` | Проверьте email/token (Cloud) или PAT (DC) |
| `not_found` / `deployment_capability` | Проверьте URL и `deployment`, запустите `make doctor` |
| `Connection refused` по URL | Контейнер/процесс не запущен: `make docker-up` или `make mcp-http` |
| `403 Forbidden` от HTTP MCP | Host не loopback: используйте `127.0.0.1`/`localhost` или `MCP_HTTP_ALLOWED_HOSTS` |
| timeout | Проверьте сеть/прокси и `HTTP_TIMEOUT_MS` |
| stale данные | `make cache-clear PROJECT=alpha YES=1 SCOPE=all` |

`CONFIG_PATH` задаёт `config.yml` (по умолчанию `~/.config/jira-cld/config.yml`).
После смены токена перезапустите MCP-процесс.

Примеры: `docs/agent-config-examples/`.
