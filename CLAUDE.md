# CLAUDE.md — xchg

Клиент обмена сообщениями между агентами для программирования через git-хабы. Один bash-скрипт `bin/xchg`;
репозиторий заодно — исходник пакетов для харнессов Claude Code, Codex CLI и Gemini CLI: каждый собирается из `harness/<имя>/` и выкладывается в свой репозиторий; Hermes Agent и Cline настраивает `xchg install` (раскладка — [.claude-docs/architecture.md](.claude-docs/architecture.md)).
Пользовательская документация — [`docs/`](docs/), внутренняя — [`.claude-docs/`](.claude-docs/index.md).

## Documentation index
- [.claude-docs/index.md](.claude-docs/index.md) — что читать под какую задачу
- [.claude-docs/architecture.md](.claude-docs/architecture.md) — устройство `bin/xchg`, потоки данных
- [.claude-docs/gotchas.md](.claude-docs/gotchas.md) — ловушки bash и git, на которых уже спотыкались
- [docs/hubs.md](docs/hubs.md), [docs/cli.md](docs/cli.md), [docs/agents.md](docs/agents.md), [docs/autonomous.md](docs/autonomous.md) — поведение, обещанное пользователю

## Commands
- `tests/run.sh [-v]` — e2e в песочнице (HOME подменяется, хабы — локальные bare). Обязателен перед коммитом в `bin/xchg`.
- `tests/bash32.sh [-v]` — тот же прогон под bash 3.2 в docker. Обязателен перед коммитом в `bin/xchg`.
- `bash -n bin/xchg` — синтаксис.
- `tools/package.sh <харнесс> <каталог>` — собрать пакет; `tools/publish.sh <харнесс> <версия> [--dry-run]` — выложить его в репозиторий пакета. Настоящую установку собранного пакета в песочный HOME `tests/run.sh` делает для каждого харнесса, чей CLI есть в PATH (`claude`, `codex`, `gemini`).
- `XCHG_NO_SELFUPDATE=1 bin/xchg <cmd>` — прогнать клиент из репозитория против настоящих хабов.

## Boundaries
### MUST
- Клиент — чистый bash ≥ 3.2 (системный bash macOS) + git/awk/sed/coreutils: без ассоциативных массивов, пустые массивы разворачивать как `${a[@]+"${a[@]}"}`, перед не-ASCII писать `${var}`, `case` внутри `$( )` — только со скобкой перед шаблоном: `(*/done/*)`. `python3` и `jq` только как необязательные ускорители (есть fallback).
- Всё исполнение `bin/xchg` — внутри `main`, последняя строка файла — `main "$@"; exit $?`: иначе правка файла на месте во время работы команды портит её выход и код возврата.
- Изменение поведения — код, тест в `tests/run.sh` и правка соответствующего файла в `docs/` и `docs/ru/` в одном коммите.
- Документация и тесты не привязаны к окружению автора: примеры — `alice`/`bob`, `example.com`, проекты `api`/`web`. Исключение — адрес самого репозитория xchg в инструкциях по установке.
- Документация описывает текущее устройство. Никаких «раньше было», версий и истории решений.
- Пользовательская документация на английском (`README.md`, `docs/`), русский перевод — `README.ru.md`, `docs/ru/`; правишь один — правь оба.
- Весь текст клиента на английском: сообщения, комментарии, то, что он пишет в хаб. Ошибки на stderr, с подсказкой следующей команды; код ≠ 0 (2 — неверный вызов, 3 — `wait` не дождался письма, 4 — записано локально, но в хаб не отправлено).
- `inbox --brief` при отсутствии нового печатает 0 байт: хуки не должны тратить токены. «Новое» — то, что этому агенту ещё не показывали; всё открытое показывает только `SessionStart`.
### MUST NOT
- Не добавлять реле между хабами, БД, HTTP, MCP, хранение состояния агентов — см. [docs/design.md](docs/design.md).
- Не запускать `bin/xchg install` в реальном HOME при разработке — только в песочнице (`tests/run.sh`).
- Не коммитить `~/.config/xchg/*` и содержимое хабов.
- Не класть в корень репозитория файлы одного харнесса (`hooks/`, `commands/`, манифесты) и не править репозитории пакетов руками: их перезаписывает релиз.

## Workflow
- Ветка `main`, коммиты однострочные.
- Релиз: поднял `version` (одинаково в `harness/claude-code/.claude-plugin/plugin.json`, `harness/codex/.codex-plugin/plugin.json`, `harness/gemini/gemini-extension.json`) — на этот же коммит аннотированный тег `v<версия>` (`git tag -a v0.1.11 -m v0.1.11`) и `git push --tags`. Bump версии и тег — один коммит; по тегу версия клиента закрепляется в чужих сборках. Дальше по тегу `.github/workflows/release.yml` пересобирает три пакета и перезаписывает репозитории `claude-code-plugin`, `codex-plugin`, `gemini-plugin` тем же тегом.
