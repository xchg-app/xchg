---
tags: [memory/repo, architecture]
---
# Устройство `bin/xchg`

Один файл, секции сверху вниз:

1. **Утилиты** — `die/udie/warn`, `meta` (поле frontmatter), `title`, `body_of`, `plural`, `rel_time`.
2. **Конфиг** — `parse_conf` (awk печатает `G/H/S/E` строки с TAB, bash раскладывает через `hub_new/hub_set` в параллельные массивы `HUBS/HUB_PATHS/HUB_REMOTES/HUB_LOGINS`; читать — `hub_path/hub_remote/hub_login`, искать — `hub_idx`), `load_conf`, правки `conf_set_global/conf_set_hub/conf_rm_hub/conf_add_hub` (awk → tmp → mv), `ensure_conf`, `check_contract`.
3. **Синхронизация** — `hub_sync` (pull одного хаба и дотолкнуть то, что не ушло после неудачного push; стампы в `.git/xchg-last-sync`, `.git/xchg-unavail`), `sync_hubs` (параллельно, дедлайн 20 с), `self_update`, `hub_push` (commit + pull --rebase + push ×3).
4. **Люди и проекты** — `resolve_user` (только contacts.md: сначала точный логин, потом имя/алиасы; python3 casefold или awk), `user_gone` (каталог people/ без строки — только для текста ошибки «is no longer in hub»), `has_project`, `user_projects` (участие выводится из каталогов агентов), `register_me` и `agent_passport` (авторегистрация при `hub add/init` и `projects add`).
5. **Адреса** — `parse_addr` → `A_HUB/A_REL/A_LABEL` (части в любом порядке, хаб выводится из содержимого), `addr_label` (обратно в короткую метку), `locate` (файл по `хаб:путь`, абсолютному пути или единственному совпадению).
6. **Агент** — `repo_root`, `cur_project`, `project_norm` (имя репозитория → допустимое имя проекта) (basename главного репозитория или `git config xchg.project`), `sender_id` (`user/project`), `my_addrs` (адреса сессии), `other_addrs` (мои адреса в других проектах), `cmd_agent`.
7. **Сообщения** — `msg_files` (без карточек и подкаталогов), `kind_of`, `cursor_file`/`is_read`/`mark_read` (курсор на пару агент+адрес, лежит в `.git/xchg-read/`), `list_addr` (заглушённое пропускает), `write_msg`, `warn_secrets`.
8. **Команды** — `cmd_inbox` (+`inbox_lines`, `record_shown`, `others_note`, `unsent_warn`), `cmd_wait` (+`shown_file`/`is_shown`/`mark_shown`/`unshown_lines`), `cmd_mute` (+`muted_file`/`is_muted`/`set_muted`), `read_hook_input` (событие хука из JSON на stdin), `cmd_read`, `cmd_seen`, `cmd_sent`, `cmd_thread` (+`hist_find`/`msg_field`/`msg_title` — чтение закрытых задач из истории), `send_common`/`cmd_send`/`cmd_post`, `cmd_reply`, `cmd_claim` (+`claim_owner`), `cmd_done`, `cmd_forward`, `cmd_who`, `cmd_contact`, `cmd_projects`/`cmd_project_add`, `cmd_hubs`/`cmd_hub`/`init_hub_repo`, `cmd_log`, `cmd_sync`, `cmd_install`, `cmd_status`, `cmd_help`.
9. **Диспетчер** — функция `main`: `help`/`version` обрабатываются до чтения конфига; файл заканчивается строкой `main "$@"; exit $?`.

## Потоки

- **Хук** `xchg inbox --brief [--max-age 300]`: `sync_hubs` → для каждого хаба `my_addrs` → `list_addr` → счётчик других проектов и неотправленного. Нечего показать → 0 байт.
- **send/post**: `sync_hubs` всех (нужны свежие contacts и projects) → `parse_addr` → `check_contract` → `write_msg` → `hub_push` → своё сообщение сразу помечается прочитанным.
- **claim**: sync → проверка, что задача ещё на месте и это задача → `git mv` в `projects/<p>/<me>/` → push; при проигрыше гонки локальный коммит откатывается (`reset --hard @{u}`, только если он единственный) и печатается, кто успел.
- **done**: `git mv` в `<адрес>/done/`.

## Пакеты харнессов

Корень репозитория не принадлежит ни одному харнессу: всё, что специфично, лежит в
`harness/<имя>/`, а пользователь ставит пакет из отдельного репозитория, который собирается отсюда.
Так сделано потому, что Gemini и Codex теряют симлинки при установке, а Gemini ставится только из
корня репозитория (см. gotchas) — при общем репозитории корень доставался бы одному из харнессов.

