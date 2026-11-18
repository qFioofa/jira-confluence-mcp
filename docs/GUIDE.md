# ruby-jira-mcp

Этот сценарий подключает один проект Jira и Confluence к opencode. В конце вы получите свои задачи, карточку задачи с комментариями и ссылки на связанные страницы Confluence.

## Getting Started

### Подготовить окружение и секреты

#### Проверить требования

Сервер запускается на Ruby 4.0 и обращается к Atlassian только на чтение. Вам нужен доступ к Jira и Confluence и токен, который не разрешает запись. Для Jira Cloud нужны email и API token. Для Data Center нужен personal access token.

#### Заполнить .env

Файл `.env` хранит адрес сайта, deployment, email и секреты. `make env` создаёт его из `.env.example` с правами `0600`. Заполните блок Cloud или Data Center и оставьте остальные значения по умолчанию.

`make` подхватывает `.env` в свои команды. Прямой запуск `src/bin/jira-cld` файл не читает, поэтому запускайте сервер через `make` или экспортируйте переменные в shell.

```bash
make env
vi .env
```

```dotenv
# Jira Cloud
JIRA_BASE_URL=https://acme.atlassian.net
JIRA_DEPLOYMENT=cloud
JIRA_EMAIL=dev@acme.io
JIRA_API_TOKEN=...
CONFLUENCE_BASE_URL=https://acme.atlassian.net/wiki

# Jira Data Center
JIRA_BASE_URL=https://jira.acme.internal
JIRA_DEPLOYMENT=dc
JIRA_PAT=...
CONFLUENCE_BASE_URL=https://confluence.acme.internal
```

#### Установить зависимости

`make install` устанавливает зависимости из `src/Gemfile`. Повторите команду после изменения `Gemfile` или `Gemfile.lock`.

```bash
make install
```

### Создать привязку к проекту

#### Запустить setup

`make setup` читает `.env` и создаёт `~/.config/jira-cld/config.yml`. `PROJECT=alpha` задаёт id проекта, `JIRA_KEY=CLD` ограничивает Jira, а space берётся из `CLD_SPACE`. При обновлении команда сохраняет резервную копию и не пишет секреты.

Для другого пути передайте `CONFIG=/abs/path/config.yml`. Путь должен быть абсолютным, потому что команда выполняется из `src/`.

```bash
make setup PROJECT=alpha JIRA_KEY=CLD
```

#### Проверить config.yml

`config.yml` связывает проект с Jira keys и spaces. В примере проект `alpha` видит только `CLD` в Jira и Confluence. Поле `token_ref` указывает, откуда взять секрет во время запуска.

```yaml
schema: 1
connections:
  jira:
    base_url: "https://acme.atlassian.net"
    deployment: "cloud"
    email: "dev@acme.io"
    token_ref: "env:JIRA_API_TOKEN"
projects:
  alpha:
    jira_keys: ["CLD"]
    spaces: ["CLD"]
```

Секреты остаются в env через `token_ref`. В YAML нет самого токена.

### Подключить сервер к opencode

#### Описать HTTP-сервер (URL без токена)

Запустите контейнер (`make docker-run-http PROJECT=alpha HTTP_PORT=8765`) и укажите
opencode только URL. Секреты остаются в контейнере.

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

#### Описать локальный stdio-сервер

opencode запускает `jira-cld` как локальный stdio-процесс. `cwd` указывает на `src`, где лежат `Gemfile` и `bin/jira-cld`. `pool: false` создаёт отдельный процесс на сессию и не делит состояние между клиентами.

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

#### Передать проект и секрет

`MCP_PROJECT_ID` связывает процесс с проектом и обязателен. Без него сервер завершается с ошибкой до обработки запросов. Секрет приходит из окружения через `{env:JIRA_API_TOKEN}`. Для Data Center замените переменную на `JIRA_PAT`.

### Проверить доступ и границы

#### Запустить doctor

`make doctor` проверяет конфиг, секреты, доступ к сайту и целостность SQLite. `OFFLINE=1` пропускает сетевые проверки и оставляет локальные. Код `0` означает успех, остальные коды указывают на конфиг, auth, сеть или БД.

```bash
make doctor PROJECT=alpha
make doctor PROJECT=alpha OFFLINE=1
```

#### Проверить личность и allowlist

`atlassian_whoami` возвращает пользователя, deployment, site и capabilities. Вызовите его из opencode после подключения сервера.

```text
atlassian_whoami()
```

Allowlist разрешает только ключи проекта. Запрос к чужому Jira-проекту или space завершится ошибкой.

### Собрать первый рабочий контекст

#### Найти свои задачи

`jira_my_work` берёт preset `my_work` из конфига и возвращает задачи со ссылками и подсказками `why_now`. Scope `assigned` означает ваши незакрытые задачи. Увеличьте `limit`, если список короткий.

