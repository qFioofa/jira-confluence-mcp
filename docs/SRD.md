# SRD — ruby-jira-mcp

**Статус:** зафиксировано для локальной v1
**Версия:** 0.2
**Дата:** 2026-11-17
**Среда:** Ruby 4.0.6, Bundler 4.0.16, Linux (NixOS)

---

## 1. Назначение и границы

Локальный MCP-сервер для чтения задач Jira и базы знаний Confluence команды.
Транспорт — stdio. Сервер запускается MCP-хостом (opencode) как дочерний процесс.

В scope v1:

- Jira Cloud и Jira Server/Data Center (read-only).
- Поиск и чтение задач, changelog, вложения (метаданные), boards/sprints.
- Confluence как база знаний: пространство `CLD`, поиск по CQL, чтение страниц.
- Поиск носителей контекста и подготовка вопросов команде (read-only, без отправки сообщений).
- Локальный кэш: память + SQLite, с ревалидацией по версии/ETag.
- Интернационализация промптов, описаний и ошибок.
- Структурные JSON-логи в stderr.
- Изоляция проектов: каталог метаданных + явная привязка.
- Headless-режим: настройка, диагностика, статистика и обслуживание без UI.
- Опциональный локальный UI для настройки и просмотра статистики.
- Destructive-операции в UI: очистка кэша и soft-delete проекта с подтверждением.

Вне scope v1:

- Запись в Jira/Confluence.
- Отправка сообщений в Slack/Teams/email; team-tools только готовят вопрос и ссылки.
- HTTP-транспорт, nginx, OAuth, multi-user.
- Postgres, Redis, горизонтальное масштабирование.
- Вложения как бинарные данные (только метаданные и URL).
- Полнотекстовый поиск по KB (FTS5) — возможное расширение.
- Автоматическое восстановление проекта из `.trash` — вручную.

---

## 2. Зафиксированные решения

| # | Решение | Обоснование |
|---|---|---|
| D1 | Rails используется как набор библиотек, без `railties` | нужны AR/AS, но не `Rails::Application` и web-слой |
| D2 | Транспорт stdio, протокол пиннится на `2025-11-25` | opencode по умолчанию открывает legacy handshake |
| D3 | SQLite — L2-кэш; durable-зеркало KB — v1.1 | один локальный движок, транзакции, SQL, WAL; зеркало не блокирует базовые tools |
| D4 | Кэш двухуровневый: `MemoryStore` + `DatabaseStore` | скорость L1, переживание рестарта L2 |
| D5 | `DatabaseStore` наследует `ActiveSupport::Cache::Store` | TTL, namespace, `race_condition_ttl`, instrumentation бесплатно |
| D6 | `solid_cache` не используется | требует `activejob`, `activerecord`, `railties` |
| D7 | i18n фиксируется на старте процесса | `tools/list` кэшируется хостом, локаль не должна меняться в рантайме |
| D8 | Ougai + `oj`, логи только в `$stderr` | stdout занят JSON-RPC |
| D9 | Zeitwerk без `eager_load` в рантайме | память и предсказуемый старт |
| D10 | Нет HTTP-транспорта MCP и nginx; UI — отдельный локальный процесс | stdio не имеет сетевого периметра |
| D11 | Read-only токен и allowlist `project/space` на проект | исключить случайные записи и лишние данные |
| D12 | Ревалидация по `version`/`updated`/ETag | TTL недостаточен для изменений в Confluence/Jira |
| D13 | Поиск кэшируется только при `CACHE_SEARCH=1` | результаты JQL/CQL быстро стареют |
| D14 | Имена tools/аргументов — английские, тексты — локализуемые | имена это API, тексты — для модели/человека |
| D15 | Изоляция проектов: `MCP_PROJECT_ID` обязателен, fail closed | нельзя угадывать проект по JQL/тексту |
| D16 | Каталог проектов — отдельный набор metadata-tools | discovery не должен быть границей доступа |
| D17 | Данные проектов — в отдельном каталоге SQLite на проект | удаление/аудит/утечки локализованы |
| D18 | Кросс-scope: `deny`/`declared`/`confirm`, без авто-фоллоу ссылок | связанность объявляется или подтверждается |
| D19 | UI — отдельный локальный процесс, не внутри stdio-сервера | stdout и lifecycle |
| D20 | UI: чтение + wizard + destructive-операции с подтверждением | очистка кэша и удаление проекта доступны в UI, но только через POST, CSRF и typed confirm |
| D21 | Headless — first-class: CLI покрывает настройку, статистику, диагностику | работа без браузера и UI-гемов |
| D22 | `config.yml` — источник настроек, env — переопределения | воспроизводимость и скриптуемость |
| D23 | Локаль по умолчанию — `ru`; `LANG`/`LC_*` игнорируются | предсказуемый вывод независимо от окружения |
| D24 | Тема по умолчанию — `system` | уважает настройку ОС, остаётся переключатель |
| D25 | Диапазоны графиков — `15m/1h/24h/7d` | покрывают рабочий день и неделю, ≤120 точек |
| D26 | Очистка кэша и удаление проекта — CLI и UI; удаление soft-delete в `.trash` | сохраняет восстановимость и статистику |
| D27 | KB-зеркало (`kb_pages`, `delta_cursors`) — после базовых tools, v1.1 | v1 не зависит от прогрева и живёт на ленивом кэше |
| D28 | В v1 19 tools: 16 data/team + 3 catalog | §8.1 — источник истины |
| D29 | Поддержка Jira/Confluence Cloud и DC через адаптеры и capability-матрицу | один интерфейс, разные API и формат тела |
| D30 | Бюджеты памяти и старта — по замерам, а не по оценке | решения о зависимостях принимаются по факту |
| D31 | ActiveRecord остаётся в runtime; отказ от AR отклонён | миграции/модели/транзакции сохраняются; hot path — `connection.select_value`/`exec_query` без инстанцирования моделей; raw `sqlite3` не вводим |
| D32 | Cache hit — read-only: `accessed_at` на чтении не обновляется | один commit на hit дороже разницы AR/raw; eviction по TTL/FIFO, запись только на miss/revalidate |
| D33 | L2-записи батчами: upsert + `BEGIN IMMEDIATE`, commit раз на запрос/порог | меньше fsync/WAL и lock contention; потеря последнего батча допустима для кэша |
| D34 | SQLite latency-настройки: `cache_size=8 MB`, `page_size=8 KB` (cache.db), `mmap=64 MB`, `temp_store=MEMORY`, `journal_size_limit=16 MB` | цель — тёплый L2; mmap подтвердить замером, fallback `0` |
| D35 | L1 = 8 MB, L2 = 16 MB; `CACHE_L1_BYTES` отдельно | latency: больше горячих данных в L1, но без раздувания RSS |
| D36 | Ruby runtime: GC growth `1.1`, disable `did_you_mean`/`error_highlight`/`syntax_suggest`, frozen strings, без YJIT для MCP, `MALLOC_ARENA_MAX=2` для UI | замеры: −~4 MB RSS; YJIT даёт +2 MB и +20–30 ms старта |
| D37 | Ленивые `net/http`/`openssl`/`nokogiri`; без `active_support/all`/core_ext | −~6.5 MB и −~70 ms до первого сетевого/KB-вызова |
| D38 | HTTP keep-alive к Jira/Confluence; latency-цель L2 p95 ≤ 2 ms, cache hit без записи | сеть доминирует в cold-вызовах; TLS handshake 100–300 ms |
| D39 | JQL/CQL — не парсим семантически: пресеты + структурные builders + guarded escape hatch | JQL/CQL принадлежат Atlassian; свой парсер даст ложные отказы и отставание от Cloud/DC |
| D40 | Team-tools работают только на evidence из Jira/Confluence и не отправляют сообщения | «к кому обратиться» = профиль + доказательства; write/messaging — отдельный scope с audit |

---

## 3. Стек и библиотеки

### Runtime

| Gem | Версия | Роль | Примечание |
|---|---|---|---|
| `mcp` | `~> 1.10` | JSON-RPC, tools/prompts/resources, stdio | официальный Ruby SDK; runtime-зависимость `json_schemer` |
| `activerecord` | `~> 8.1` | модели, миграции, транзакции, SQL | standalone; hot path — `select_value`/`exec_query` без моделей |
| `activesupport` | `~> 8.1` | `MemoryStore`, `AS::Cache::Store`, TZ, Notifications | грузить точечно, не `active_support/all` |
| `sqlite3` | `~> 2.10` | локальная БД | native-ext, сборка на NixOS |
| `i18n` | `~> 1.15` | локали | `activesupport` требует `< 2`; совместимо |
| `ougai` | `~> 2.1` | JSON-логи | тянет `oj ~> 3.17`; писать в `$stderr` |
| `zeitwerk` | `~> 2.8` | автозагрузка `lib/` | инфлекторы для `HTTP`, `ADF`, `KB`, `JQL` |
| `nokogiri` | `~> 1.16` | Confluence `body.view` → текст | ленивый `require`, только при `KB_ENABLED` |

Транзитивные, которые нужно учитывать: `json_schemer` (`bigdecimal`, `hana`, `regexp_parser`, `simpleidn`), `oj`, `activemodel`, `concurrent-ruby`, `connection_pool`, `tzinfo`, `drb`, `mini_portile2`.

### UI (опциональная группа `:ui`)

| Gem / ассет | Версия | Роль |
|---|---|---|
| `rack` | `~> 3.1` | Rack-интерфейс UI |
| `puma` | `~> 7.0` | локальный HTTP-сервер UI |
| `roda` | `~> 3.9` | роутинг |
| `erubi` | `~> 1.13` | ERB-шаблоны |
| `htmx.min.js` | 2.x, vendored | частичные обновления |
| `uplot.min.js` | 1.6.x, vendored | графики |
| шрифты | IBM Plex Sans/Mono, woff2 | типографика |

UI-гемы и ассеты **не загружаются** в headless-режиме. `require "roda"`/`puma` допустим только внутри `bin/jira-cld ui`.

### Development / test

`minitest`, `webmock`, `rubocop`, `rubocop-performance`, `memory_profiler`, `stackprof`, `bundler-audit`, `lefthook`.

### Сборка и упаковка

