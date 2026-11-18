# Tools, prompts, resources

Все tools read-only. Имена и аргументы стабильны и на английском; тексты ошибок
локализуются через `MCP_LOCALE=ru|en`. Поиск возвращает `next_cursor` (`null` — конец),
`limit` — `1..50`. Большие ответы обрезаются с `truncated: true`
(`OUTPUT_CHAR_LIMIT`, по умолчанию `24000`).

## Catalog

| Tool | Аргументы | Что делает |
|---|---|---|
| `project_list` | — | Доступные проекты и привязка |
| `project_describe` | `project_id?`, `include_query=false` | Типы, поля, boards, members, пресеты |
| `project_resolve` | `query` | Находит проект по имени; привязку не меняет |

## Jira

| Tool | Аргументы | Что делает |
|---|---|---|
| `jira_my_work` | `scope` (`assigned`, `sprint`, `review`, `blocked`, `recent`), `limit=20`, `project_id?` | Мои задачи + почему сейчас |
| `jira_search_issues` | `jql?` или `preset?`, `limit=25`, `cursor?` | Поиск задач |
| `jira_get_issue` | `key`, `include[]` (`comments`, `changelog`, `links`) | Задача с секциями |
| `jira_brief_issue` | `key`, `intent` (`understand`, `plan`, `verify`), `depth?`, `include[]`, `limits?` | Бриф: AC, решения, зависимости, KB |
| `jira_get_changelog` | `key`, `limit=50`, `cursor?` | История изменений |
| `jira_list_attachments` | `key` | Метаданные вложений, без файлов |
| `jira_unblock_issue` | `key?` или `query?`, `symptom?`, `window=30d`, `limit=5` | Похожие решения, эксперты, гипотезы |
| `jira_list_sprints` | `board_id`, `state?` | Спринты |
| `jira_get_sprint_issues` | `sprint_id`, `limit=50`, `cursor?` | Задачи спринта |

`jira_my_work` принимает только известный scope/preset; иначе `query_preset_unknown`.

## Confluence

| Tool | Аргументы | Что делает |
|---|---|---|
| `kb_search` | `query?` или `cql?`, `preset?`, `limit=10`, `cursor?` | Поиск страниц |
| `kb_get_page` | `id?` или `title?`+`space?` | Страница как plain text |
| `kb_list_children` | `page_id`, `limit=50`, `cursor?` | Дочерние страницы |

Макросы `include`/`excerpt-include` не раскрываются. Вложения не скачиваются.

## Team и meta

| Tool | Аргументы | Что делает |
|---|---|---|
| `team_who_knows` | `topic?`/`issue_key?`/`component?`/`label?`, `window=180`, `limit=5`, `depth?` | Кто разбирается + evidence |
| `team_prepare_question` | `issue_key?`/`topic?`, `person?`, `goal?`, `context?`, `urgency?` | Готовый пакет вопросов, `sent: false` |
| `atlassian_whoami` | — | Пользователь, site, capabilities |
| `atlassian_cache_stats` | — | Статистика кэша |

`team_*` ничего не отправляют.

## JQL/CQL

Пользовательский запрос автоматически оборачивается:

```text
project IN (CLD) AND (<your JQL>) ORDER BY updated DESC
space IN ("CLD") AND (<your CQL>) ORDER BY lastmodified DESC
```

Запрещены `project`, `space`, `ORDER BY`, `;` и управляющие символы внутри строки.
Лимит — `QUERY_MAX_CHARS=2000`. Пресеты задаются в `config.yml`, их список —
`project_describe.query_presets`.

```text
jira_search_issues(jql: 'text ~ "timeout"', limit: 25)
jira_search_issues(preset: 'my_work', limit: 20)
kb_search(query: 'retry timeout', preset: 'runbooks')
```

## Prompts и resources

Prompts: `jira:daily`, `jira:release-notes`, `jira:task-brief`, `jira:unblock`,
`team:handoff`, `kb:answer`.

Resources: `jira://issue/{key}`, `kb://page/{id}`.

## Ошибки

`auth_failed`, `forbidden`, `not_found`, `rate_limited`, `server_error`,
`deployment_capability`, `query_invalid`, `query_scope_forbidden`, `query_too_large`,
`query_timeout`, `query_rate_limited`, `query_preset_unknown`, `scope_forbidden`,
`config_error`, `secret_unresolved`, `invalid_arguments`, `cursor_invalid`.

Ошибка приходит как `isError: true` + `structured_content.error` с `message` и `hint`.