```text
jira_my_work(scope: "assigned", limit: 10)
```

#### Открыть задачу

`jira_get_issue` возвращает карточку задачи. Аргумент `include` добавляет comments, changelog или links. Если один источник недоступен, ответ сохраняет задачу и добавляет `warnings`.

```text
jira_get_issue(key: "CLD-142", include: ["comments", "links"])
```

#### Добавить знания из Confluence

`kb_search` ищет страницы Confluence в разрешённых spaces и возвращает заголовок, версию, URL и excerpt. Запрос `query` оборачивается в CQL с allowlist проекта.

```text
kb_search(query: "retry timeout", limit: 5)
```

Поиск продолжается через `next_cursor`. Для полного текста вызовите `kb_get_page` с id или title и space.

### Посмотреть кэш и статистику

#### Проверить кэш

`atlassian_cache_stats` показывает hits, misses, evictions и размер кэша. L1 хранит горячие ответы в памяти процесса. L2 хранит ответы в `cache.db` проекта и переживает перезапуск.

```text
atlassian_cache_stats()
```

#### Посмотреть вызовы

`make stats` показывает вызовы за интервал и помогает найти медленные tools. `make cache-stats` печатает таблицу namespace без запуска MCP. `make cache-clear` очищает только выбранный проект и требует `YES=1`.

```bash
make stats PROJECT=alpha RANGE=1h
make cache-stats PROJECT=alpha
```

`make cache-clear` очищает кэш выбранного проекта. Флаг `SCOPE=expired` удаляет только просроченные записи.

```bash
make cache-clear PROJECT=alpha YES=1 SCOPE=expired
```

## Diving Deeper

### Изолировать проекты и их кэши

#### Intent

Один процесс обслуживает один проект. Такая привязка снижает риск, что агент смешает данные двух команд или покажет кэш чужого проекта. Тема нужна при нескольких проектах, при переключении между ними и при диагностике неожиданных ответов.

#### Design decisions

- **Привязка обязательна.** `MCP_PROJECT_ID` читается при загрузке конфига. `Config#require_project!` проверяет id до создания runtime и завершает процесс с `ConfigError`, если проект не задан или не найден.
- **Неизвестный проект не подменяется.** `ProjectRegistry#find` возвращает `nil` для отсутствующего id. Сервер не выбирает первый проект из `config.yml`, потому что ошибка конфигурации безопаснее случайного доступа.
- **Кэш живёт рядом с проектом.** `Project#cache_db_path` собирает `<DATA_DIR>/<project>/cache.db`. Ответы, TTL и eviction остаются внутри проекта.
- **Справочники и метрики общие.** `global/reference.db` хранит field map и capabilities, `stats.db` хранит метрики. Эти данные описывают сайт и процесс, а не задачи проекта.
- **Разрешение имени не меняет привязку.** `project_resolve` ищет совпадения по id, name, keys, spaces и aliases. Он возвращает кандидатов и `needs_confirmation`, но процесс остаётся привязанным к `MCP_PROJECT_ID`.
- **Путь можно перенести.** `DATA_DIR` задаёт корень данных. Если сохранить структуру каталогов, проект переезжает вместе с кэшем.

#### API walkthrough

**Привязать процесс к проекту**

- `MCP_PROJECT_ID` задаёт проект для процесса. Значение попадает в `Config#project_id`. Без переменной CLI `mcp` завершается до запуска сервера.
- `Config#require_project!` проверяет id и поднимает `ConfigError` для пустого или неизвестного проекта.
- `ProjectRegistry#find` возвращает `Project` с keys, spaces и путями. `nil` означает, что id отсутствует в `config.yml`.

**Осмотреться в каталоге**

- `project_list` показывает проекты и текущую привязку. Вызов не переключает процесс.
- `project_describe` добавляет пресеты, capabilities и метаданные. С `include_query: true` возвращает сырые запросы.
- `project_resolve` ищет проект по строке. `needs_confirmation` остаётся true, если кандидатов несколько.

**Разделить данные**

- `Project#cache_db_path` строит путь к `cache.db`. `DB.setup!` открывает файл и применяет PRAGMA.
- `Config#reference_db_path` возвращает `global/reference.db`. Файл общий, потому что справочники не зависят от проекта.
- `Config#stats_path` возвращает `stats.db`. История метрик переживает удаление проекта.

### Ограничивать запросы и листать результаты

#### Intent

Агент может сформулировать широкий JQL или CQL. Сервер добавляет ограничение проекта и проверяет строку до отправки в Atlassian. Тема нужна, когда пресетов не хватает или результат не помещается на одну страницу.

#### Design decisions