- Bundler-группы: core, `:ui`, `:kb` (`nokogiri`), `:development`, `:test`.
- Headless-установка: `bundle config set --local without 'ui'`.
- Ассеты UI вендорятся в `assets/ui/` + `SHA256SUMS`; Node/сборщик не нужны.
- Один исполняемый entrypoint: `bin/jira-cld` с подкомандами.
- Gem build: `gem build jira-cld.gemspec`; артефакт содержит `bin/`, `lib/`, `assets/`.
- Docker: multi-stage, build-arg `INSTALL_UI=true/false`, non-root, `--read-only`, tmpfs.
- Nix: devShell с `sqlite`, `pkg-config`, компилятором; без `nodejs`.

### Бюджеты (пересчитано по замерам)

Замеры: 2026-11-17, Ruby 4.0.6, NixOS, x86_64, `/usr/bin/time -f 'rss=%MKB elapsed=%e'`, по одному прогону на слой (быстрая оценка). Релизные значения снимать 5 прогонами по медиане. RSS — абсолютный максимум процесса, не приращение.

| Слой | RSS | Cold start |
|---|---:|---:|
| голый Ruby | 15.8 MB | 0.05 s |
| `AS::Cache` + `sqlite3` | 18.3 MB | 0.09 s |
| + `json` + `zeitwerk` | 19.5 MB | 0.10 s |
| + `net/http` + `nokogiri` | 26.3 MB | 0.18 s |
| полный стек + `active_record` | 32.2 MB | 0.25 s |
| `active_support/core_ext` (весь) | 42.4 MB | 0.26 s |

Профиль cache latency (AR, `select_value`, in-memory, 10k×1 KB): L2 get — **20.9 µs/op**, L2 upsert в транзакции — **17.7 µs/op**; 100k get → GC 149 ms, 3.87M аллокаций. Raw `sqlite3` даёт 3.9 µs/get и 3.9 µs/upsert, но **не выбран** (D31): это только ориентир для оценки цены AR.

Итоговые цели:

| Метрика | Цель | Бюджет |
|---|---|---|
| RSS MCP в простое | 40–55 MB | ≤ 60 MB |
| Cold start MCP | 200–350 ms | ≤ 400 ms |
| UI-процесс (on demand) | +20–30 MB | ≤ 90 MB суммарно с MCP |
| L2 get p95, тёплый кэш | ≤ 2 ms | — |
| Batch upsert 64 записи p95 | ≤ 10 ms | — |
| Размер SQLite v1 | 10–100 MB | — |
| Размер SQLite с KB-зеркалом (v1.1) | до 500 MB | — |

Оговорки:

- `mcp`, `json_schemer`, `ougai`, `oj`, `roda` в текущем окружении не установлены; их вклад замерить в фазе 0 (MCP) и фазе 10 (UI).
- `active_support/core_ext` — верхняя граница; в рантайме подключаются точечные ext.
- AR остаётся (D31); raw-цифры в профиле latency — только reference, не целевой путь.
- `mmap_size`, `page_size` и `cache_size` подтвердить на реальном `cache.db` в фазе 1; mmap может увеличить RSS на touched-страницы.
- Замеры на NixOS; перед релизом повторить в Docker-образе.
- `rake memory:measure` и `rake latency:measure` (фаза 7) — гейты: превышение бюджета блокирует релиз.

---

## 4. Что вырезано из Rails

| Вырезано | Причина | Замена |
|---|---|---|
| `rails`, `railties` | `Rails::Application`, initializers, credentials | `config/boot.rb`, `Config` Struct, env |
| `actionpack`, `actionview`, `actionmailer`, `actioncable`, `activestorage`, `actiontext` | нет web-слоя | — |
| `activejob` | нет фоновых джоб | один bounded-поток прогрева |
| `solid_cache` | требует `railties` | свой `DatabaseStore` |
| `ActiveSupport::Dependencies` | двойной автолоад | Zeitwerk |
| `ActiveRecord::Tasks` (Railties-обёртка) | лишнее | `ActiveRecord::MigrationContext` |
| `active_support/all` | лишние core_ext и память | точечные `require` |
| `puma`, `rack` | не нужны для MCP | только в опциональной группе `:ui` |
| `nginx` | нет сетевого периметра | — |
| `jira-ruby`, `faraday`, `httparty`, `rest-client` | тяжёлые/лишний стек | `net/http` |
| `dotenv`, `bootsnap` | секреты/память | env, `direnv`, `op run` |
| Postgres, Redis | локальный режим | смена адаптеров AR/AS позже |

---

## 5. Архитектура

```
                 LLM / opencode
                       │  JSON-RPC 2.0 over stdio
                       ▼
              ┌──────────────────┐
              │  MCP::Server     │  tools / prompts / resources / instructions
              │  StdioTransport  │  protocol 2025-11-25, page_size, ttl_ms
              └────────┬─────────┘
                       ▼
              ┌──────────────────┐
              │     Tools        │  валидация, DTO, isError
              └────────┬─────────┘
                       ▼
              ┌──────────────────┐
              │  Repositories    │  issues, knowledge_base, reference
              └────┬──────────┬──┘
                   │          │
        ┌──────────▼───┐  ┌───▼──────────────┐
        │ Cache        │  │ HTTP::Client     │
        │ TieredStore  │  │ net/http, retry  │
        │ ├ L1 Memory  │  └───┬──────────────┘
        │ └ L2 SQLite  │      │
        └──────┬───────┘      ▼
               │        Jira Cloud/DC, Confluence
               ▼
        ┌──────────────────────────────┐
        │ SQLite (WAL)                 │
        │ cache_entries (v1) /         │
        │ kb_pages, delta (v1.1)       │
        └──────────────────────────────┘
```

Правила слоёв:

- `tools` не знают про AR, SQL и HTTP.
- `repositories` — единственное место вызова кэша и HTTP.
- `Cache` facade скрывает L1/L2 и позволяет заменить SQLite/Redis.
- Зависимости инжектятся (`Tool.new(client:, cache:)`) для тестов.
- Проектные данные изолированы: `MCP_PROJECT_ID` → `<project>/cache.db`; каталог — только метаданные.

---

## 6. Project tree

```
mcp-jira-cld/
├── bin/
│   ├── jira-cld                 # единый entrypoint: mcp | ui | setup | doctor | stats | cache | db | export
│   ├── mcp-jira                 # alias: jira-cld mcp (для opencode)
│   └── console                  # irb + boot
├── assets/
│   └── ui/
│       ├── app.css
│       ├── htmx.min.js
│       ├── uplot.min.js
│       ├── fonts/
│       └── SHA256SUMS
├── config/
│   ├── boot.rb                  # порядок инициализации
│   ├── database.yml             # sqlite3, pool, pragmas
│   └── locales/
│       ├── ru.yml
│       ├── en.yml
│       └── ui.ru.yml / ui.en.yml
├── db/
│   ├── migrate/                 # AR-миграции
│   └── schema.rb
├── lib/
│   ├── jira_cld.rb              # Zeitwerk.setup + инфлекторы
│   └── jira_cld/
│       ├── config.rb            # ENV → frozen Struct + валидация
│       ├── config_store.rb      # config.yml: load/validate/atomic write
│       ├── secrets.rb           # env | keyring | command | file
│       ├── project_registry.rb  # каталог проектов
│       ├── logging.rb           # Ougai → $stderr
│       ├── i18n.rb              # backend, locale, load_path
│       ├── db.rb                # connect, pragmas, migrate, shutdown
│       ├── cli/
│       │   ├── app.rb           # разбор подкоманд
│       │   ├── setup.rb         # интерактивный и non-interactive
│       │   ├── doctor.rb
│       │   ├── projects.rb
│       │   ├── stats.rb
│       │   ├── cache.rb
│       │   ├── db.rb
│       │   ├── config_cmd.rb
│       │   └── export.rb
│       ├── stats/
│       │   ├── writer.rb        # batched writes в stats.db
│       │   └── query.rb         # агрегаты для CLI/UI
│       ├── ui/
│       │   ├── app.rb           # Roda
│       │   ├── helpers.rb
│       │   └── views/
│       ├── cache/
│       │   ├── policy.rb        # ns → ttl/limits/stale
│       │   ├── database_store.rb# AS::Cache::Store → AR
│       │   ├── tiered_store.rb  # L1 MemoryStore + L2
│       │   └── key.rb           # нормализация + digest + principal
│       ├── models/
│       │   ├── cache_entry.rb
│       │   ├── kb_page.rb
│       │   └── delta_cursor.rb
│       ├── http/client.rb       # таймауты, retry, 429, error mapping
│       ├── atlassian/
│       │   ├── auth.rb          # basic | bearer
│       │   ├── errors.rb        # 401/403/404/429/5xx → коды
│       │   ├── jira.rb          # /rest/api/3|2, /search/jql
│       │   ├── agile.rb         # /rest/agile/1.0
│       │   ├── confluence.rb    # space resolve, pages, CQL
│       │   └── fields.rb        # customfield_* → name (кэш)
│       ├── query/
│       │   ├── jql.rb           # wrap, validate, presets
│       │   └── cql.rb           # build, escape, wrap, presets
│       ├── repositories/
│       │   ├── issues.rb
│       │   ├── knowledge_base.rb
│       │   ├── people.rb        # evidence: authors, leads, experts
│       │   └── reference.rb
│       ├── render/
│       │   ├── adf.rb           # ADF → text
│       │   └── html.rb          # Confluence view → text
│       ├── serialize/
│       │   ├── issue.rb         # компактный DTO
│       │   ├── person.rb
│       │   └── page.rb
│       ├── tools/
│       │   ├── project_list.rb
│       │   ├── project_describe.rb
│       │   ├── project_resolve.rb
│       │   ├── my_work.rb
│       │   ├── search_issues.rb
│       │   ├── get_issue.rb
│       │   ├── brief_issue.rb
│       │   ├── unblock_issue.rb
│       │   ├── get_changelog.rb
│       │   ├── list_attachments.rb
│       │   ├── list_sprints.rb
│       │   ├── kb_search.rb
│       │   ├── kb_get_page.rb
│       │   ├── kb_list_children.rb
│       │   ├── team_who_knows.rb
│       │   ├── team_prepare_question.rb
│       │   ├── whoami.rb
│       │   └── cache_stats.rb
│       └── server.rb            # сборка MCP::Server
├── test/
│   ├── test_helper.rb
│   ├── fixtures/                # JSON/HTML: issue, changelog, page
│   ├── cli/
│   ├── cache/
│   ├── repositories/
│   ├── tools/
│   ├── ui/
│   └── integration/stdio_test.rb
├── Gemfile
├── Rakefile
├── jira-cld.gemspec
├── Dockerfile
├── flake.nix
└── README.md
```

