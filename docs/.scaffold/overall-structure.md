# ruby-jira-mcp — структура документации

## Audiences

**Primary:** Интегратор MCP-клиента
Разработчик, который подключает Jira и Confluence к opencode или другому AI-клиенту.
Хочет быстро получить рабочий доступ, понимать tools, границы проекта и стоимость ошибок.

**Secondary:**
- DevOps — разворачивает сервер, управляет секретами, кэшем и диагностикой.
- Контрибьютор — добавляет tools, адаптеры и меняет внутренние подсистемы.

## Формат

Один файл `docs/GUIDE.md`. Внутри три смысловых блока:

1. Getting Started.
2. Diving Deeper.
3. Reference.

Существующие `docs/usage/*.md` остаются справочниками по эксплуатации и не дублируются.

## Selected use case

**Первый рабочий запрос по задаче.** Интегратор подключает один проект к opencode,
находит свои задачи, открывает задачу с контекстом и ищет связанную страницу в Confluence.
Сценарий покрывает установку, конфиг, MCP-подключение, tools, allowlist, кэш и проверку.

## Getting Started outline

1. **Подготовить окружение и секреты** — Makefile, `.env`, `make install`, Cloud vs DC.
2. **Создать привязку к проекту** — `make setup PROJECT=alpha`, `config.yml`, project keys и spaces.
3. **Подключить сервер к opencode** — `opencode.json`, абсолютный `cwd` на `src/`, `MCP_PROJECT_ID`.
4. **Проверить доступ и границы** — `make doctor`, `atlassian_whoami`, allowlist.
5. **Собрать первый рабочий контекст** — `jira_my_work`, `jira_get_issue`, `kb_search`.
6. **Посмотреть кэш и статистику** — `atlassian_cache_stats`, `make stats`, что кэшируется.

## Diving Deeper topics

| Тема | Зачем нужна | Компоненты |
|---|---|---|
| Изолировать проекты и их кэши | Понять, почему один процесс обслуживает один проект и как избежать смешивания данных. | `Config`, `ProjectRegistry`, `MCP_PROJECT_ID`, `cache.db` |
| Ограничивать JQL и CQL и листать результаты | Написать безопасный запрос, использовать пресеты и корректно продолжать пагинацию. | `Query::JQL`, `Query::CQL`, `Cursor`, `Tools::*` |
| Управлять свежестью данных через кэш | Выбрать TTL, понять stale-if-error, очистку и влияние кэша на ответы. | `Cache::TieredStore`, `Cache::DatabaseStore`, `Cache::Policy` |
| Собирать брифы и командный контекст | Использовать композитные tools и понимать, откуда берутся evidence и warnings. | `Tools::BriefIssue`, `Tools::UnblockIssue`, `Tools::Team*`, repositories |
| Разбирать ошибки и сохранять partial results | Отличить ошибку конфигурации от сетевой и понять, когда ответ остаётся полезным. | domain errors, `Tools::Support`, `Runtime`, `doctor` |
| Эксплуатировать сервер в Docker и Nix | Запустить сервер без Ruby на хосте и сохранить данные и секреты. | Dockerfile, `flake.nix`, `Config`, `Secrets` |
| Расширять сервер новыми tools и адаптерами | Добавить tool или источник данных, не нарушив read-only контракт и кэш. | `Server`, `Runtime`, `Atlassian::*`, `Repositories::*`, tests |

## Reference items

- Tools, prompts и resources: аргументы, возвращаемые поля, ограничения.
- CLI: команды, флаги, коды возврата.
- Переменные окружения и схема `config.yml`.
- Доменные коды ошибок.
- Карта внутренних модулей для контрибьюторов.

## Out of scope

- Повторение `docs/SRD.md`.
- Пошаговая документация UI: она остаётся в `docs/usage/UI.md`.
- Внутренние детали SQLite и HTTP-клиента сверх того, что нужно для правильного использования.