- **Allowlist задаёт границу.** `Query::JQL.wrap` строит `project IN (...)` из `jira_keys`. Пустой allowlist даёт `query_scope_forbidden`.
- **CQL повторяет правило.** `Query::CQL.wrap` строит `space IN (...)` и экранирует кавычки в именах пространств.
- **Опасные конструкции отклоняются.** `project`, `space`, `ORDER BY`, `;` и control characters не доходят до сети. Это не даёт переопределить allowlist или добавить второй запрос.
- **Пресет хранит проверенный запрос.** В `config.yml` лежат `query`, `order_by` и `default_limit`. `jira_my_work` сопоставляет scope с id пресета, а неизвестный scope даёт `query_invalid`.
- **Курсор непрозрачен.** `Cursor.encode` кодирует JSON в base64url. `Cursor.decode` проверяет версию `v:1` и отбрасывает повреждённые данные.
- **Лимит ограничивает вход.** `QUERY_MAX_CHARS` проверяется до оборачивания. Слишком длинная строка даёт `query_too_large`.
- **Курсор обходит кэш.** Страница с курсором не сохраняется, потому что курсор уже задаёт позицию и следующий вызов должен продолжить выдачу.

#### API walkthrough

**Строить безопасный запрос**

- `jira_search_issues` принимает `jql` или `preset`, но не оба. Repository выбирает пресет, оборачивает запрос и передаёт лимит.
- `kb_search` принимает `query` или `cql`. `preset` добавляет фильтр из `config.yml`, а `query` превращается в `text ~` и проходит allowlist.
- `Query::JQL.wrap` нормализует ключи, проверяет строку и добавляет `ORDER BY`.
- `Query::CQL.wrap` делает то же для Confluence и экранирует имена spaces.

**Использовать пресеты**

- `project_describe` возвращает `id`, `kind`, `label` и `default_limit`. Сырые запросы скрыты без `include_query`.
- `preset` задаёт имя пресета из `config.yml`. Repository загружает query и order_by.
- `jira_my_work` мапит scope на пресеты и добавляет `why_now` к задачам.

**Продолжать выдачу**

- `next_cursor` указывает на следующую страницу. `null` означает конец выдачи.
- `cursor` передаётся в следующий вызов. Repository запрашивает следующий участок без кэша.
- `Cursor.encode` кодирует версию и поля пагинации в base64url.
- `Cursor.decode` восстанавливает поля или возвращает `nil` для неизвестной версии.

### Управлять свежестью данных через кэш

#### Intent

Atlassian отвечает медленнее локального SQLite. Кэш снижает число запросов и помогает пережить короткий сбой. Тема нужна при настройке TTL, диагностике устаревших данных и очистке.

#### Design decisions

- **L1 ускоряет горячие чтения.** `TieredStore` создаёт `MemoryStore` размером `CACHE_L1_BYTES`. L1 живёт в процессе и исчезает при перезапуске.
- **L2 переживает перезапуск.** `DatabaseStore` пишет в `cache.db` проекта. Запись и чтение идут через один SQLite-файл.
- **TTL зависит от данных.** `Policy::DEFAULTS` задаёт срок для identity, issue, search, page и других namespace. Search живёт 45 секунд, identity 3600, page 600.
- **Stale-if-error сохраняет ответ.** Для `reference`, `page_meta`, `page` и `children` разрешён stale. Если обновление падает, `fetch_with_meta` возвращает старую запись с `stale: true`.
- **Eviction освобождает место.** `DatabaseStore` удаляет expired записи, затем самые старые по `fetched_at`. Лимит задаёт `CACHE_MAX_BYTES`.
- **Хит не меняет запись.** Успешное чтение не обновляет `accessed_at`, поэтому популярные записи не вытесняют остальные.
- **Курсорные страницы не кэшируются.** Повторный вызов с курсором должен продолжить выдачу, а не вернуть сохранённую страницу.

#### API walkthrough

**Читать через два уровня**

- `Cache::TieredStore#fetch` сначала читает L1, затем L2. При промахе вызывает блок и записывает результат.
- `Cache::Policy#ttl` возвращает TTL для namespace или явный override.
- `Cache::Key` собирает ключ из проекта, сайта, principal, namespace и логического запроса.

**Смотреть и очищать**

- `atlassian_cache_stats` показывает hits, misses, stale и размер файла. Счётчики живут в runtime.
- `make cache-stats` печатает namespace, entries, bytes и oldest.
- `make cache-clear` удаляет expired или все записи проекта. Требует `YES=1`.

**Настраивать размеры**

- `CACHE_L1_BYTES` задаёт размер памяти для L1.
- `CACHE_MAX_BYTES` задаёт верхнюю границу SQLite-кэша.
- `CACHE_STALE_GRACE` задаёт окно stale-if-error после истечения TTL.

### Собирать брифы и командный контекст

#### Intent

Одна задача редко даёт полный контекст. Брифы, поиск экспертов и вопросы собирают evidence из Jira и Confluence. Тема нужна, когда агенту мало карточки задачи.