---

## 7. Требования MCP

| # | Требование | Реализация | Критерий готовности |
|---|---|---|---|
| 1 | JSON-RPC 2.0, stdio | `MCP::Server` + `StdioTransport` | ответ на `ping`/`initialize` |
| 2 | Версия протокола | пин `2025-11-25` | `initialize` возвращает capabilities |
| 3 | `tools/list`, `tools/call` | 16 data/team-tools + 3 catalog-tools | список и вызов работают |
| 4 | Схемы входа | `input_schema` (JSON Schema 2020-12) | невалидные аргументы отклоняются |
| 5 | Схемы выхода | `output_schema` + `structured_content` | ответ проходит валидацию |
| 6 | Аннотации | `read_only_hint: true`, `destructive_hint: false`, `idempotent_hint: true` | видны в `tools/list` |
| 7 | Компактный вывод | DTO, лимит символов, `truncated`, курсор | вызов ≤ 25k символов |
| 8 | Ошибки | `Tool::Response(error: true)`, доменные коды | модель видит понятный текст |
| 9 | Пагинация | курсоры в tools + `page_size:` списков | следующая страница доступна |
| 10 | Кэш-хинты хоста | `ttl_ms`, `cache_scope: "private"` | ресурсы/списки кэшируются корректно |
| 11 | Server instructions | `MCP::Server.new(instructions:)` | попадают в системный промпт opencode |
| 12 | Prompts | `jira:daily`, `jira:release-notes`, `jira:task-brief`, `jira:unblock`, `team:handoff`, `kb:answer` | `prompts/get` возвращает сообщения |
| 13 | Resources | `jira://issue/{key}`, `kb://page/{id}` | `resources/read` работает |
| 14 | Логи | Ougai только в `$stderr` | тест: stdout содержит только JSON-RPC |
| 15 | Наблюдаемость | `around_request`, `exception_reporter`, request_id | логи коррелируются |
| 16 | Отмена/прогресс | `server_context.cancelled?` в длинных циклах | опционально, не блокирует |
| 17 | Graceful shutdown | SIGINT/SIGTERM → транспорт, `disconnect!`, checkpoint | процесс выходит чисто |
| 18 | Безопасность | read-only токен, allowlist `project/space` на проект, БД `0600` | нет write-вызовов к Jira/Confluence |
| 19 | Секреты | только env, не в логах и аргументах | grep по логам чист |
| 20 | Таймауты/retry | connect 5s / read 20s, retry только GET/429/5xx | `429` уважает `Retry-After` |
| 21 | Keep-alive | один persistent `Net::HTTP` на origin, `keep_alive_timeout=30s`, reconnect на EOF/reset | повторные вызовы без нового TLS handshake |

---

## 8. Функциональные требования

### 8.1. Tools

| Tool | Аргументы | Возврат | Аннотации |
|---|---|---|---|
| `project_list` | — | каталог проектов: `id`, `key`, `name`, `style`, `capabilities`, `kb_space`, `aliases` | read-only, metadata only |
| `project_describe` | `project_id`, `include_query=false` | issue types, статусы, boards, поля, `query_presets`, `members`, `roles`, `component_leads`, `tools` | read-only, metadata only |
| `project_resolve` | `query` | кандидаты + `needs_confirmation`, без привязки | read-only, metadata only |
| `jira_my_work` | `scope` (`assigned`, `sprint`, `review`, `blocked`, `recent`), `limit=20`, `project_id?` | компактные issues + `why_now`, `next_action`, `blockers[]` | read-only, composite |
| `jira_search_issues` | `jql?` или `preset?`, `limit=25`, `cursor` | компактные issues + `next_cursor`; ровно один из `jql`/`preset` | read-only |
| `jira_get_issue` | `key`, `include[]` | issue + опц. comments/changelog/links | read-only |
| `jira_brief_issue` | `key`, `intent` (`understand`, `plan`, `verify`), `depth` (`standard`, `deep`), `include[]`, limits | issue + AC/decisions/open questions/dependencies/KB/similar/next actions | read-only, composite |
| `jira_get_changelog` | `key`, `limit`, `cursor` | field/from/to/author/at | read-only |
| `jira_list_attachments` | `key` | имя, размер, mime, url | read-only |
| `jira_unblock_issue` | `key?` или `query?`, `symptom?`, `window=30d`, `limit=5` | similar resolved, experts, recent changes, runbooks, hypotheses, questions | read-only, composite |
| `jira_list_sprints` | `board_id`, `state` | id, name, state, dates | read-only |
| `jira_get_sprint_issues` | `sprint_id`, `limit` | компактные issues | read-only |
| `kb_search` | `query?` или `cql?`, `preset?`, `limit=10`, `cursor` | CQL-результаты Confluence; ровно один из `query`/`cql`; `preset` — дополнительный фильтр | read-only |
| `kb_get_page` | `id` или `title`, `space` | title, url, текст (лимит) | read-only |
| `kb_list_children` | `page_id` | дочерние страницы | read-only |
| `team_who_knows` | `topic?`/`issue_key?`/`component?`/`label?`, `window=180d`, `limit=5`, `depth=standard` | люди, evidence, confidence, gaps, suggested questions | read-only, composite |
| `team_prepare_question` | `issue_key?`/`topic?`, `person?`, `goal`, `context?`, `urgency` | question packet: кому, что спросить, зачем, ссылки; без отправки | read-only, composite |
| `atlassian_whoami` | — | user, deployment, space id | read-only |
| `atlassian_cache_stats` | — | hits/misses/bytes/evictions | read-only |

Ограничения:

- JQL/CQL не парсятся семантически; используются пресеты, структурные builders и guarded escape hatch (§8.1.1).
- JQL всегда оборачивается в `project IN (<allowlist>) AND (<user_jql>)`; `project` и `ORDER BY` в пользовательском JQL запрещены.
- Confluence: `space IN (<allowlist>) AND (<user_cql>)`; `space` и `ORDER BY` в пользовательском CQL запрещены; кавычки экранируются.
- `fields` для Jira — явный allowlist.
- Allowlist берётся из проекта; `CLD` — значение по умолчанию для одного проекта.
- Вложения: только метаданные, без base64.
- `team_*` не отправляют сообщения; email не отдаётся без `TEAM_SHOW_EMAIL=1`; боты исключаются.
- Композитные tools возвращают partial result + `warnings[]`, если один источник недоступен.
- Вывод обрезается по `OUTPUT_CHAR_LIMIT` с флагом `truncated`.

#### 8.1.1. JQL/CQL: представление и использование

JQL (Jira Query Language) и CQL (Confluence Query Language) — это vendor-DSL для поиска, не SQL и не язык локальной БД. Сервер не интерпретирует их семантически: он передаёт их Atlassian, но оборачивает в allowlist и ограничивает.

Примеры:

```text
JQL: project = CLD AND status = "In Progress" ORDER BY updated DESC
CQL: space = CLD AND type = page AND text ~ "retry" ORDER BY lastmodified DESC
```

Используются три слоя:

| Слой | Где живёт | Кто использует | Назначение |
|---|---|---|---|
| **Presets** | `config.yml` проекта | `jira_my_work`, `jira_search_issues`, `kb_search` | типовые запросы команды без сочинения JQL/CQL моделью |
| **Structured builders** | `Query::Jql` / `Query::Cql` | `kb_search(query:)`, `team_*`, `jira_unblock_issue` | собирают безопасный запрос из аргументов и allowlist |
| **Guarded escape hatch** | те же классы | продвинутый пользователь | сырой JQL/CQL, но только после wrapper/валидации |

Пресеты в `config.yml`:

```yaml
queries:
  jql:
    my_work:
      label: "Моя работа"
      query: 'assignee = currentUser() AND statusCategory != Done'
      order_by: 'updated DESC'
      default_limit: 20
    blocked:
      label: "Заблокировано"
      query: 'status = Blocked OR flagged = Impediment'
      order_by: 'priority DESC'
      default_limit: 20
  cql:
    runbooks:
      label: "Runbooks"
      query: 'label = runbook AND type = page'
      order_by: 'lastmodified DESC'
      default_limit: 10
```

`project_describe` возвращает `query_presets: [{id, kind, label, description, default_limit}]`. Сырой `query` возвращается только при `include_query=true` — для отладки, не для модели по умолчанию. Пресеты хранятся без `ORDER BY`: сортировка лежит отдельно в `order_by`, чтобы сервер мог гарантировать стабильную пагинацию.

В JSON-схемах `jql`/`cql` — строки с `maxLength=QUERY_MAX_CHARS`; `preset` — строка, которая валидируется в рантайме (пресеты динамические, `enum` в схеме не фиксируем). `tools/list` не содержит сырых запросов — только аргументы; `project_describe.query_presets` — единственное место, где модель видит список доступных пресетов.

Как это выглядит в tool-схемах:

```text
jira_search_issues(jql: 'text ~ "timeout"', limit: 25)
  → project IN (CLD) AND (text ~ "timeout") ORDER BY updated DESC

jira_search_issues(preset: 'my_work', limit: 20)
  → берётся query + order_by из config.yml, без пользовательской строки

kb_search(query: 'retry timeout', preset: 'runbooks', limit: 10)
  → space IN (CLD) AND (label = runbook AND type = page) AND (text ~ "retry timeout")
    ORDER BY lastmodified DESC
```

Правила wrapper'а:

| Правило | JQL | CQL |
|---|---|---|
| Allowlist | `project IN (...)` | `space IN (...)` |
| Запрещено в user-строке | `project`, `ORDER BY`, `;`, control chars | `space`, `ORDER BY`, `;`, control chars |
| `ORDER BY` | добавляет сервер: `preset.order_by` или `updated DESC` | добавляет сервер: `preset.order_by` или `lastmodified DESC` |
| Экранирование | значения не переписываются, строка передаётся как есть | `"` и `\` экранируются в builder'е |
| Лимит длины | 2000 символов | 2000 символов |
| Лимит результатов | `limit` 1..50 | `limit` 1..50 |
| Баланс скобок/кавычек | проверяется | проверяется |

Важно:

- **Нет полного парсера JQL/CQL.** Это сознательно: языки развиваются, Cloud/DC отличаются, а полный парсер даст ложные отказы. Защита — allowlist-wrapper, запрет scope-полей, лимиты, таймауты и post-filter.
- **JQL/CQL никогда не попадают в SQLite как SQL.** SQLite-запросы параметризованы отдельно; JQL/CQL — только аргумент HTTP-запроса к Atlassian.
- **Поиск не кэшируется по умолчанию** (D13). При `CACHE_SEARCH=1` ключ включает `project`, `principal`, `deployment` и digest нормализованной строки; TTL 30–60 секунд.
- **Логи**: не пишем полную строку; пишем `query_kind`, `query_preset`, `query_sha256`, `length`.
- **Ошибки**: `query_invalid`, `query_scope_forbidden`, `query_too_large`, `query_timeout`, `query_rate_limited`, `query_preset_unknown`.
- **Cloud/DC**: JQL-семантика близка, но endpoint и пагинация разные (`nextPageToken` vs `startAt`); CQL идёт через v1 search в обоих, но поля/функции могут отличаться. Отличия закрывает capability probe (§8.3).

`jira_my_work` не принимает JQL: `scope` — это id пресета (`assigned` → `my_work`, `blocked` → `blocked`, `review` → `review_requested` и т.п.). Если пресета нет — `query_preset_unknown`, без fallback на «любой JQL».

`team_*` не используют JQL/CQL напрямую в аргументах: они строят bounded-запросы внутри (`text ~`, `component`, `label`, `space`) и возвращают evidence, а не сырые результаты поиска.

### 8.2. Resources и prompts

| Тип | URI/имя | Назначение |
|---|---|---|
| Resource | `jira://issue/{key}` | задача как адресуемый ресурс |
| Resource | `kb://page/{id}` | страница KB |
| Prompt | `jira:daily` | стендап по задачам |
| Prompt | `jira:release-notes` | релиз-ноты по preset/JQL |
| Prompt | `jira:task-brief` | brief задачи под `understand/plan/verify` |
| Prompt | `jira:unblock` | разбор ступора: prior art, эксперты, вопросы |
| Prompt | `team:handoff` | передача задачи/смены |
| Prompt | `kb:answer` | ответ по базе знаний со ссылками |

### 8.3. Deployment-матрица Jira/Confluence

Cloud и DC отвечают по-разным endpoint'ам и возвращают тело в разных форматах. Tools не знают про deployment: они работают с адаптерами `Jira::Client` и `Confluence::Client`, а различия инкапсулированы в матрице.

**Jira**

| Аспект | Cloud | DC |
|---|---|---|
| Auth | Basic: `JIRA_EMAIL` + `JIRA_API_TOKEN` | `Authorization: Bearer $JIRA_PAT` |
| REST | `/rest/api/3` | `/rest/api/2` |
| Search | `/rest/api/3/search/jql`; `nextPageToken`, `maxResults`; `total` может отсутствовать | `/rest/api/2/search`; `startAt`, `maxResults`, `total` |
| Тело | ADF: `description`, comments | wiki markup + `renderedFields` |
| Поля | `/rest/api/3/field` | `/rest/api/2/field` |
| Agile | `/rest/agile/1.0` | `/rest/agile/1.0` |

**Confluence**

| Аспект | Cloud | DC |
|---|---|---|
| Auth | Basic: `JIRA_EMAIL` + `JIRA_API_TOKEN` | `Authorization: Bearer $CONFLUENCE_PAT` |
| Страница | v2 `/wiki/api/v2/pages/{id}`, `body-format=view` | v1 `/wiki/rest/api/content/{id}?expand=body.view,version` |
| Поиск | CQL `/wiki/rest/api/content/search?cql=...` (v1) | CQL v1, тот же endpoint |
| Дети | v2 `/wiki/api/v2/pages/{id}/children`, `cursor` | v1 `/wiki/rest/api/content/{id}/child/page`, `start`/`limit` |
| Версия | `version.number` | `version.number` |

Правила:

- Курсор — opaque `base64url(JSON{v:1,k,t})`; внутри `nextPageToken` или `startAt`, наружу не раскрывается.
- `limit` ограничивается `1..50`; `next_cursor: null` означает конец.
- `total` опционален: Cloud может его не вернуть, нельзя на него опираться.
- Тело нормализуется в plain text: ADF → текст, `renderedFields`/`body.view` → текст через Nokogiri; в DTO остаётся `body_format`.
- Макросы `include`/`excerpt-include` не раскрываются.
- Capability-probe: `doctor` и первый запрос проверяют доступный endpoint, результат кэшируется на 24 ч в `global/reference.db`.
- `404/410` на предпочтительный endpoint → один fallback с warning в лог; если недоступны оба — `isError` с кодом `deployment_capability`.
- JQL: Cloud `/rest/api/3/search/jql` (`nextPageToken`), DC `/rest/api/2/search` (`startAt`); wrapper и `ORDER BY` одинаковые, но поля/функции проверяются capability-probe.
- CQL: поиск идёт через v1 `/wiki/rest/api/content/search` в обоих; различия — в доступных полях, функциях и `expand`, а не в wrapper'е.
- `atlassian_whoami` возвращает `deployment` и список доступных capabilities.
- Фикстуры: `fixtures/jira_cloud`, `jira_dc`, `confluence_cloud`, `confluence_dc`; contract-тесты через WebMock, CI-матрица `JIRA_DEPLOYMENT=cloud|dc`.

---

## 9. Модель данных SQLite

| Таблица | Назначение | Ключевые поля |
|---|---|---|
| `cache_entries` | L2-кэш | `ns, key, value_json, version, etag, last_modified, fetched_at, verified_at, expires_at, stale_until, size, accessed_at` |
| `kb_pages` | durable-зеркало KB (v1.1) | `id, space, version, lastmodified, title, url, text, fetched_at` |
| `delta_cursors` | синхронизация KB (v1.1) | `source, cursor, updated_at` |
| `schema_migrations` | AR | версия схемы |

Правила:

- Проектный файл `~/.local/share/jira-cld/<project>/cache.db`, права `0600`, каталог `0700`.
- Site-wide справочники: `~/.local/share/jira-cld/global/reference.db` (field map, statuses, space ids, capabilities probe на 24 ч).
- Метрики: `~/.local/share/jira-cld/stats.db`.
- `PRAGMA journal_mode=WAL`, `synchronous=NORMAL`, `busy_timeout=5000`, `temp_store=MEMORY`, `journal_size_limit=16777216`, `cache_size=-8192`, `mmap_size=67108864` (latency; fallback `0` по замеру).
- `cache.db`: `page_size=8192` до создания таблиц; `stats.db`/`reference.db` — 4096. Смена `page_size` — только новая БД или `VACUUM`.
- `max_page_count` = `CACHE_MAX_BYTES / page_size` с запасом; при `SQLITE_FULL` — evict и retry.
- Чтение кэша не пишет: `accessed_at` на hit не обновляется; eviction — сначала по `expires_at`, затем FIFO по `fetched_at`.
- Запись — upsert `ON CONFLICT(ns,key) DO UPDATE`, `BEGIN IMMEDIATE`, батч на запрос/64 записи; `wal_checkpoint(PASSIVE)` после батча, `TRUNCATE` на SIGTERM и после `cache clear`.
- `PRAGMA optimize` + `analysis_limit=400` на закрытии; `ANALYZE` после миграций. `auto_vacuum=NONE`, `secure_delete=OFF`.
- `DatabaseStore` использует `connection.select_value`/`exec_query` и не инстанцирует модели; AR остаётся для схемы/миграций.
- Индексы: только unique `(ns, key)`; отдельного индекса на `accessed_at` нет.
- `cache_entries` очищаемая (`bin/jira-cld cache clear --project <id>`); `kb_pages`/`delta_cursors` появляются в v1.1 и `cache clear` их не трогает.
- В v1 текст страниц кэшируется лениво в `cache_entries` (namespace `page`); отдельного зеркала и прогрева нет.
- Значения сериализуются JSON, не Marshal.
- `WITHOUT ROWID` и FTS5 — только через raw SQL при необходимости.

---

## 10. Кэш

### 10.1. Уровни

| Уровень | Реализация | Роль |
|---|---|---|
| L1 | `ActiveSupport::Cache::MemoryStore` | горячие чтения, TTL, байтовый лимит |
| L2 | `DatabaseStore < AS::Cache::Store` → AR/SQLite | переживание рестарта, общий для процессов на одной машине |

`TieredStore` сначала читает L1, затем L2 и прогревает L1. Запись — в оба уровня.

Ограничения и latency-правила:

- L1 `MemoryStore` — `CACHE_L1_BYTES=8388608`; L2 — `CACHE_MAX_BYTES=16777216`.
- Hit path не пишет в L2: L1 read, L2 read + promote в L1. `accessed_at` — только диагностика, на чтении не обновляется.
- Запись — `write_multi`/`commit_batch`: один `BEGIN IMMEDIATE` на запрос или 64 записи/1 MB; flush в `around_request`, на SIGTERM и перед `cache clear`. Потеря последнего батча при crash допустима.
- Eviction: сначала `expires_at`, затем FIFO по `fetched_at`, батчами 5–10%; footprint считать по `page_count - freelist_count`, без `SUM(size)` на каждой записи.
- `PRAGMA`-настройки и `DatabaseStore` — по D34/§9; `select_value`/`exec_query` без моделей AR.

### 10.2. TTL и ревалидация

| Namespace | TTL | Ревалидация |
|---|---|---|
| identity | 1 ч | — |
| reference (fields, space, project) | 6–12 ч | — |
| issue | 60 с | probe `fields=updated` |
| comments/changelog | 60–120 с | по `updated` issue |
| page meta | 10 мин | probe `version.number` |
| page text | по версии | версия неизменна |
| children | 5 мин | TTL |
| search | 30–60 с (по умолчанию off) | — |
| negative 404 | 30 с | — |

