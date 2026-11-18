# Быстрый старт

`ruby-jira-mcp` — локальный read-only MCP-сервер для Jira и Confluence. Работает по
stdio (его запускает MCP-клиент) или по Streamable HTTP (Docker/процесс + URL).
UI опционален.

## 1. Установка

```bash
make env          # создаст .env из .env.example
vi .env           # заполните только секреты
make install
```

Для Jira Cloud нужны `JIRA_EMAIL` + `JIRA_API_TOKEN`. Для Data Center — `JIRA_PAT`.
`make` сам копирует `.env.example` в `.env` (права `0600`) и загружает его в свои команды.

> `src/bin/jira-cld` напрямую `.env` **не** читает. Запускайте через `make` или
> экспортируйте переменные/используйте `direnv`, `op run`.

## 2. Настройка проекта

```bash
make setup PROJECT=alpha
```

Берёт значения из `.env`. Явные параметры тоже работают:

```bash
make setup PROJECT=alpha JIRA_URL=https://acme.atlassian.net EMAIL=dev@acme.io \
  JIRA_KEY=CLD SPACE=CLD
```

Записывается `~/.config/jira-cld/config.yml` (или `CONFIG_PATH`). Секреты в файл не
попадают — только ссылка вида `token_ref: env:JIRA_API_TOKEN`.

## 3. Проверка и запуск

```bash
make doctor PROJECT=alpha             # сеть + конфиг + БД
make doctor PROJECT=alpha OFFLINE=1   # без сети
make run PROJECT=alpha                # stdio MCP (запускает клиент)
```

Без `MCP_PROJECT_ID` сервер не стартует. Это защита от случайного доступа не к тому
проекту. stdout занят JSON-RPC, логи идут в stderr.

## 4. Подключение к opencode

**Docker + URL (токен остаётся в контейнере):**

```bash
make docker-up PROJECT=alpha HTTP_PORT=8765
```

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

**Локальный stdio:** скопируйте `docs/agent-config-examples/opencode.local.json` в
`opencode.json` и замените `cwd` на абсолютный путь к `src/`:

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

Подробнее: [OPENCODE.md](OPENCODE.md).

## 5. Режимы

- **Headless** — MCP + CLI, без UI-гемов и портов: [NO-UI.md](NO-UI.md).
- **UI** — отдельный локальный процесс на `127.0.0.1`: [UI.md](UI.md).

## 6. Где лежат данные

```
~/.local/share/jira-cld/
├── global/reference.db
├── stats.db
├── <project>/cache.db
└── .trash/<id>-<UTC>/     # soft-delete проектов
```

Кэш: L1 в памяти + L2 SQLite. Очистка:

```bash
make cache-clear PROJECT=alpha YES=1 SCOPE=expired
```

## 7. Главное о безопасности

- Только GET-запросы к Jira/Confluence. Записи и отправки сообщений нет.
- JQL всегда ограничен `project IN (...)`, CQL — `space IN (...)`.
- Секреты не пишутся в логи, HTML и диагностический экспорт.
- UI доступен только с loopback, мутации — через CSRF.

Коды ошибок `doctor`: `0` ok, `2` config, `3` auth, `4` not found, `5` db,
`6` network, `7` rate limited, `8` secret, `9` capability.

Полный список параметров — в `.env.example`; API tools — в [TOOLS.md](TOOLS.md).