#### Design decisions

- **Partial result важнее пустого ответа.** Композитные tools возвращают то, что удалось получить. Недоступный источник попадает в `warnings`.
- **Бриф зависит от intent.** `understand`, `plan` и `verify` меняют акценты и следующий шаг. `deep` увеличивает лимиты комментариев и истории.
- **Team tools ничего не отправляют.** `team_prepare_question` возвращает пакет с `sent: false`. Отправка остаётся решением человека.
- **Email скрыт по умолчанию.** `TEAM_SHOW_EMAIL=0` убирает адреса из ответов. Это снижает утечку контактов в логи и контекст модели.
- **Who-knows опирается на evidence.** `team_who_knows` собирает авторов задач, комментариев и страниц Confluence. Боты исключены, а уверенность зависит от числа свидетельств.
- **KB закрывает пробелы.** `jira_brief_issue` ищет связанные страницы по теме задачи. `kb_get_page` даёт полный текст, если excerpt не хватает.

#### API walkthrough

**Собрать бриф**

- `jira_brief_issue` возвращает AC, решения, открытые вопросы, зависимости и следующий шаг. `include` выбирает comments, changelog, links, similar и kb.
- `jira_unblock_issue` ищет похожие решённые задачи, экспертов и недавние изменения. Возвращает гипотезы и вопросы.

**Найти людей**

- `team_who_knows` возвращает людей с evidence, confidence и gaps. `depth: deep` добавляет комментарии.
- `team_prepare_question` собирает вопросы с reason и links. Поле `sent` всегда false.

**Дочитать KB**

- `kb_get_page` возвращает текст страницы по id или title и space. Версия проверяется перед чтением.
- `kb_list_children` перечисляет дочерние страницы для обхода дерева.

### Разбирать ошибки и сохранять partial results

#### Intent

Агент должен понимать, что сломалось и что всё ещё можно использовать. Тема нужна при auth, сети, лимитах и неполных ответах.

#### Design decisions

- **Ошибка остаётся данными.** `Tools::Support.run` ловит известные исключения и передаёт их в `Support.error`. Ответ получает `isError` и `structured_content`, поэтому клиент читает код без разбора текста.
- **Причина запроса не теряется.** `Atlassian::QueryError` хранит `query_code`. `Tools::Support.error_payload` переносит его в `error.code`, поэтому `query_scope_forbidden` и `query_invalid` различимы.
- **Atlassian передаёт контекст.** `Atlassian::Error#to_h` возвращает code, message, status, domain и hint. `Errors.from_response` превращает 401, 403, 404, 429 и 5xx в доменные ошибки с подсказкой.
- **Partial result сохраняет пользу.** Композитный tool перехватывает сбой одного источника и добавляет `warnings`. Задача или страница остаются в ответе, даже если comments или KB недоступны.
- **doctor говорит кодом.** `CLI::Support::EXIT` сопоставляет конфиг, auth, not found, БД, сеть, лимиты, секрет и capability с кодами от `0` до `9`. Скрипт может проверить причину без разбора текста.
- **stdout остаётся протоколом.** Сервер пишет Ougai JSON в stderr. Любая строка лога в stdout сломала бы JSON-RPC, поэтому эти потоки разделены.
- **Обрезка сохраняет JSON.** `Support.trim` сокращает массивы и строки до `OUTPUT_CHAR_LIMIT` и ставит `truncated: true`. Ответ остаётся валидным, но теряет менее важные детали.

#### API walkthrough

**Читать ошибку tool**

- `Tools::Support.error` строит MCP-ответ с `isError` и `structured_content`.
- `Tools::Support.error_payload` выбирает code, message и hint для класса ошибки.
- `MCP::Tool::Response` несёт текст и structured content для клиента.

**Различать источники**

- `Atlassian::Error#to_h` возвращает код, статус, домен и подсказку.
- `Atlassian::QueryError#query_code` хранит причину отказа JQL или CQL.
- `ConfigError` превращается в `config_error`.
- `SecretError` превращается в `secret_unresolved`.

**Проверять окружение**

- `make doctor` проверяет конфиг, секреты, сеть и БД.
- `CLI::Support::EXIT` сопоставляет ошибки с кодами выхода.
- `export diagnostics` собирает redacted-бандл для разбора.

### Эксплуатировать сервер в Docker и Nix

#### Intent

Сервер должен запускаться без локального Ruby и сохранять данные между контейнерами. Тема нужна DevOps и при воспроизводимой установке.

#### Design decisions