Фазы записи: `fresh → revalidate → stale → hard expiry`.

- `version` входит в ключ: после обновления старая запись недостижима.
- ETag/Last-Modified → conditional GET, `304` продлевает TTL.
- Confluence probe: `GET /wiki/api/v2/pages/{id}` без `body-format`.
- Jira probe: `GET /rest/api/3/issue/{key}?fields=updated`.
- `stale_if_error` только для reference/pages, с флагом `stale: true` в ответе.
- 401/403/429/5xx не кэшируются; 404 — только negative 30 с.
- `race_condition_ttl` для защиты от stampede.

### 10.3. Инвалидация

- TTL и версия — основные механизмы; write-операций нет.
- `query_presets` входят в project metadata; изменение `config.yml` инвалидирует metadata/поисковый namespace.
- При `CACHE_SEARCH=1` ключ поиска: `project`, `principal`, `deployment`, `query_sha256`, `preset_revision`; TTL 30–60 с.
- При `401` очищать `identity` и namespace principal.
- Без `principal` в ключе кэш между пользователями не разделяется — недопустимо при per-user токенах.

---

## 11. Конфигурация

| Переменная | Значение по умолчанию |
|---|---|
| `JIRA_BASE_URL` | обязательна |
| `JIRA_DEPLOYMENT` | `cloud` |
| `JIRA_EMAIL`, `JIRA_API_TOKEN` | для Cloud |
| `JIRA_PAT` | для DC |
| `CONFLUENCE_BASE_URL` | `JIRA_BASE_URL/wiki` для Cloud |
| `CONFLUENCE_PAT` | для DC |
| `CLD_SPACE` | `CLD` |
| `KB_ENABLED` | `true` |
| `MCP_LOCALE` | `ru` |
| `OUTPUT_LANG` | `ru` |
| `OUTPUT_CHAR_LIMIT` | `24000` |
| `DB_PATH` | `~/.local/share/jira-cld/<project>/cache.db` |
| `REFERENCE_DB_PATH` | `~/.local/share/jira-cld/global/reference.db` |
| `DB_AUTO_MIGRATE` | `1` |
| `CACHE_ENABLED` | `1` |
| `CACHE_L1_BYTES` | `8388608` |
| `CACHE_MAX_BYTES` | `16777216` |
| `CACHE_MAX_ENTRY_BYTES` | `262144` |
| `CACHE_SEARCH` | `0` |
| `CACHE_STALE_GRACE` | `600` |
| `CACHE_WRITE_BATCH` | `64` |
| `DB_CACHE_SIZE_KB` | `8192` |
| `DB_MMAP_BYTES` | `67108864` |
| `DB_PAGE_SIZE` | `8192` (только `cache.db`) |
| `DB_JOURNAL_SIZE_LIMIT` | `16777216` |
| `HTTP_KEEP_ALIVE` | `1` |
| `HTTP_KEEP_ALIVE_TIMEOUT` | `30` |
| `HTTP_TIMEOUT_MS` | `20000` |
| `QUERY_MAX_CHARS` | `2000` |
| `TEAM_SHOW_EMAIL` | `0` |
| `TEAM_WINDOW_DAYS` | `180` |
| `LOG_LEVEL` | `info` |
| `LOG_FORMAT` | `json` |
| `MCP_PROJECT_ID` | обязательна для `mcp`; fail closed |
| `CONFIG_PATH` | `~/.config/jira-cld/config.yml` |
| `SECRET_PROVIDER` | `env` (`env`/`keyring`/`command`/`file`) |
| `STATS_PATH` | `~/.local/share/jira-cld/stats.db` |
| `STATS_ENABLED` | `1` |
| `STATS_RETENTION_DAYS` | `7` |
| `UI_PORT` | `0` (эфеверный) |
| `UI_OPEN` | `1` |
| `UI_LOCALE` | `MCP_LOCALE` |
| `UI_THEME` | `system` (`system`/`light`/`dark`) |

Приоритет: CLI-флаги → env → `--config` → проектный конфиг → глобальный конфиг → значения по умолчанию.

Локаль: по умолчанию `ru`; `MCP_LOCALE`, `OUTPUT_LANG`, `UI_LOCALE` — явные override. `LANG`/`LC_*` не читаются. Тема: `UI_THEME=system` по умолчанию, допустимы `light`/`dark`.

`DB_PAGE_SIZE` применяется только к новому `cache.db`; для существующей БД нужен `VACUUM`. `DB_MMAP_BYTES=0` отключает mmap. `DB_CACHE_SIZE_KB` — на соединение; для UI пула учитывать `pool * cache_size`.

`config.yml` (схема v1):

```yaml
schema: 1
connections:
  jira:   { base_url: "...", deployment: "cloud", token_ref: "env:JIRA_API_TOKEN", email: "..." }
  confluence: { base_url: "...", token_ref: "env:CONFLUENCE_PAT" }
projects:
  alpha:
    name: "Alpha"
    jira_keys: ["ALP"]
    spaces: ["ALP_KB"]
    style: "scrum"
    related_scopes: []
    queries:
      jql:
        my_work:
          label: "Моя работа"
          query: 'assignee = currentUser() AND statusCategory != Done'
          order_by: 'updated DESC'
          default_limit: 20
        blocked:
          label: "Заблокировано"
          query: 'status = Blocked OR flagged = Impediment'
          order_by: 'priority DESC'
          default_limit: 20
      cql:
        runbooks:
          label: "Runbooks"
          query: 'label = runbook AND type = page'
          order_by: 'lastmodified DESC'
          default_limit: 10
    team:
      show_email: false
      channels:
        - { name: "#alpha-dev", url: "https://chat.example/#alpha-dev" }
cross_scope:
  mode: confirm          # deny | declared | confirm
  grant_ttl: 3600
  cache: false
ui:
  locale: "ru"
  theme: "system"
```

---

## 12. Порядок загрузки

```
Config (config.yml + ENV + SecretStore → frozen Struct, валидация)
  → проверка MCP_PROJECT_ID (fail closed)
  → bootstrap-логгер в $stderr
  → Ougai (Bunyan JSON)
  → I18n (locale, load_path, backend)
  → Zeitwerk (setup, инфлекторы, без eager_load)
  → ActiveRecord (standalone, без Railties)
  → DB.connect проекта + REFERENCE + PRAGMA + (DB_AUTO_MIGRATE ? migrate)
  → Cache::TieredStore (L1 MemoryStore + L2 DatabaseStore)
  → Stats::Writer
  → HTTP::Client (net/http/openssl — lazy require при первом запросе)
  → Repositories
  → Tools (title/description через I18n)
  → MCP::Server (instructions, page_size, ttl_ms, cache_scope)
  → StdioTransport.open
```

I18n — до сборки tools: `MCP::Tool` вычисляет `description` при загрузке класса.

`nokogiri` грузится лениво в KB-репозитории при первом `kb_*`; `active_support/all` и `core_ext` целиком не подключаются (D37). AR остаётся в runtime (D31), но `DatabaseStore` не создаёт модели.

`bin/jira-cld` по умолчанию выставляет `RUBY_GC_HEAP_GROWTH_FACTOR=1.1` и `RUBYOPT=--disable=did_you_mean,error_highlight,syntax_suggest` (если не заданы); для `ui` добавляет `MALLOC_ARENA_MAX=2`. YJIT для `mcp` не включается; для UI — только по результатам профиля.

---

## 13. Логирование и наблюдаемость

- `Ougai::Logger.new($stderr)`, formatter `Bunyan` (JSON lines).
- Поля: `service`, `version`, `site`, `deployment`, `request_id`, `method`, `tool`.
- `MCP.configure`: `exception_reporter` → `LOG.error`; `around_request` → старт/финиш, тайминг.
- `ActiveRecord::Base.logger = nil` или debug-канал Ougai.
- Не логировать токены, тела страниц, полные JQL/CQL; ключи кэша и query digest — хэш.
- `server_context._meta` использовать для `traceparent`/session id.
- Метрики кэша: hits/misses/revalidated/stale/evictions/bytes.

---

## 14. Безопасность

- Read-only токен/аккаунт: к Jira/Confluence только GET. Локальные мутации UI не ходят в API.
- Allowlist: Jira `project IN (...)` и Confluence `space IN (...)` из конфига проекта.
- JQL/CQL: wrapper + запрет `project`/`space`/`ORDER BY`/`;`; лимит длины и результатов; запрос не исполняется локально (см. §8.1.1).
- Секреты — только env; не передавать аргументами CLI.
- SQLite и WAL-файлы `0600`; каталог `0700`.
- Вывод моделей обрезать, не отдавать сырые ADF/HTML.
- Не писать в stdout ничего, кроме JSON-RPC.

UI и headless:

- UI слушает только `127.0.0.1`, эфемерный порт, одноразовый токен → HttpOnly cookie.
- CSRF-токен на все мутации: wizard, cache clear, delete; `SameSite=Strict`.
- CSP `default-src 'self'; form-action 'self'`; ассеты только локальные, без CDN.
- Секреты не отдаются в HTML/JSON/логи; только маска и статус.
- Destructive-операции: только POST + typed confirm + audit; удаление проекта — soft-delete в `.trash`; активный проект удалить нельзя.
- CLI не печатает секреты; `--dry-run` показывает diff без значений.
- `doctor` и `setup` завершаются с ненулевым кодом при ошибке.

---

## 15. Тестирование

