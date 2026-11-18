# Headless (без UI)

Основной режим: MCP-сервер и CLI. Не загружает Roda/UI-гемы. stdio-режим портов
не открывает; HTTP-режим слушает loopback на заданном порту.

## Установка и запуск

```bash
make env
vi .env                         # JIRA_EMAIL + JIRA_API_TOKEN (Cloud) или JIRA_PAT (DC)
(cd src && bundle config set --local without 'ui')
make install

make setup PROJECT=alpha        # читает значения из .env
make doctor PROJECT=alpha
make run PROJECT=alpha          # stdio MCP
```

`make run` выставляет `MCP_PROJECT_ID=alpha`. Ручной запуск:

```bash
MCP_PROJECT_ID=alpha src/bin/jira-cld mcp
```

Без проекта процесс завершается с ошибкой. stdout — только JSON-RPC, логи — stderr.

## HTTP-режим (Streamable HTTP)

```bash
make mcp-http PROJECT=alpha HTTP_PORT=8765
# или вручную
cd src && MCP_PROJECT_ID=alpha MCP_HTTP_PORT=8765 bundle exec ruby bin/jira-cld mcp-http
```

- URL: `http://127.0.0.1:8765/mcp`, health: `/health`.
- `MCP_HTTP_HOST` (по умолчанию `127.0.0.1`), `MCP_HTTP_PATH` (`/mcp`),
  `MCP_HTTP_STATELESS=1` для режима без сессий.
- Встроенной аутентификации нет — не публикуйте порт наружу.
- В Docker: `make docker-up PROJECT=alpha HTTP_PORT=8765` (в фоне) или
  `make docker-run-http` (на переднем плане).

## Если .env нет

`make` создаёт его из `.env.example` автоматически. Прямой бинарник `.env` не читает —
используйте `make`, `export`, `direnv` или `op run`.

## Проверка MCP вручную

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | MCP_PROJECT_ID=alpha src/bin/jira-cld mcp
```

## Ежедневные команды

```bash
make doctor PROJECT=alpha OFFLINE=1     # без сети
make stats PROJECT=alpha RANGE=1h
make cache-stats PROJECT=alpha
make cache-clear PROJECT=alpha YES=1 SCOPE=expired
make db-check PROJECT=alpha
make db-migrate PROJECT=alpha
```

## Проекты

```bash
src/bin/jira-cld projects list
src/bin/jira-cld projects add --project beta --name Beta --jira-key BET --space BET_KB
src/bin/jira-cld projects remove --project beta --yes
```

`remove` делает soft-delete в `.trash/` и убирает проект из `config.yml`.
`--purge` удаляет данные из `.trash`.

## Конфиг и диагностика

```bash
src/bin/jira-cld config show
src/bin/jira-cld config validate
src/bin/jira-cld export diagnostics --output /tmp/jira-cld-diag.json
```

Экспорт не содержит токенов. Для поиска причин: `LOG_LEVEL=debug`.

## Коды возврата `doctor`

`0` ok · `2` config · `3` auth · `4` not found · `5` db · `6` network ·
`7` rate limited · `8` secret · `9` capability.

## Ограничения

- `ui` без UI-гемов завершается кодом `2` с подсказкой.
- Вложения — только метаданные и URL.
- `nokogiri` (группа `:kb`) улучшает разбор Confluence HTML; без него работает fallback.

Подключение к клиенту: [OPENCODE.md](OPENCODE.md).