- **Dockerfile собирает два образа.** Один build stage ставит компиляторы и библиотеки. Runtime stage оставляет только SQLite и YAML, поэтому образ не тащит toolchain.
- **Headless не содержит UI.** `INSTALL_UI=false` исключает группу `ui` из bundle и удаляет `assets/ui`. Full-образ собирается с `INSTALL_UI=true`.
- **Контейнер работает не от root.** Runtime создаёт пользователя `jira` с uid `10001` и владельцем каталогов конфига и данных. Смонтированные каталоги должны быть доступны этому uid.
- **Пути фиксированы.** `CONFIG_PATH` указывает на `/home/jira/.config/jira-cld/config.yml`, `DATA_DIR` на `/home/jira/.local/share/jira-cld`. Конфиг монтируется только для чтения, данные идут в volume.
- **Read-only root допустим.** С `--read-only` нужен writable volume для данных и `--tmpfs /tmp`. SQLite пишет в `DATA_DIR`, а не в слой контейнера.
- **Nix фиксирует окружение.** `flake.nix` даёт Ruby 4.0, Bundler, SQLite и системные библиотеки. `BUNDLE_GEMFILE` указывает на `src/Gemfile`, поэтому команды работают из корня.
- **Nix package запускает bundle.** `nix run` использует `bundle exec ruby src/bin/jira-cld` с `BUNDLE_GEMFILE` и `BUNDLE_PATH`. Перед первым запуском нужен `make install`.

#### API walkthrough

**Собрать образ**

- `make docker-headless` собирает образ с `INSTALL_UI=false`.
- `make docker-full` собирает образ с UI.
- `docker build` принимает `-f docker/Dockerfile` и контекст из корня.

**Запустить контейнер**

- `docker run` монтирует конфиг и каталог данных.
- `CONFIG_PATH` указывает конфиг внутри контейнера.
- `DATA_DIR` указывает writable-каталог данных.
- `MCP_PROJECT_ID` выбирает проект для процесса.

**Воспроизвести окружение**

- `nix develop` даёт Ruby, Bundler и SQLite.
- `nix run` запускает `jira-cld` из flake.
- `flake.nix` фиксирует зависимости devShell.

### Расширять сервер новыми tools и адаптерами

#### Intent

Контрибьютор должен добавить tool или источник, не нарушив read-only контракт и кэш. Тема нужна при изменении API и адаптеров.

#### Design decisions

- **Tool объявляет контракт.** Класс наследует `MCP::Tool` и задаёт `tool_name`, `title`, `description`, `input_schema` и `output_schema`. `Server` включает валидацию аргументов, поэтому схема проверяется до вызова.
- **Support.run держит границу.** Tool вызывает `Support.run` и получает единый маппинг ошибок, structured response и запись метрик. Без обёртки ошибки утекают в MCP и теряют доменный код.
- **Annotations фиксируют поведение.** Read-only tools ставят `read_only_hint: true`, `destructive_hint: false` и `idempotent_hint: true`. `open_world_hint` зависит от источника и остаётся честным.
- **Runtime собирает зависимости.** `Runtime` создаёт config, clients, adapters, repositories и cache. Tool берёт готовый runtime из `JiraCld.runtime`, поэтому не создаёт HTTP-клиент на каждый вызов.
- **Адаптер прячет Atlassian.** `Atlassian::Jira` и `Atlassian::Confluence` отвечают за endpoint, cursor, auth и ошибки. Новый источник должен повторять этот слой, а не вызывать HTTP из repository.
- **Кэш выбирает repository.** Repository решает, что кэшировать, и передаёт namespace, logical key и TTL. `Cache::Key` добавляет проект, сайт, principal и хэш запроса.
- **Тест фиксирует поведение.** Contract-тест проверяет HTTP-форму, tool-тест проверяет response, integration-тест проверяет stdout и lifecycle. Новый tool без теста ломает контракт незаметно.

#### API walkthrough

**Добавить tool**

- `MCP::Tool` задаёт базовый класс и регистрацию имени.
- `input_schema` описывает аргументы, типы и ограничения.
- `annotations` объявляет `readOnlyHint` и `destructiveHint`.
- `Tools::Support.run` оборачивает вызов ошибками и метриками.

**Подключить источник**

- `Runtime#issues` собирает репозиторий задач.
- `Atlassian::Jira` инкапсулирует Jira API и auth.
- `Atlassian::Confluence` инкапсулирует Confluence API и версии страниц.
- `Atlassian::Errors.from_response` мапит HTTP-статус в доменную ошибку.

**Проверить поведение**

- `Server::TOOLS` регистрирует tool в MCP.
- `tools/list` проверяет имя, схему и annotations.
- `make test` прогоняет контракты, tools и stdio.

## Reference

### Tools

Публичный API MCP. Все tools read-only, `limit` ограничен `1..50`, `next_cursor` непрозрачен.