| Уровень | Что проверяется |
|---|---|
| Unit | `DatabaseStore` (TTL/FIFO/eviction, `select_value`, без моделей), policy, key normalization, ADF/HTML renderer |
| Query | JQL/CQL wrapper: allowlist, запрет `project`/`space`/`ORDER BY`, экранирование, лимиты, пресеты |
| Contract | WebMock-фикстуры Cloud/DC, пагинация `nextPageToken`/`startAt`, маппинг 401/403/404/429/5xx |
| Integration | `MCP::Client::Stdio` → `tools/list`/`tools/call`, аргументы через JSON-round-trip |
| Purity | `$stdout` содержит только JSON-RPC |
| DB | `:memory:` + `pool: 1`, миграции, WAL/checkpoint; hit не пишет; upsert/батч; pragma-контракт |
| Perf | `memory_profiler`, `stackprof`, `VmRSS` до/после `require`, L2 get/upsert p95, GC, WAL, бюджеты §3 |
| HTTP | keep-alive reuse, reconnect на EOF/reset, таймауты и retry |
| Composite | `brief`/`unblock`: partial result, `warnings[]`, лимиты, citations, отсутствие падения при недоступном KB |
| Team | evidence-ranking, `confidence`, `gaps`, исключение ботов, email только при `TEAM_SHOW_EMAIL=1`, никакой отправки |
| i18n | паритет ключей и плейсхолдеров между локалями |
| CLI | `setup --non-interactive`, `doctor`, `stats --json`, `projects remove`, коды возврата |
| Isolation | два проекта: disjoint данные, кэш/негативный кэш не пересекаются, `.trash` и stats |
| UI | wizard add/edit, cache clear/delete с confirm и CSRF, активный проект, темы, локаль |
| Headless | `mcp` без `:ui`-гемов; `$stdout` чист; assets не читаются |

---

## 16. Критерии приёмки v1

1. `opencode mcp list` → `connected`.
2. `tools/list` возвращает 19 инструментов (16 data/team + 3 catalog) со схемами и аннотациями.
3. `jira_search_issues` по CLD с лимитом и курсором, вывод ≤ 25k.
4. `jira_brief_issue` собирает issue + AC + comments + links + KB за один вызов; `intent=verify` даёт AC-checklist.
5. `jira_unblock_issue` возвращает prior art, экспертов, runbooks и вопросы; при недоступном KB — partial + warning.
6. `team_who_knows` возвращает evidence/`confidence`/`gaps`, исключает ботов и не отдаёт email по умолчанию.
7. `team_prepare_question` формирует 3–5 вопросов с `reason`/`evidence` и ничего не отправляет.
8. `kb_get_page` отдаёт читаемый текст без макросов.
9. Повторный вызов — cache hit; после смены версии страницы — revalidate.
10. `401/429` дают `isError` с кодом и подсказкой, не «internal error».
11. stdout чист, логи только в stderr.
12. RSS ≤ 60 MB, cold start ≤ 400 ms; замер на релизном кандидате.
13. `bundle exec rake test` и `rubocop` зелёные.
14. SIGTERM завершает процесс с checkpoint и `disconnect!`.
15. `bin/jira-cld setup --non-interactive ...` создаёт валидный `config.yml` без UI.
16. `bin/jira-cld doctor` проверяет конфиг, секреты, capability probe, Jira/Confluence, БД, пространства.
17. `bin/jira-cld stats --json` отдаёт агрегаты без запуска UI.
18. `bin/jira-cld cache stats` и `cache clear` работают без UI.
19. Headless-установка (`without: ui`) не загружает `roda`/`puma`/`rack` и не читает `assets/ui`.
20. `bin/jira-cld mcp` без `MCP_PROJECT_ID` падает с понятной ошибкой (fail closed).
21. UI: активный проект, тёмная тема, RU/EN, uPlot, wizard add/edit; Cache clear и Delete только с confirm и CSRF.
22. `projects remove` переносит каталог в `.trash`, убирает запись из `config.yml`, сохраняет `stats.db`; активный проект в UI удалить нельзя.
23. `rake assets:verify` подтверждает SHA256 вендоренных ассетов.
24. Cache hit (L1/L2) не выполняет запись; `accessed_at` не меняется; WAL не растёт на hit.
25. L2 get p95 ≤ 2 ms на тёплом кэше (AR `select_value`); batch upsert 64 записи p95 ≤ 10 ms.
26. PRAGMA-контракт: WAL, `synchronous=NORMAL`, `cache_size=8192 KB`, `mmap_size=64 MB` (или `0` по замеру), `page_size=8192` для `cache.db`, `temp_store=MEMORY`, `journal_size_limit=16 MB`.
27. Ruby-профиль: `RUBY_GC_HEAP_GROWTH_FACTOR=1.1`, disable `did_you_mean`/`error_highlight`/`syntax_suggest`, без YJIT для MCP; UI — `MALLOC_ARENA_MAX=2`.
28. HTTP keep-alive: повторные вызовы переиспользуют соединение, нового TLS handshake нет.
29. JQL/CQL wrapper: `project`/`space`/`ORDER BY` в user-строке отклоняются; allowlist добавляется сервером; полная строка не пишется в лог.
30. `jira_my_work` использует только preset id; неизвестный preset → `query_preset_unknown`, без fallback на произвольный JQL.

---

## 17. Фазы

| Фаза | Содержание |
|---|---|
| 0 | Boot, config, Ougai, I18n, Zeitwerk, пустой MCP-сервер, ping |
| 1 | DB: миграции, pragmas, `cache_entries`, `DatabaseStore`, `TieredStore`; read-only hit path, batch upsert, `page_size=8192` |
| 2 | Jira: HTTP-клиент с keep-alive, Cloud/DC адаптер, capability probe, auth, errors, `Query::Jql`, `search_issues`, `get_issue`, `jira_my_work` |
| 3 | Jira: changelog, attachments, agile, `jira_brief_issue` |
| 4 | Confluence KB: Cloud/DC адаптер, space resolve, `Query::Cql`, `body.view` → text, `kb_*`, `team_who_knows` |
| 5 | `team_prepare_question`, `jira_unblock_issue`, Resources, prompts, instructions, i18n-паритет |
| 6 | Ревалидация по версии/ETag, stale-if-error, `cache_stats`, latency p95 |
| 7 | Тесты, CI, замер памяти и latency, README, `opencode.json` |
| 8 | Изоляция проектов: реестр, `MCP_PROJECT_ID`, каталог-tools, post-filter, кросс-scope |
| 9 | Headless CLI: `setup`, `doctor`, `projects`, `stats`, `cache`, `db`, `export` |
| 10 | UI: shell, дерево, Overview, uPlot, Projects/wizard, Cache/Checks, destructive-операции, темы и локали |
| 11 | Упаковка: `:ui`-группа, headless-образ, `assets:verify`, CI-матрица, релиз |
| 12 | v1.1: KB-зеркало (`kb_pages`, `delta_cursors`), прогрев, локальный поиск |

---

## 18. Путь развития для команды

```
stdio + SQLite
   │  нужен общий сервер
   ▼
HTTP + Puma + ingress + OAuth
   │  нужны HA/общий кэш
   ▼
Postgres (AR-адаптер) + Redis (RedisCacheStore)
```

Меняются только адаптеры AR/AS и транспорт; `tools`, `repositories`, `Cache` facade остаются.

---

## 19. Изоляция проектов

Модель: **каталог метаданных + явная привязка**. Каталог помогает выбрать проект, но не даёт доступ к контенту.

### 19.1. Привязка

- `MCP_PROJECT_ID` обязателен для `bin/jira-cld mcp`; без него — отказ на старте.
- Нет «проекта по умолчанию» и угадывания по JQL/тексту.
- UI-активный проект — только контекст интерфейса, не меняет привязку MCP-сервера.
- Неизвестный проект → `isError`, без обращения к Jira/Confluence.

### 19.2. Хранилище

```
~/.local/share/jira-cld/
├── global/reference.db      # site-wide: field map, statuses, space ids, capabilities
├── stats.db                 # метрики, project в каждой строке
├── alpha/cache.db           # задачи, страницы, поиск, negative
├── alpha/meta.json
├── beta/cache.db
└── .trash/<id>-<UTC>/       # soft-deleted projects
```

- Проектные данные не покидают каталог проекта.
- Ключ кэша: `v1:<project>:<site>:<principal>:<ns>:<logical>`.
- `global/reference.db` не содержит задач и страниц.
- Удаление `alpha/cache.db` не затрагивает `beta/` и `stats.db`.
- `projects remove` и UI `Delete`: запись в `config.yml` убирается атомарно, каталог `<project>/` переносится в `.trash/<id>-<UTC>/`; `stats.db` и `global/reference.db` не трогаются.
- `--purge` удаляет запись из `.trash`; активный проект в UI удалить нельзя, CLI требует `--yes`.
- Строки `stats.db` удалённого проекта сохраняются, но в UI не показываются (нет проекта в конфиге).
- Путь проекта никогда не берётся из пользовательского ввода: только id из реестра + канонический путь.
- Уже запущенный MCP с удалённым проектом продолжает работать до рестарта; после рестарта — fail closed по `MCP_PROJECT_ID`.

### 19.3. Каталог

`project_list`, `project_describe`, `project_resolve`:

- только метаданные (ключи, стиль, capabilities, boards, поля, KB space, `query_presets`, `members`, `roles`, `component_leads`);
- `project_resolve` возвращает кандидатов и `needs_confirmation`, но **никогда не привязывает**;
- список фильтруется по правам токена и allowlist.

### 19.4. Жёсткие границы

| Уровень | Правило |
|---|---|
| JQL | `project IN (<allowlist>) AND (<user_jql>)`; `project`/`ORDER BY` в пользовательском JQL запрещены |
| CQL | `space IN (<allowlist>) AND (<user_cql>)`; `space`/`ORDER BY` в пользовательском CQL запрещены |
| Team | evidence только из allowlist issues/pages; профили без email по умолчанию; боты исключены |
| Post-filter | каждый issue `key` и page `space` проверяются; иначе ошибка |
| Ссылки | issue links/remote links возвращаются ссылкой, без авто-фетча |
| Confluence | `include`/`excerpt-include` не раскрываются |
| Аудит | `project_id`, `scope`, `binding_source` в каждой строке |

### 19.5. Кросс-scope

Режимы: `deny` (по умолчанию для необъявленного), `declared` (связь в конфиге), `confirm` (явное подтверждение пользователя).

- Кросс-scope не пишется в проектное зеркало и по умолчанию не кэшируется.
- Ответ маркируется по scope; массивы разных scope не объединяются.
- Частичный доступ: `X: ok`, `Y: forbidden`, без падения всего вызова.
- Модель не расширяет scope самостоятельно.

---

## 20. UI/UX

Локальная консоль для настройки и статистики. Стиль — «приборная ведомость»: центрированная оболочка, воздух по бокам, тихое дерево слева, плотные таблицы справа. Не SaaS-карточки.

### 20.1. Границы