| харнесс | исходник пакета | репозиторий пакета | манифест | хуки | как попадает клиент |
|---|---|---|---|---|---|
| Claude Code | `harness/claude-code/` | `claude-code-plugin` | `.claude-plugin/plugin.json`; маркетплейс `.claude-plugin/marketplace.json` → `./` | `hooks/hooks.json` (подхватывается сам), `${CLAUDE_PLUGIN_ROOT}` | `bin/` в PATH |
| Codex CLI | `harness/codex/` | `codex-plugin` | `.codex-plugin/plugin.json`; маркетплейс `.agents/plugins/marketplace.json` → `./` | `hooks/hooks.json` (стандартный путь), `${PLUGIN_ROOT}` | в PATH не попадает — путь говорит скилл |
| Gemini CLI | `harness/gemini/` | `gemini-plugin` | `gemini-extension.json` | `hooks/hooks.json` (событие `BeforeAgent`, таймаут в мс), `${extensionPath}` | в PATH не попадает |

Харнессы без пакета настраивает `cmd_install` по `harness_info`: `H_STYLE` — как писать хуки
(`json` — файл настроек, правит jq; `yaml` — печатаем строки, YAML не трогаем; `scripts` — по
исполняемому файлу на событие), `H_FORMAT` — в каком поле харнесс ждёт ответ (`hook_print`:
`hookSpecificOutput.additionalContext`, `context` у Hermes, `contextModification` у Cline).
Форму задаёт флаг `--hook-format`, «всё открытое» — событие `SessionStart`/`TaskStart`, флаг
`--session` или `is_first_turn` в JSON на stdin (Hermes: ответ хука старта сессии игнорируется).

Вложения — `att_put`/`att_get`: файл в хаб как коммит без родителей с одним файлом под
`refs/xchg/att/<хеш блоба>`, в письме строка `attachments: att:<хеш>/<имя> …`. Выкладка до записи
письма (`upload_all`, отказ хаба — ничего не отправлено), скачивание в `<клон>/.git/xchg-att/<хеш>/`.
`hub_sync` тянет только ветки, поэтому вложения не качаются, пока их не попросят. `forward` скачивает
файлы из исходного хаба и выкладывает в целевой.

Сборка — `tools/package.sh <харнесс> <каталог>`: кладёт файлы `harness/<имя>/` и настоящие копии
`bin/`, `skills/`, `hub/`, `LICENSE` плюс сгенерированный README. Публикация —
`tools/publish.sh <харнесс> <версия>`: перезаписывает репозиторий пакета целиком и ставит тот же тег;
запускает её `.github/workflows/release.yml` по тегу `v*` (секрет `PACKAGE_REPOS_TOKEN`).
Репозитории пакетов руками не правят — следующий релиз затрёт.

Общее для всех: `bin/xchg`, скиллы `skills/exchange` и `skills/xchg-setup` (настройка), обёртки
команды `/xchg:setup` — `harness/claude-code/commands/setup.md` и
`harness/gemini/commands/xchg/setup.toml`. Версия одна во всех трёх манифестах (тест сверяет).

Хуки всех трёх зовут `xchg inbox --brief`. Клиент читает `hook_event_name` из JSON на stdin
(`SessionStart` → всё открытое, любое другое → только новое) и отвечает
`{"hookSpecificOutput":{"hookEventName":…,"additionalContext":…}}` (`hook_print`, `json_str`); без JSON
на stdin — текстом. Нечего сказать — 0 байт.

`PLUGIN_MODE`: `$XCHG_ROOT` внутри `~/.claude/plugins/`, `~/.codex/plugins/` или `~/.gemini/extensions/`.
Тогда нет самообновления (обновляет харнесс), `install` только создаёт конфиг, `cmd_version` берёт
версию из манифеста. Отдельная установка (`install`) настраивает каждый найденный харнесс по таблице
`harness_info`: файл хуков, имена событий, единицы таймаута, каталог скиллов.

## Состояние на диске

- `~/.config/xchg/xchg.conf` — реестр хабов (не в git).
- `<клон>/.git/xchg-last-sync`, `xchg-unavail` — стампы синхронизации и недоступности.
- `<клон>/.git/xchg-read/<проект>--<адрес>` — прочитанные заметки: список имён файлов, свой у каждого агента.
- `<клон>/.git/xchg-shown/<проект>` — имена писем, уже показанных агенту (хук, `inbox`, `wait`, свои отправки): `wait` будит только на остальные.
- `<клон>/.git/xchg-muted/<проект>` — имена писем, заглушённых этим агентом (`xchg mute`); `claim` снимает пометку.
- `git config xchg.project` в клоне рабочего репозитория — имя проекта, если клон назван иначе.