| Tool | Аргументы | Возврат |
|---|---|---|
| `project_list` | — | `projects[]`, `bound_project` |
| `project_describe` | `project_id?`, `include_query=false` | типы, поля, presets, capabilities |
| `project_resolve` | `query` | `candidates[]`, `needs_confirmation` |
| `jira_my_work` | `scope=assigned`, `limit=20`, `project_id?` | задачи, `why_now`, `next_action` |
| `jira_search_issues` | `jql?` или `preset?`, `limit=25`, `cursor?` | `issues[]`, `next_cursor`, `total?` |
| `jira_get_issue` | `key`, `include=[]` (`comments`, `changelog`, `links`) | задача и выбранные секции |
| `jira_brief_issue` | `key`, `intent=understand`, `depth=standard`, `include[]`, `limits{}` | AC, решения, зависимости, KB, `next_actions` |
| `jira_get_changelog` | `key`, `limit=50`, `cursor?` | `entries[]`, `next_cursor` |
| `jira_list_attachments` | `key` | имя, размер, mime, URL |
| `jira_unblock_issue` | `key?` или `query?`, `symptom?`, `window=30d`, `limit=5` | похожие задачи, эксперты, гипотезы |
| `jira_list_sprints` | `board_id`, `state?` (`active`, `future`, `closed`) | `sprints[]` |
| `jira_get_sprint_issues` | `sprint_id`, `limit=50`, `cursor?` | задачи, `next_cursor` |
| `kb_search` | `query?` или `cql?`, `preset?`, `limit=10`, `cursor?` | `pages[]`, `next_cursor`, `cql` |
| `kb_get_page` | `id?` или `title?` + `space?` | страница, текст, версия |
| `kb_list_children` | `page_id`, `limit=50`, `cursor?` | `children[]`, `next_cursor` |
| `team_who_knows` | `topic?`/`issue_key?`/`component?`/`label?`, `window=180`, `limit=5`, `depth=standard` | люди, evidence, confidence, gaps |
| `team_prepare_question` | `issue_key?`/`topic?`, `person?`, `goal?`, `context?`, `urgency=normal` | вопросы, links, `sent: false` |
| `atlassian_whoami` | — | user, deployment, site, capabilities |
| `atlassian_cache_stats` | — | hits, misses, stale, bytes |

`scope` у `jira_my_work` принимает `assigned`, `sprint`, `review`, `blocked`, `recent`.
`include` у `jira_brief_issue` принимает `comments`, `changelog`, `links`, `similar`, `kb`.

### Prompts and resources

| Prompt | Аргументы | Назначение |
|---|---|---|
| `jira:daily` | `scope?`, `limit?` | стендап |
| `jira:release-notes` | `preset?`, `version?` | релиз-ноты |
| `jira:task-brief` | `key`, `intent?` | бриф задачи |
| `jira:unblock` | `key?`, `query?`, `symptom?` | поиск выхода из блокера |
| `team:handoff` | `issue_key`, `person?` | передача задачи |
| `kb:answer` | `question` | ответ по KB |

| Resource URI | Содержимое |
|---|---|
| `jira://issue/{key}` | задача и связанные секции |
| `kb://page/{id}` | страница Confluence |

### CLI

Запуск из корня через `make` или из `src` через `bundle exec ruby bin/jira-cld`.

| Команда | Назначение |
|---|---|
| `jira-cld mcp` | stdio MCP, требует `MCP_PROJECT_ID` |
| `jira-cld mcp-http` | Streamable HTTP MCP, флаги `--host`, `--port`, `--path`, `--stateless` |
| `jira-cld ui` | локальный UI на `127.0.0.1` |
| `jira-cld setup` | создаёт `config.yml`, флаги `--non-interactive`, `--dry-run`, `--force`, `--config` |
| `jira-cld doctor` | проверка, флаги `--project`, `--config`, `--offline`, `--json` |
| `jira-cld projects list` | список проектов |
| `jira-cld projects add` | `--project`, `--name`, `--jira-key`, `--space`, `--style` |
| `jira-cld projects edit` | те же флаги, что у add |
| `jira-cld projects remove` | `--project`, `--yes`, `--purge` |
| `jira-cld stats` | `--project`, `--range 15m\|1h\|24h\|7d`, `--json`, `--csv` |
| `jira-cld cache stats` | `--project`, `--json` |
| `jira-cld cache clear` | `--project`, `--scope expired\|all`, `--namespace`, `--yes` |
| `jira-cld db migrate` | применяет миграции |
| `jira-cld db check` | `PRAGMA integrity_check` |
| `jira-cld db vacuum` | сжимает файл |
| `jira-cld db checkpoint` | `wal_checkpoint(TRUNCATE)` |
| `jira-cld config show` | redacted-конфиг |
| `jira-cld config validate` | проверка схемы без сети |
| `jira-cld config path` | путь к конфигу |
| `jira-cld config print-opencode` | готовый JSON для opencode |
| `jira-cld export diagnostics` | redacted-бандл, `--output` |
| `jira-cld console` | IRB с runtime |
| `jira-cld version` | версия |