| Область | Доступ |
|---|---|
| Overview / Checks | чтение |
| Cache | чтение + очистка с подтверждением |
| Projects | чтение + add/edit/delete (soft) |
| Connections / Diagnostics / Settings | чтение |
| Wizard (add/edit) | запись `config.yml`, атомарно |
| Checkpoint | CLI/конфиг |

```
┌ jira-cld mcp ──────────┐        ┌ jira-cld ui ───────────┐
│ stdio, без UI-гемов    │        │ 127.0.0.1, Roda + Puma │
└───────────┬────────────┘        └───────────┬────────────┘
            │ читает                          │ читает
            ▼                                 ▼
   config.yml (0600) ◄────────────── wizard + delete (atomic write)
   cache/<project>/cache.db ◄──────── read; cache clear
   stats.db ◄─────────────────────── read-only
```

UI-мутации ограничены: `config.yml` (wizard, delete), `cache.db` (clear), `.trash` (soft-delete). Записи в Jira/Confluence нет.

### 20.2. Активный проект

- Один активный проект: селектор в шапке + cookie `jira_cld.project`.
- URL `/projects/:id/...` важнее cookie.
- Если проект исчез из конфига — редирект на первый доступный с уведомлением.

### 20.3. Информационная архитектура

```
Projects
  Alpha  (active)
  Beta
Connections
Diagnostics
Settings
```

Внутри проекта — вкладки `Overview / Cache / Checks`. Глубина дерева — 1 уровень + вкладки.

### 20.4. Каркас

```
│← 96px →│                 shell 1200px                 │← 96px →│

  ┌──────────────────────────────────────────────────────────────┐
  │ ruby-jira-mcp        alpha ▾     RU/EN  ◐     [ok] live     │
  ├──────────────┬───────────────────────────────────────────────┤
  │ Projects   ▾ │ Projects / Alpha              [Test] [Edit]   │
  │   Alpha  ●   │ ───────────────────────────────────────────── │
  │   Beta       │ Overview   Cache   Checks                     │
  │ Connections  │ ───────────────────────────────────────────── │
  │ Diagnostics  │ Activity · last 1h                            │
  │ Settings     │ ▁▂▃▅▆▇▆▅▃▂▁▁▂▃▅▇█▇▅▃▂▁  hit 82% err 3 429 1  │
  │              │ Requests 1,284  Hit 82%  Saved 1,052  p95 410│
  │              │ Recent calls                                  │
  │              │ 10:42  kb_get_page        hit    12   ok      │
  └──────────────┴───────────────────────────────────────────────┘
```

- `max-width: 1200px`, `padding-inline: clamp(20px, 6vw, 96px)`.
- Сетка: `240px` + `40px` + `minmax(0,1fr)`.
- `≤ 900px`: дерево в `<details>`, вкладки и таблицы со скроллом.

### 20.5. Токены

| Токен | Light | Dark |
|---|---|---|
| `--paper` | `#EFF1EC` | `#101315` |
| `--surface` | `#F7F8F4` | `#171B1E` |
| `--ink` | `#121517` | `#E7EAE5` |
| `--muted` | `#5E6661` | `#98A19A` |
| `--rule` | `#C9CEC6` | `#2A3034` |
| `--accent` | `#1B4DD8` | `#8AA6FF` |
| `--ok` | `#1C6B4A` | `#63D6A3` |
| `--warn` | `#8A5A00` | `#E3AC52` |
| `--error` | `#A8231B` | `#FF7A70` |

- Типографика: IBM Plex Sans + IBM Plex Mono (кириллица), `tabular-nums`.
- Шкала 12/13/15/18/24; строки таблиц 36 px; радиус 2 px; теней нет.
- Тема: `system` по умолчанию, ручной toggle, `localStorage`, без FOUC.
- Статусы текстом `[ok]/[warn]/[fail]`, не только цветом.

### 20.6. Экраны

| Экран | Содержание |
|---|---|
| Overview | activity strip, 4 показателя, recent calls, alerts, диапазоны `15m/1h/24h/7d` |
| Cache | таблица namespace: entries/bytes/hit/expired/oldest; очистка `expired`/`all` |
| Checks | Jira, Confluence, space resolve, срок токена; read-only вызовы |
| Projects | список + Open/Edit/Delete (soft); Add project |
| Wizard | 5 шагов: Jira → Confluence → Project → Cache → Review; add/edit, без удаления |
| Connections | endpoints, deployment, статус токена, последняя проверка |
| Diagnostics | конфиг, доступность, `integrity_check`, пути, `Copy opencode.json`, `Export` |
| Settings | текущие значения; изменение — wizard/конфиг |

Потоки destructive-операций:

- **Delete project:** Projects → Delete → модалка с последствиями (запись в `config.yml`, каталог → `.trash`, статистика остаётся) → ввод `project_id` → `POST /projects/:id/delete` + CSRF. Активный проект удалить нельзя.
- **Cache clear:** Cache → Clear → scope `expired`/`all`, опционально namespace → `POST /projects/:id/cache/clear` + CSRF. Очистка идёт только по выбранному проекту.
- **Wizard:** только add/edit; удаление в wizard недоступно.

### 20.7. Данные и графики

- `stats.db`: `metric_events` (7 дней) + `metric_counters` (постоянно).
- uPlot: activity (stacked bars), latency p50/p95, cache hit rate; ≤120 точек.
- Диапазоны: `15m/1h/24h/7d`; другие не поддерживаются.
- Цвета серий из CSS-переменных; при смене темы график пересоздаётся.
- `role="img"` + `aria-label` + скрытая таблица-дубль; без JS — сводная таблица.

### 20.8. Реализация

| Слой | Решение |
|---|---|
| Роутинг | Roda |
| Шаблоны | Erubi/ERB |
| Интерактив | HTMX + ~4 KB своего JS |
| Графики | uPlot (vendored) |
| Стили | свой CSS (~12 KB) |
| Шрифты | IBM Plex, woff2 |
| Сервер | Puma, только при `bin/jira-cld ui` |

Бюджет: страница < 250 KB, JS < 60 KB. Polling 5 с, без SSE/WebSocket/Node/CDN.

### 20.9. Безопасность UI

- `127.0.0.1`, эфемерный порт, одноразовый токен → HttpOnly cookie.
- CSRF на все мутации: wizard, cache clear, delete; `SameSite=Strict`, CSP `default-src 'self'; form-action 'self'`.
- Только POST для мутаций; GET ничего не удаляет и не очищает.
- Delete: подтверждение вводом `project_id`, soft-delete в `.trash`, активный проект удалить нельзя.
- Cache clear: подтверждение, scope `expired`/`all`, опционально namespace.
- Каждая мутация пишет audit-строку (`project_id`, `action`, `source=ui`, `request_id`).
- Секреты только маской; UI-процесс не встроен в MCP-сервер и не влияет на stdout.

---

## 21. Headless-сценарии

Принцип: **headless — first-class**. Всё, кроме визуального UI, доступно из CLI; headless-режим не загружает UI-гемы и ассеты.

### 21.1. Режимы запуска

| Команда | Назначение |
|---|---|
| `bin/jira-cld mcp` | stdio MCP-сервер (production) |
| `bin/jira-cld ui` | локальный UI (опционально) |
| `bin/jira-cld setup` | интерактивная настройка → `config.yml` |
| `bin/jira-cld setup --non-interactive ...` | скриптуемая настройка |
| `bin/jira-cld doctor` | проверка конфига, секретов, сети, БД |
| `bin/jira-cld projects list`, `projects add`, `projects edit`, `projects remove` | каталог, изменения и soft-delete проектов |
| `bin/jira-cld stats` | статистика в таблице (`--json`, `--csv`) |
| `bin/jira-cld cache stats`, `cache clear` | просмотр/очистка кэша |
| `bin/jira-cld db migrate`, `db check`, `db vacuum` | обслуживание SQLite |
| `bin/jira-cld config show`, `config validate`, `config path` | конфиг без секретов |
| `bin/jira-cld config print-opencode` | сниппет `opencode.json` |
| `bin/jira-cld export diagnostics` | redacted-бандл |
| `bin/jira-cld console` | irb + boot |

```
config.yml + env + SecretStore
            │
            ▼
    bin/jira-cld mcp ──► stdout: JSON-RPC
            │
            ├─ cache/<project>/cache.db
            ├─ stats.db (batched)
            └─ global/reference.db
```

### 21.2. Non-interactive setup

```bash
bin/jira-cld setup --non-interactive \
  --jira-url https://acme.atlassian.net \
  --deployment cloud \
  --email dev@acme.io \
  --token-ref env:JIRA_API_TOKEN \
  --confluence-url https://acme.atlassian.net/wiki \
  --space ALP_KB \
  --project alpha --jira-key ALP \
  --locale ru
```

- Валидирует схему, секреты, доступность, resolve пространства.
- Пишет `config.yml` атомарно с `.bak`; `--dry-run` показывает diff без секретов.
- Код возврата `≠ 0` при любой ошибке; пригодно для CI/Ansible.

### 21.3. Секреты

`SecretStore`: `env` (по умолчанию), `keyring` (`secret-tool`), `command` (`op read`, `pass show`), `file` (`0600`). В конфиге только `token_ref`, не значение. `doctor` проверяет разрешимость ссылок, не печатая секрет.

### 21.4. Статистика без UI

```bash
bin/jira-cld stats --project alpha --range 1h
bin/jira-cld stats --json | jq
bin/jira-cld stats --csv > stats.csv
```

- Читает `stats.db`; UI не нужен.
- `cache stats` — таблица по namespace.
- `cache clear --project alpha [--namespace issue] [--scope expired|all] [--yes]`.
- `projects remove --project alpha [--purge] [--yes]`: soft-delete в `.trash`; `--purge` удаляет запись из `.trash`.

### 21.5. Doctor: проверки и коды

Проверки: схема конфига, `MCP_PROJECT_ID`, секреты, Jira `myself`, capability probe (Cloud/DC), Confluence space resolve, права, writable DB, `PRAGMA integrity_check`, свободное место, версии, размер `.trash`.

`--offline` пропускает сетевые проверки; `stats`, `config validate`, `cache stats` работают без сети.

| Код | Значение |
|---|---|
| 0 | ok |
| 2 | невалидный конфиг |
| 3 | auth failed |
| 4 | проект/пространство не найдены |
| 5 | ошибка БД |
| 6 | сеть/таймаут |
| 7 | rate limited |
| 8 | секрет не разрешён |
| 9 | deployment capability недоступна |

