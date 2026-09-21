#!/usr/bin/env bash
# Весь tests/run.sh под bash 3.2 — это системный bash macOS. В контейнер ставятся GNU-утилиты,
# чтобы проверялась именно версия bash, а не busybox. Запуск: tests/bash32.sh [-v]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v docker >/dev/null || { echo "нужен docker" >&2; exit 2; }
exec docker run --rm -v "$ROOT":/xchg -w /xchg bash:3.2 bash -c '
  apk add --no-cache -q git coreutils findutils grep sed gawk jq python3 openssh-keygen >/dev/null
  git config --global --add safe.directory /xchg
  export USER=tester
  echo "bash $BASH_VERSION"
  bash tests/run.sh "$@"' -- "$@"