Коды возврата: `0` ok, `2` config, `3` auth, `4` not found, `5` db, `6` network,
`7` rate limited, `8` secret, `9` capability.

### Configuration

`config.yml` читается из `CONFIG_PATH` или `~/.config/jira-cld/config.yml`.

```yaml
schema: 1
connections:
  jira:
    base_url: "https://acme.atlassian.net"
    deployment: "cloud" # cloud | dc
    email: "dev@acme.io"
    token_ref: "env:JIRA_API_TOKEN"
    pat_ref: "env:JIRA_PAT" # для Data Center
  confluence:
    base_url: "https://acme.atlassian.net/wiki"
    token_ref: "env:JIRA_API_TOKEN"
    pat_ref: "env:CONFLUENCE_PAT"
projects:
  alpha:
    name: "Alpha"
    jira_keys: ["CLD"]
    spaces: ["CLD"]
    style: "scrum"
    aliases: []
    related_scopes: []
    queries:
      jql:
        my_work:
          label: "Моя работа"
          query: "assignee = currentUser() AND statusCategory != Done"
          order_by: "updated DESC"
          default_limit: 20
      cql:
        runbooks:
          label: "Runbooks"
          query: "label = runbook AND type = page"
          order_by: "lastmodified DESC"
          default_limit: 10
    team:
      show_email: false
      channels: []
cross_scope:
  mode: "confirm" # deny | declared | confirm
  grant_ttl: 3600
  cache: false
ui:
  locale: "ru"
  theme: "system" # system | light | dark
```

`token_ref` и `pat_ref` принимают `env:NAME`, `file:PATH`, `command:CMD`, `keyring:NAME`.
`SECRET_PROVIDER` задаёт провайдер по умолчанию.

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `MCP_PROJECT_ID` | — | проект процесса, обязателен для `mcp` |
| `JIRA_BASE_URL` | — | адрес Jira |
| `JIRA_DEPLOYMENT` | `cloud` | `cloud` или `dc` |
| `JIRA_EMAIL` | — | email для Cloud |
| `JIRA_API_TOKEN` | — | API token Cloud |
| `JIRA_PAT` | — | PAT Data Center |
| `CONFLUENCE_BASE_URL` | `<jira>/wiki` | адрес Confluence |
| `CONFLUENCE_API_TOKEN` | `JIRA_API_TOKEN` | отдельный токен Cloud |
| `CONFLUENCE_EMAIL` | `JIRA_EMAIL` | email Confluence |
| `CONFLUENCE_PAT` | `JIRA_PAT` | PAT Confluence |
| `CLD_SPACE` | `CLD` | space по умолчанию |
| `KB_ENABLED` | `1` | включает Confluence tools |
| `CONFIG_PATH` | `~/.config/jira-cld/config.yml` | путь к конфигу |
| `DATA_DIR` | `~/.local/share/jira-cld` | корень данных |
| `DB_PATH` | `<DATA_DIR>/<project>/cache.db` | override кэша |
| `REFERENCE_DB_PATH` | `<DATA_DIR>/global/reference.db` | справочник |
| `STATS_PATH` | `<DATA_DIR>/stats.db` | метрики |
| `DB_AUTO_MIGRATE` | `1` | миграции при старте |
| `CACHE_ENABLED` | `1` | включает кэш |
| `CACHE_L1_BYTES` | `8388608` | размер L1 |
| `CACHE_MAX_BYTES` | `16777216` | размер L2 |
| `CACHE_MAX_ENTRY_BYTES` | `262144` | лимит записи |
| `CACHE_SEARCH` | `0` | кэшировать поиск |
| `CACHE_STALE_GRACE` | `600` | окно stale |
| `CACHE_WRITE_BATCH` | `64` | размер batch |
| `DB_CACHE_SIZE_KB` | `8192` | SQLite cache |
| `DB_MMAP_BYTES` | `67108864` | SQLite mmap |
| `DB_PAGE_SIZE` | `8192` | размер страницы |
| `DB_JOURNAL_SIZE_LIMIT` | `16777216` | лимит журнала |
| `HTTP_KEEP_ALIVE` | `1` | keep-alive |
| `HTTP_KEEP_ALIVE_TIMEOUT` | `30` | таймаут keep-alive |
| `HTTP_TIMEOUT_MS` | `20000` | таймаут запроса |
| `QUERY_MAX_CHARS` | `2000` | лимит JQL/CQL |
| `TEAM_SHOW_EMAIL` | `0` | показывать email |
| `TEAM_WINDOW_DAYS` | `180` | окно экспертизы |
| `MCP_LOCALE` | `ru` | язык tools |
| `OUTPUT_LANG` | `MCP_LOCALE` | язык ответов |
| `OUTPUT_CHAR_LIMIT` | `24000` | лимит ответа |
| `SECRET_PROVIDER` | `env` | провайдер секретов |
| `STATS_ENABLED` | `1` | включает метрики |
| `STATS_RETENTION_DAYS` | `7` | хранение метрик |
| `UI_PORT` | `0` | порт UI, `0` означает эфемерный |
| `UI_OPEN` | `1` | открывать браузер |
| `UI_LOCALE` | `MCP_LOCALE` | язык UI |
| `UI_THEME` | `system` | тема UI |
| `LOG_LEVEL` | `info` | уровень логов |
| `LOG_FORMAT` | `json` | формат логов |
| `RUBY_GC_HEAP_GROWTH_FACTOR` | `1.1` | настройка GC |
| `RUBYOPT` | `--disable=...` | отключение диагностики Ruby |
| `MALLOC_ARENA_MAX` | `2` | лимит арен malloc |