### 21.6. Паритет headless и UI

| Возможность | CLI | UI |
|---|---|---|
| Настройка соединений | setup | wizard |
| Проекты add/edit | setup / projects add/edit | wizard |
| Удаление проекта | projects remove (soft) | Delete (soft) |
| Статистика | stats | Overview |
| Кэш: просмотр | cache stats | Cache |
| Кэш: очистка | cache clear | Cache |
| Диагностика | doctor | Diagnostics |
| `opencode.json` | config print-opencode | кнопка |
| Темы, графики | нет | да |

### 21.7. Headless-ограничения

- `bin/jira-cld mcp` не требует `rack`, `roda`, `puma`, `erubi`, `uplot`, `htmx`.
- `bin/jira-cld ui` без `:ui`-группы завершается с кодом `2` и подсказкой установить группу.
- `nokogiri` загружается только при `KB_ENABLED`.
- Логи — только `$stderr`; `LOG_FILE` опционален.
- MCP-процесс не открывает портов.

### 21.8. Сценарий: только MCP

```bash
bundle config set --local without 'ui'
bundle install

export JIRA_BASE_URL=https://acme.atlassian.net
export JIRA_EMAIL=dev@acme.io
export JIRA_API_TOKEN=...
export MCP_PROJECT_ID=alpha

bin/jira-cld doctor
bin/jira-cld mcp
```

`opencode.json` проекта:

```jsonc
{
  "mcp": {
    "servers": {
      "jira-alpha": {
        "type": "local",
        "command": ["bundle", "exec", "bin/jira-cld", "mcp"],
        "cwd": "/path/to/ruby-jira-mcp",
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

- UI-гемы не устанавливаются и не загружаются.
- Метрики пишутся в `stats.db`; просмотр — `bin/jira-cld stats`.
- Конфиг и секреты — через env или `setup --non-interactive`.

---

## 22. Сборка и упаковка

### 22.1. Bundler-группы

```ruby
gem "mcp"; gem "activerecord"; gem "activesupport"; gem "sqlite3"
gem "i18n"; gem "ougai"; gem "zeitwerk"

group :kb do
  gem "nokogiri", require: false
end

group :ui do
  gem "rack"; gem "puma"; gem "roda"; gem "erubi"
end

group :development, :test do
  gem "minitest"; gem "webmock"; gem "rubocop"; gem "rubocop-performance"
  gem "memory_profiler"; gem "stackprof"; gem "bundler-audit"; gem "lefthook"
end
```

- Headless: `bundle config set --local without 'ui'`.
- Full: без `without` (или `bundle config unset --local without`).

```
bundle without ui ──► gem ──► Docker headless (entrypoint: mcp)
bundle with ui ─────► gem ──► Docker full     (entrypoint: jira-cld)
```

### 22.2. Ассеты

- `assets/ui/` c `app.css`, `htmx.min.js`, `uplot.min.js`, `fonts/`, `SHA256SUMS`.
- Без Node, npm, bundler-ассетов и CDN.
- `rake assets:verify` проверяет хэши; `rake assets:list` — состав.

### 22.3. Артефакты

| Артефакт | Содержание |
|---|---|
| gem | `bin/jira-cld`, `lib/`, `assets/`, `config/locales` |
| Docker headless | `INSTALL_UI=false`, без `assets/ui`, entrypoint `jira-cld mcp` |
| Docker full | `INSTALL_UI=true`, entrypoint `jira-cld ui` |
| Nix | devShell + `bundlerEnv`, без Node |

Docker: multi-stage, non-root, `--read-only`, tmpfs для `/tmp`, `HEALTHCHECK` только для UI.

### 22.4. CI-матрица

| Job | Проверки |
|---|---|
| headless | установка без `:ui`, тесты, `mcp` smoke, stdout purity |
| full | `:ui` + `:kb`, тесты UI/wizard/destructive, assets verify |
| quality | rubocop, `bundler-audit`, i18n parity, memory/latency budget |
| isolation | два проекта, cross-scope, soft-delete/`.trash`, отсутствие утечек |
| build | gem build, Docker headless/full, размер образа |

### 22.5. Релизный чек-лист

1. `bundle exec rake test` и `rubocop`.
2. `rake assets:verify`.
3. `rake memory:measure` в бюджете; `rake latency:measure` — L2 get p95 ≤ 2 ms, batch upsert p95 ≤ 10 ms.
4. `bin/jira-cld doctor` на чистом конфиге.
5. `gem build` + smoke `jira-cld mcp` (ping/tools/list).
6. Docker headless smoke:
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"ping"}' \
     | docker run -i --rm -e MCP_PROJECT_ID=alpha jira-cld:headless mcp
   ```
7. Smoke destructive: временный проект → `projects remove --yes` → каталог в `.trash`, `stats.db`/`global` целы; UI Delete активного проекта заблокирован.
8. README: headless quickstart и UI quickstart.

### 22.6. Быстрый старт

```bash
# headless
bundle config set --local without 'ui'
bundle install
bin/jira-cld setup --non-interactive ...
bin/jira-cld doctor
bin/jira-cld mcp

# full (с UI)
bundle install
bin/jira-cld ui --open
```

- Headless-сборка не содержит UI-гемов в bundle и не читает `assets/ui`.
- Full-сборка добавляет Roda/Puma/ассеты; entrypoint `bin/jira-cld`.
- Обе сборки используют один `config.yml`, `stats.db` и проектные `cache.db`.

---

## 23. Решённые вопросы

| Вопрос | Решение | Где зафиксировано |
|---|---|---|
| Локаль по умолчанию | `ru`; `LANG`/`LC_*` игнорируются | D23, §11 |
| Тема по умолчанию | `system` | D24, §20.5 |
| Диапазоны графиков | `15m/1h/24h/7d` | D25, §20.7 |
| Очистка кэша и удаление проектов | CLI + UI; удаление soft-delete в `.trash` | D26, §19.2, §20.6, §20.9, §21.4 |
| KB-зеркало | после базовых tools, v1.1 | D27, §9, §17 |
| Wizard | add/edit без удаления; удаление — отдельное действие Projects | §20.6 |
| Количество tools | 19: 16 data/team + 3 catalog | D28, §7, §8.1, §16 |
| JQL/CQL | пресеты + структурные builders + guarded escape hatch; без своего парсера | D39, §8.1.1, §14 |
| Team-tools | evidence из Jira/Confluence, без отправки сообщений | D40, §8.1 |
| Cloud и DC | оба, через адаптеры и capability-матрицу | D29, §8.3 |
| Бюджеты | по замерам: 40–55 MB, ≤ 60 MB; cold start ≤ 400 ms | D30, §3, §16 |
| ActiveRecord | остаётся в runtime; hot path без моделей | D31, §9, §12 |
| Cache hit | read-only, без `accessed_at`; batched writes | D32, D33, §9, §10 |
| SQLite latency | WAL/NORMAL, 8 MB cache, 8 KB page, mmap 64 MB | D34, §9, §11, §16 |
| L1/L2 | 8 MB / 16 MB | D35, §10, §11 |
| Ruby runtime | GC growth 1.1, disable-флаги, без YJIT для MCP | D36, §3, §12 |
| Lazy load | `net/http`/`openssl`/`nokogiri`; без `core_ext` целиком | D37, §12 |
| HTTP keep-alive | persistent connection к Jira/Confluence | D38, §7 |
| Отказ от AR / raw sqlite3 | отклонён: AR остаётся | D31, §3 |

---

## 24. Индекс решений (ADR)

| ADR | Решение |
|---|---|
| ADR-001 | Rails как библиотеки, без Railties |
| ADR-002 | stdio и пин протокола `2025-11-25` |
| ADR-003 | SQLite как L2-кэш; durable-зеркало KB — v1.1 |
| ADR-004 | L1 `MemoryStore` + L2 `DatabaseStore` |
| ADR-005 | i18n фиксируется на старте |
| ADR-006 | Ougai + `oj`, логи в stderr |
| ADR-007 | Без HTTP/nginx в локальной v1 |
| ADR-008 | Read-only токен и allowlist |
| ADR-009 | Ревалидация по версии/ETag |
| ADR-010 | Поиск не кэшируется по умолчанию |
| ADR-011 | Изоляция проектов: каталог + явная привязка |
| ADR-012 | `MCP_PROJECT_ID` обязателен, fail closed |
| ADR-013 | Кросс-scope: `deny`/`declared`/`confirm`, без авто-фоллоу |
| ADR-014 | UI — отдельный локальный процесс |
| ADR-015 | UI: чтение + wizard + destructive с подтверждением |
| ADR-016 | Тёмная тема и переключатель RU/EN |
| ADR-017 | uPlot как вендоренный график |
| ADR-018 | Headless-first: CLI покрывает настройку/статистику |
| ADR-019 | `config.yml` + `SecretStore`, env как override |
| ADR-020 | Две сборки: headless и full (с `:ui`) |
| ADR-021 | Soft-delete проекта в `.trash`; stats сохраняются |
| ADR-022 | KB-зеркало — v1.1, после базовых tools |
| ADR-023 | Jira/Confluence Cloud и DC через адаптеры |
| ADR-024 | 19 tools в v1: 16 data/team + 3 catalog |
| ADR-025 | Бюджеты памяти и старта — по замерам |
| ADR-026 | AR остаётся; hot path через `select_value`/`exec_query`, без моделей |
| ADR-027 | Cache hit read-only; запись и eviction батчами |
| ADR-028 | SQLite latency-pragmas: 8 MB cache, 8 KB page, mmap 64 MB |
| ADR-029 | L1 8 MB / L2 16 MB |
| ADR-030 | Ruby runtime: GC growth 1.1, disable-флаги, без YJIT для MCP |
| ADR-031 | Ленивые network/KB-зависимости и HTTP keep-alive |
| ADR-032 | Latency-критерии: L2 p95 ≤ 2 ms, hit без записи |
| ADR-033 | JQL/CQL: пресеты, структурные builders, guarded escape hatch; без своего парсера |
| ADR-034 | Team-tools: evidence-based экспертиза, профиль + вопросы, без отправки сообщений |