Полный список с комментариями: `.env.example`.

### Error codes

| Код | Значение |
|---|---|
| `auth_failed` | 401, токен не принят |
| `forbidden` | 403, нет доступа |
| `not_found` | 404 или 410 |
| `rate_limited` | 429 |
| `server_error` | 5xx Atlassian |
| `deployment_capability` | endpoint недоступен на deployment |
| `query_invalid` | неверный JQL/CQL или аргументы |
| `query_scope_forbidden` | запрос вышел за allowlist |
| `query_too_large` | превышен `QUERY_MAX_CHARS` |
| `query_timeout` | истёк таймаут запроса |
| `query_rate_limited` | лимит поиска |
| `query_preset_unknown` | неизвестный preset |
| `scope_forbidden` | issue или page вне allowlist |
| `config_error` | ошибка конфигурации |
| `secret_unresolved` | секрет не разрешён |
| `invalid_arguments` | неверные аргументы tool |
| `cursor_invalid` | повреждённый курсор |
| `internal_error` | непойманное исключение |
| `request_failed` | общий HTTP-сбой |

Ответ об ошибке содержит `error.code`, `error.message` и иногда `error.hint`.

### Internal modules

| Модуль | Роль | Ключевые точки |
|---|---|---|
| `JiraCld::Server` | собирает MCP, stdio и HTTP | `TOOLS`, `PROMPTS`, `RESOURCE_TEMPLATES`, `run`, `run_http`, `http_app` |
| `JiraCld::Runtime` | связывает конфиг, клиентов и repositories | `build`, `issues`, `knowledge_base`, `people`, `cache` |
| `JiraCld::Config` | читает env и `config.yml` | `load`, `require_project!`, `db_path`, `spaces` |
| `JiraCld::ConfigStore` | валидирует и пишет YAML | `load`, `save`, `validate!`, `SCHEMA` |
| `JiraCld::ProjectRegistry` | хранит проекты и пути | `list`, `find`, `resolve`, `add`, `remove` |
| `JiraCld::DB` | открывает три SQLite-базы | `setup!`, `migrate!`, `checkpoint`, `stats` |
| `JiraCld::Cache::TieredStore` | L1 и L2 | `fetch`, `write`, `clear`, `stats` |
| `JiraCld::Cache::DatabaseStore` | SQLite-кэш | `read_record`, `write_record`, `evict_if_needed!` |
| `JiraCld::Cache::Policy` | TTL и stale | `ttl`, `stale?`, `enabled_for?` |
| `JiraCld::Query::JQL` | JQL wrapper | `wrap`, `validate!`, `preset` |
| `JiraCld::Query::CQL` | CQL wrapper | `wrap`, `validate!`, `preset` |
| `JiraCld::Atlassian::Jira` | Jira API | `search`, `issue`, `comments`, `changelog` |
| `JiraCld::Atlassian::Agile` | boards и sprints | `boards`, `sprints`, `sprint_issues` |
| `JiraCld::Atlassian::Confluence` | Confluence API | `search`, `page`, `children`, `space` |
| `JiraCld::Atlassian::Cursor` | пагинация | `encode`, `decode` |
| `JiraCld::Atlassian::Errors` | HTTP → domain | `from_response`, `raise_for!` |
| `JiraCld::Repositories::Issues` | Jira use cases | `search_issues`, `my_work`, `brief`, `unblock` |
| `JiraCld::Repositories::KnowledgeBase` | Confluence use cases | `search`, `get_page`, `list_children` |
| `JiraCld::Repositories::People` | экспертиза | `who_knows`, `prepare_question` |
| `JiraCld::CLI::App` | CLI dispatcher | `COMMANDS`, `run` |
| `JiraCld::UI::App` | локальный UI | `run`, `Router` |

Референс внутренних модулей нужен контрибьюторам. Интегратору достаточно tools,
CLI и конфигурации.
