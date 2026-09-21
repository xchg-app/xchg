#!/usr/bin/env bash
# xchg e2e tests in a sandbox: HOME is replaced, hubs are local bare repositories.
# Run: tests/run.sh [-v]. Names are made up: alice/bob/carol, projects api and web.
# Cyrillic names and aliases in contacts are intentional: they cover case-insensitive lookup beyond ASCII.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V=0; [ "${1:-}" = -v ] && V=1
SB="${XCHG_TEST_SANDBOX:-$(mktemp -d)}"; mkdir -p "$SB"; [ -n "${XCHG_TEST_SANDBOX:-}" ] || trap 'rm -rf "$SB"' EXIT
export XCHG_NO_SELFUPDATE=1 GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL="$SB/gitconfig"; git config --global init.defaultBranch main; git config --global pull.rebase true
X="$ROOT/bin/xchg"; PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); [ $V = 0 ] || echo "  ok: $1"; return 0; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/      /'; return 0; }
t()    { echo "== $1"; }
assert_contains() { grep -qF -- "$2" <<< "$1" && ok "contains '$2'" || fail "missing '$2'" "$1"; }
assert_not_contains() { grep -qF -- "$2" <<< "$1" && fail "must not contain '$2'" "$1" || ok "no '$2'"; }
assert_eq() { [ "$1" = "$2" ] && ok "$3" || fail "$3: '$1' != '$2'"; }
run() { set +e; OUT=$("$@" 2>&1); RC=$?; set -e; }

H="$SB/home"; mkdir -p "$H"; export HOME="$H"
mkdir -p "$SB/repos/api" "$SB/repos/web" "$SB/repos/tool"
for r in api web tool; do git init -q "$SB/repos/$r"; done
in_api() { ( cd "$SB/repos/api" && "$@" ); }
in_web() { ( cd "$SB/repos/web" && "$@" ); }

t "install and hub creation"
mkdir -p "$H/.claude" "$H/.codex" "$H/.gemini" "$H/.hermes" "$H/.cline"   # harnesses present: install configures each of them
run "$X" install </dev/null; assert_eq "$RC" 0 "install rc"
for hf in "claude-code .claude/settings.json UserPromptSubmit 30" "codex .codex/hooks.json UserPromptSubmit 30" "gemini .gemini/settings.json BeforeAgent 30000"; do
  set -- $hf
  assert_contains "$OUT" "$1 ($H/"
  assert_eq "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$H/$2")" 'xchg inbox --brief 2>/dev/null || true' "$1: session start hook"
  assert_eq "$(jq -r ".hooks.$3[0].hooks[0].command" "$H/$2")" 'xchg inbox --brief --max-age 300 2>/dev/null || true' "$1: prompt hook ($3)"
  assert_eq "$(jq -r ".hooks.$3[0].hooks[0].timeout" "$H/$2")" "$4" "$1: timeout in the harness's unit"
done
[ -L "$H/.claude/skills/exchange" ] && [ -L "$H/.agents/skills/xchg-setup" ] && ok "skills linked" || fail "skills not linked"
# a harness whose hooks are a file per event gets files, but only where that harness already keeps them:
# the path differs between builds, so the client never creates one on a guess
[ -d "$H/Documents" ] && fail "install created a directory the harness may not read" || ok "no hooks directory: nothing is created"
assert_contains "$OUT" "TaskStart (executable)"; assert_contains "$OUT" "--hook-format cline"
ok "cline: without a hooks directory install prints what to create"
mkdir -p "$H/Documents/Cline/Rules/Hooks"
run "$X" install </dev/null
for ev in TaskStart UserPromptSubmit; do
  f="$H/Documents/Cline/Rules/Hooks/$ev"
  [ -x "$f" ] && ok "cline: hook $ev is an executable file" || fail "cline: no hook $ev"
  assert_contains "$(cat "$f")" "--hook-format cline"
done
assert_contains "$(cat "$H/Documents/Cline/Rules/Hooks/TaskStart")" "--session" "cline: the task-start hook shows everything open"
[ -L "$H/.cline/skills/exchange" ] && ok "cline: skill linked" || fail "cline: skill not linked"
assert_contains "$OUT" "add to $H/.hermes/config.yaml"; assert_contains "$OUT" "pre_llm_call"
assert_contains "$OUT" "--hook-format hermes"; ok "hermes: install prints the snippet instead of rewriting the config"
[ -L "$H/.hermes/skills/exchange" ] && ok "hermes: skill linked" || fail "hermes: skill not linked"
run "$X" status; assert_contains "$OUT" "cline: hooks TaskStart ok"; assert_contains "$OUT" "hermes: hook pre_llm_call MISSING"
printf 'hooks:\n  pre_llm_call:\n    - command: "xchg inbox --brief --max-age 300 --hook-format hermes"\n' > "$H/.hermes/config.yaml"
run "$X" status; assert_contains "$OUT" "hermes: hook pre_llm_call ok" "status reads the pasted snippet"
run "$X" install </dev/null; assert_contains "$OUT" "hook BeforeAgent already present"; ok "install is idempotent"
assert_eq "$(jq '.hooks.SessionStart | length' "$H/.claude/settings.json")" 1 "no duplicate hooks"
run "$X" inbox --brief; assert_eq "$OUT" "" "no hubs: the hook stays silent (0 bytes)"
git init -q --bare "$SB/bare-work"
git config --global init.defaultBranch master   # the hub branch must not depend on the local default
run "$X" hub init work --remote "$SB/bare-work" --login alice; assert_eq "$RC" 0 "hub init"; assert_contains "$OUT" "hub work created"
assert_eq "$(git -C "$H/exchange/work" branch --show-current)" main "the hub is always on main"
git config --global init.defaultBranch main
assert_contains "$(cat "$H/exchange/work/README.md")" "contract: 6"
run "$X" hubs; assert_contains "$OUT" "work*"; assert_contains "$OUT" "alice"

t "a token in the remote URL stays out of the output"
run "$X" hub add tok "https://alice:SECRET@example.invalid/git/tok.git" --login alice; assert_eq "$RC" 1 "clone of an unreachable remote fails"
assert_not_contains "$OUT" "SECRET"; assert_contains "$OUT" "alice:***@example.invalid"
run "$X" hub init tok2 --remote "https://alice:SECRET@example.invalid/git/tok2.git" --login alice; assert_eq "$RC" 1 "push to an unreachable remote fails"
assert_not_contains "$OUT" "SECRET"; assert_contains "$OUT" "alice:***@example.invalid"
CONFF="$H/.config/xchg/xchg.conf"; cp "$CONFF" "$SB/conf.bak"
sed -i.bak 's#^\(remote *= *\).*bare-work$#\1https://alice:SECRET@example.invalid/git/work.git#' "$CONFF"
run "$X" hubs; assert_not_contains "$OUT" "SECRET"; assert_contains "$OUT" "alice:***@example.invalid"
run "$X" hub add tok3 "https://SECRET@example.invalid/git/tok3.git" --login alice; assert_eq "$RC" 1 "clone with a token without a login fails"
assert_not_contains "$OUT" "SECRET"; assert_contains "$OUT" "https://***@example.invalid"
cp "$SB/conf.bak" "$CONFF"; rm -rf "$H/exchange/tok2"

t "an ssh key of its own, per hub"
command -v ssh-keygen >/dev/null || { ok "no ssh-keygen: key tests skipped"; SKIP_KEYS=1; }
if [ "${SKIP_KEYS:-0}" = 0 ]; then
run "$X" key new --name demo; assert_eq "$RC" 0 "key new"
K="$H/.config/xchg/keys/demo_ed25519"
[ -f "$K" ] && ok "the key is created outside ~/.ssh" || fail "no key at $K"
assert_eq "$(ls -ld "$H/.config/xchg/keys" | cut -c1-10)" "drwx------" "the key directory is private"
assert_eq "$(ls -l "$K" | cut -c1-10)" "-rw-------" "the key file is private"
assert_contains "$OUT" "ssh-ed25519" "the public key is printed"
BEFORE=$(cat "$K")
run "$X" key new --name demo; assert_contains "$OUT" "already exists"
assert_eq "$(cat "$K")" "$BEFORE" "an existing key is never overwritten"
run "$X" hub add keyed "$SB/bare-work" --login alice --ssh-key "$K"; assert_eq "$RC" 0 "hub add with a key"
assert_contains "$(git -C "$H/exchange/keyed" config core.sshCommand)" "$K" "the clone remembers the key"
assert_contains "$(git -C "$H/exchange/keyed" config core.sshCommand)" "IdentitiesOnly=yes"
assert_contains "$(git -C "$H/exchange/keyed" config core.sshCommand)" "$H/.config/xchg/known_hosts" "ssh keeps its known hosts with the config, not in ~/.ssh"
assert_contains "$(cat "$H/.config/xchg/xchg.conf")" "ssh_key = $K" "the key is written to the registry"
run "$X" hubs; assert_eq "$RC" 0 "a registry with ssh_key still parses"
run "$X" key new --name other >/dev/null; K2="$H/.config/xchg/keys/other_ed25519"
run "$X" hub key keyed "$K2"; assert_eq "$RC" 0 "hub key"
assert_contains "$(git -C "$H/exchange/keyed" config core.sshCommand)" "$K2" "the clone takes the new key"
assert_contains "$(cat "$H/.config/xchg/xchg.conf")" "ssh_key = $K2" "and so does the registry"
run "$X" hub key keyed "$H/nosuch"; assert_eq "$RC" 1 "a missing key file is an error"
run "$X" hub add bad "$SB/bare-work" --ssh-key "$H/nosuch"; assert_eq "$RC" 1 "hub add checks the key file too"
run "$X" hub check keyed; assert_eq "$RC" 0 "hub check asks git whether the hub answers"
assert_contains "$OUT" "the key $K2 is accepted"
run "$X" hub key keyed "$K" >/dev/null
cp "$H/.config/xchg/xchg.conf" "$SB/conf.keyed"
awk -v r="$SB/nosuch.git" '/^remote  = /{ $0 = "remote  = " r } { print }' "$SB/conf.keyed" > "$H/.config/xchg/xchg.conf"
run "$X" hub check keyed; assert_eq "$RC" 1 "an unreachable hub fails the check"; assert_contains "$OUT" "cannot reach"
cp "$SB/conf.keyed" "$H/.config/xchg/xchg.conf"
run "$X" hub rm keyed >/dev/null
fi

t "harness packages"
# every package is built by tools/package.sh; the package repositories hold nothing else
PKG="$SB/packages"
VER=$(jq -r .version "$ROOT/harness/gemini/gemini-extension.json")
for p in "claude-code .claude-plugin/plugin.json UserPromptSubmit" "codex .codex-plugin/plugin.json UserPromptSubmit" "gemini gemini-extension.json BeforeAgent"; do
  set -- $p; name=$1; manifest=$2; prompt=$3
  run "$ROOT/tools/package.sh" "$name" "$PKG/$name"; assert_eq "$RC" 0 "$name: the package builds"
  assert_eq "$(jq -r .version "$PKG/$name/$manifest")" "$VER" "$name: same version as the others"
  for f in bin/xchg skills/exchange/SKILL.md skills/xchg-setup/SKILL.md hub/README.md LICENSE README.md hooks/hooks.json; do
    [ -f "$PKG/$name/$f" ] && [ ! -L "$PKG/$name/$f" ] && ok "$name: has $f as a real file" || fail "$name: $f is missing or a link"
  done
  # each harness names its events, its root variable and its timeout unit differently
  assert_eq "$(jq -r '.hooks | keys | sort | join(" ")' "$PKG/$name/hooks/hooks.json")" "$(printf '%s\n' SessionStart "$prompt" | sort | tr '\n' ' ' | sed 's/ $//')" "$name: exactly the two events"
  for ev in SessionStart "$prompt"; do
    c=$(jq -r ".hooks.$ev[0].hooks[0].command" "$PKG/$name/hooks/hooks.json" | sed "s|\${CLAUDE_PLUGIN_ROOT}|R|; s|\${PLUGIN_ROOT}|R|; s|\${extensionPath}|R|")
    assert_contains "$c" "R/bin/xchg"
  done
  assert_contains "$(cat "$PKG/$name/README.md")" "generated"
done
assert_eq "$(jq -r .hooks.SessionStart[0].hooks[0].timeout "$PKG/gemini/hooks/hooks.json")" 30000 "gemini counts the timeout in milliseconds"
assert_eq "$(jq -r '.plugins[0].source' "$PKG/claude-code/.claude-plugin/marketplace.json")" "./" "claude-code: the marketplace points at the package root"
assert_eq "$(jq -r '.plugins[0].source.path' "$PKG/codex/.agents/plugins/marketplace.json")" "./" "codex: the marketplace points at the package root"
assert_not_contains "$(cat "$PKG/claude-code/.claude-plugin/plugin.json")" '"hooks"'
assert_not_contains "$(cat "$PKG/codex/.codex-plugin/plugin.json")" '"hooks"'
ok "no manifest points at hooks/hooks.json: it is found by itself, a reference would be a duplicate"
assert_contains "$(cat "$PKG/claude-code/commands/setup.md")" "xchg-setup"
assert_contains "$(cat "$PKG/gemini/commands/xchg/setup.toml")" "xchg-setup"
# nothing of a single harness may sit in the repository root: the next harness would collide with it
for f in hooks commands gemini-extension.json .claude-plugin .codex-plugin .agents; do
  [ -e "$ROOT/$f" ] && fail "the root holds $f, which belongs to one harness" || ok "the root is free of $f"
done
# the package repositories are built, never written by hand: publishing overwrites them whole
BARE="$SB/gemini-plugin.git"; git init -q --bare "$BARE"
run env XCHG_PACKAGE_REPO="$BARE" "$ROOT/tools/publish.sh" gemini "$VER"; assert_eq "$RC" 0 "the package is published"
run git -C "$BARE" show "v$VER:gemini-extension.json"; assert_contains "$OUT" "\"version\": \"$VER\"" "the tag v$VER carries the package"
run git -C "$BARE" show "v$VER:bin/xchg"; assert_contains "$OUT" "xchg"
run env XCHG_PACKAGE_REPO="$BARE" "$ROOT/tools/publish.sh" gemini "$VER"; assert_contains "$OUT" "already published"
run env XCHG_PACKAGE_REPO="$BARE" "$ROOT/tools/publish.sh" gemini 9.9.9; assert_eq "$RC" 1 "a version other than the one in the manifests is refused"
run env XCHG_PACKAGE_REPO="https://user:SECRET@example.invalid/x.git" "$ROOT/tools/publish.sh" gemini "$VER"
assert_eq "$RC" 1 "an unreachable package repository fails"; assert_not_contains "$OUT" "SECRET"

if command -v claude >/dev/null 2>&1; then
  run claude plugin validate "$PKG/claude-code"; assert_eq "$RC" 0 "claude plugin validate"
  # validate doesn't catch load errors, so do a real install into a separate HOME
  PH="$SB/claude-home"; mkdir -p "$PH"
  run env HOME="$PH" claude plugin marketplace add "$PKG/claude-code"; assert_eq "$RC" 0 "claude-code: the marketplace is added"
  run env HOME="$PH" claude plugin install xchg@xchg; assert_eq "$RC" 0 "claude-code: the plugin installs"
  run env HOME="$PH" claude plugin list; assert_contains "$OUT" "xchg@xchg"; assert_not_contains "$OUT" "failed to load"
else ok "no claude CLI: claude-code install skipped"; fi
if command -v codex >/dev/null 2>&1; then
  PH="$SB/codex-home"; mkdir -p "$PH/.codex"
  run env HOME="$PH" CODEX_HOME="$PH/.codex" codex plugin marketplace add "$PKG/codex"; assert_eq "$RC" 0 "codex: the marketplace is added"
  run env HOME="$PH" CODEX_HOME="$PH/.codex" codex plugin add xchg@xchg; assert_eq "$RC" 0 "codex: the plugin installs"
  CI=$(ls -d "$PH"/.codex/plugins/cache/xchg/xchg/*/ | head -1)
  [ -f "$CI/bin/xchg" ] && [ -f "$CI/hooks/hooks.json" ] && [ -f "$CI/skills/exchange/SKILL.md" ] && ok "codex: the installed plugin is complete" || fail "codex: the installed plugin is incomplete"
else ok "no codex CLI: codex install skipped"; fi
if command -v gemini >/dev/null 2>&1; then
  PH="$SB/gemini-home"; mkdir -p "$PH"
  run bash -c "yes y | HOME='$PH' gemini extensions install '$PKG/gemini' --consent"; assert_eq "$RC" 0 "gemini: the extension installs"
  run env HOME="$PH" gemini extensions list; assert_contains "$OUT" "xchg"
  [ -f "$PH/.gemini/extensions/xchg/bin/xchg" ] && [ -f "$PH/.gemini/extensions/xchg/hooks/hooks.json" ] && ok "gemini: the installed extension is complete" || fail "gemini: the installed extension is incomplete"
else ok "no gemini CLI: gemini install skipped"; fi

t "bash 3.2 compatibility (static; the live run is tests/bash32.sh)"
assert_eq "$(grep -c 'declare -A' "$X" || true)" 0 "no associative arrays"
BAD=$(LC_ALL=C awk '/\$[A-Za-z_][A-Za-z0-9_]*[\200-\377]/ {print FNR": "$0}' "$X")
assert_eq "$BAD" "" "no non-ASCII right after a variable name (under set -u the byte becomes part of the name)"

t "registration: contact book and passports"
assert_contains "$(cat "$H/exchange/work/contacts.md")" "| alice |"; ok "the hub creator is in the contact book"
assert_contains "$(cat "$H/exchange/work/contacts.md")" "| login | name | aliases | contact |"
[ -d "$H/exchange/work/people/alice" ] && ok "the person's directory exists" || fail "no people/alice"

t "projects and agent identity"
run in_api "$X" projects add api --repo "git@example.com:team/api.git"; assert_eq "$RC" 0 "projects add"
assert_contains "$OUT" "project added: work:projects/api"; assert_contains "$OUT" "agent registered: work:@api:alice"
assert_contains "$(cat "$H/exchange/work/projects/api/alice/README.md")" "Person: alice"
assert_contains "$(cat "$H/exchange/work/projects/api/README.md")" "Repository: git@example.com:team/api.git"
run in_api "$X" projects add api; assert_eq "$RC" 0 "a repeated projects add doesn't fail"; assert_contains "$OUT" "already exists"
run in_web "$X" projects add --repo "git@example.com:team/web.git"; assert_eq "$RC" 0 "projects add without a name, with a flag"
assert_contains "$OUT" "projects/web"; ok "the project name comes from the repository"
run in_api "$X" agent; assert_eq "$OUT" "work:@api:alice" "agent = person x project"
run in_web "$X" agent; assert_eq "$OUT" "work:@web:alice" "another repository, another agent"
run bash -c "cd '$SB/repos/tool' && '$X' agent"; assert_contains "$OUT" "is not a project in any hub"
run bash -c "cd / && '$X' agent"; assert_eq "$RC" 1 "no agent outside a repository"
run in_api "$X" projects; assert_contains "$OUT" "api              here"; assert_contains "$OUT" "git@example.com:team/api.git"
# a card written by an older client, labelled in Russian, is still read
( cd "$H/exchange/work" && mkdir -p projects/legacy && printf '# legacy\n\nРепозиторий: git@example.com:team/legacy.git\n' > projects/legacy/README.md \
  && git add -A && git commit -qm legacy && git push -q )
run in_api "$X" projects; assert_contains "$OUT" "git@example.com:team/legacy.git"
# a token in the origin URL must not land in the hub: the card and the passport only say where the code is
mkdir -p "$SB/repos/sec"; git init -q "$SB/repos/sec"; git -C "$SB/repos/sec" remote add origin "https://alice:SECRET@example.invalid/team/sec.git"
run bash -c "cd '$SB/repos/sec' && '$X' projects add sec"; assert_eq "$RC" 0 "projects add with a token in origin"
SC="$H/exchange/work/projects/sec/README.md"; SP="$H/exchange/work/projects/sec/alice/README.md"
assert_not_contains "$(cat "$SC")" "SECRET"; assert_not_contains "$(cat "$SC")" "alice:"; assert_contains "$(cat "$SC")" "Repository: https://example.invalid/team/sec.git"
assert_not_contains "$(cat "$SP")" "SECRET"; assert_not_contains "$(cat "$SP")" "alice:"; assert_contains "$(cat "$SP")" "Repository: https://example.invalid/team/sec.git"
run bash -c "cd '$SB/repos/sec' && '$X' projects add sec2 --repo https://bob:TOKEN@example.invalid/team/sec2.git"; assert_eq "$RC" 0 "projects add with a token in --repo"
assert_not_contains "$(cat "$H/exchange/work/projects/sec2/README.md")" "TOKEN"; assert_contains "$(cat "$H/exchange/work/projects/sec2/README.md")" "Repository: https://example.invalid/team/sec2.git"

t "address: part order doesn't matter, all levels"
printf '| bob | Борис Петров | боря | bob@example.com |\n| carol | Кэрол | | carol@example.com |\n' >> "$H/exchange/work/contacts.md"
mkdir -p "$H/exchange/work/people/bob" "$H/exchange/work/people/carol"
( cd "$H/exchange/work" && git add -A && git commit -qm contacts && git push -q )
run in_api "$X" send @api:bob task1 <<< "# A task for Bob's agent"; assert_eq "$RC" 0 "@api:bob"
assert_contains "$OUT" "sent: work:projects/api/bob/"
run in_api "$X" send bob:@api task2 <<< '# Same place, other order'; assert_contains "$OUT" "work:projects/api/bob/"
ok "user:project and project:user are one address"
run in_api "$X" send боря task3 <<< '# To a person by alias'; assert_contains "$OUT" "sent: work:people/bob/"
run in_api "$X" send @web task4 <<< '# Everyone on project web'; assert_contains "$OUT" "sent: work:projects/web/"
run in_api "$X" post all news --ref "api/CHANGELOG.md" <<< '# Release 2.3'; assert_contains "$OUT" "sent: work:all/"
run in_api "$X" send @nope x <<< '# x'; assert_eq "$RC" 1 "no such project"; assert_contains "$OUT" "xchg projects add nope"
run in_api "$X" send nobody x <<< '# x'; assert_eq "$RC" 1 "no such person"; assert_contains "$OUT" "xchg who"
# the registry of people is the contact book: a directory without a book row is not a recipient
mkdir -p "$H/exchange/work/people/dave"; touch "$H/exchange/work/people/dave/.gitkeep"
# an alias of a participant listed above equals the login bob: the login wins
awk '{print} /^\|---/ {print "| erin | Эрин | bob | erin@example.com |"}' "$H/exchange/work/contacts.md" > "$SB/c.md" && mv "$SB/c.md" "$H/exchange/work/contacts.md"
( cd "$H/exchange/work" && git add -A && git commit -qm gone && git push -q )
run in_api "$X" send dave x <<< '# x'; assert_eq "$RC" 1 "no messages to someone who left"; assert_contains "$OUT" "'dave' is no longer in hub work"
run in_api "$X" send work:dave x <<< '# x'; assert_eq "$RC" 1 "with a hub prefix too"; assert_contains "$OUT" "'dave' is no longer in hub work"
run in_api "$X" send work:nobody x <<< '# x'; assert_contains "$OUT" "recipient 'nobody' not found in hub work"
run in_api "$X" send bob task5 <<< "# By login, not by someone else's alias"; assert_contains "$OUT" "sent: work:people/bob/"
run in_api "$X" send Эрин task6 <<< '# By name'; assert_contains "$OUT" "sent: work:people/erin/"
# the same without python3: the book lookup falls back to awk
NOPY="$SB/nopy"; mkdir -p "$NOPY"
IFS=: read -r -a PDIRS <<< "$PATH"
for dir in "${PDIRS[@]}"; do for f in "$dir"/*; do case "${f##*/}" in (python3*) continue;; esac
  [ -x "$f" ] && [ ! -e "$NOPY/${f##*/}" ] && ln -s "$f" "$NOPY/${f##*/}"; done; done; true
run in_api env PATH="$NOPY" "$X" send боря task7 <<< '# Alias without python3'; assert_contains "$OUT" "sent: work:people/bob/"
run in_api env PATH="$NOPY" "$X" send bob task8 <<< '# Login without python3'; assert_contains "$OUT" "sent: work:people/bob/"
run in_api env PATH="$NOPY" "$X" send "Борис Петров" task9 <<< '# Full name without python3'; assert_contains "$OUT" "sent: work:people/bob/"
run in_api env PATH="$NOPY" "$X" send dave x <<< '# x'; assert_contains "$OUT" "'dave' is no longer in hub work"
M=$(ls "$H/exchange/work/projects/api/bob/"*task1.md)
assert_eq "$(sed -n 's/^from: //p' "$M")" "alice/api" "from = person/project"
assert_eq "$(sed -n 's/^to: //p' "$M")" "@api:bob" "to = canonical address"
assert_eq "$(sed -n 's/^kind: //p' "$M")" "task" "send creates a task"
assert_eq "$(sed -n 's/^kind: //p' "$(ls "$H/exchange/work/all/"*news.md)")" "note" "post creates a note"

t "inbox shows only this session's addresses"
# messages for alice are put into the hub on behalf of others
W2="$SB/w2"; git clone -q "$SB/bare-work" "$W2"
mkdir -p "$W2/projects/api/alice" "$W2/projects/web/alice" "$W2/people/alice"
printf -- '---\nfrom: bob/api\nto: @api:alice\nkind: task\ndate: 2026-09-09T10:00:00Z\n---\n# Fix the schema\n' > "$W2/projects/api/alice/20260909-100000_bob_schema.md"
printf -- '---\nfrom: carol/web\nto: @web:alice\nkind: task\ndate: 2026-09-09T10:05:00Z\n---\n# Fix the header\n' > "$W2/projects/web/alice/20260909-100500_carol_head.md"
printf -- '---\nfrom: bob/api\nto: alice\nkind: task\ndate: 2026-09-09T10:10:00Z\n---\n# Personal request\n' > "$W2/people/alice/20260909-101000_bob_personal.md"
printf -- '---\nfrom: carol/web\nto: @api\nkind: task\ndate: 2026-09-09T10:15:00Z\n---\n# A task in the api queue\n' > "$W2/projects/api/20260909-101500_carol_queue.md"
printf -- '---\nfrom: carol/web\nto: all\nkind: note\ndate: 2026-09-09T10:20:00Z\nref: web/README.md\n---\n# Short day on Friday\n' > "$W2/all/20260909-102000_carol_friday.md"
( cd "$W2" && git add -A && git commit -qm msgs && git push -q )
run in_api "$X" inbox
assert_contains "$OUT" "Fix the schema"; assert_contains "$OUT" "Personal request"
assert_contains "$OUT" "A task in the api queue"; assert_contains "$OUT" "Short day on Friday"
assert_not_contains "$OUT" "Fix the header"
assert_contains "$OUT" "in other projects (xchg inbox --all)"
run in_web "$X" inbox; assert_contains "$OUT" "Fix the header"; assert_not_contains "$OUT" "Fix the schema"
run in_api "$X" inbox --all; assert_contains "$OUT" "Fix the header"; ok "--all lifts the project filter"
run in_api "$X" inbox; assert_contains "$OUT" "@api:me"
assert_eq "$(awk '/Fix the schema/ {print $3}' <<< "$OUT")" task "kind column: task"
assert_eq "$(awk '/Short day on Friday/ {print $3}' <<< "$OUT")" note "kind column: note"

t "notes are marked read, tasks stay"
run in_api "$X" seen all; assert_contains "$OUT" "read: work:all"
run in_api "$X" seen @api:me; assert_eq "$RC" 0 "an address from the inbox column (@api:me) is accepted"; assert_contains "$OUT" "read: work:@api:alice"
run in_api "$X" seen me; assert_eq "$RC" 0 "me is me"; assert_contains "$OUT" "read: work:alice"
run in_api "$X" inbox; assert_not_contains "$OUT" "Short day on Friday"; ok "a read note is out of the way"
run in_api "$X" inbox --history; assert_contains "$OUT" "Short day on Friday"
assert_contains "$(in_api "$X" inbox)" "A task in the api queue"; ok "the task stays visible"
run in_web "$X" inbox; assert_contains "$OUT" "Short day on Friday"; ok "read marks are per agent: for web the note is still unread"

t "claim and done"
Q=$(ls "$H/exchange/work/projects/api/"*queue.md)
run in_api "$X" claim "$Q"; assert_eq "$RC" 0 "claim rc"; assert_contains "$OUT" "claimed: work:projects/api/alice/"
[ -f "$H/exchange/work/projects/api/alice/$(basename "$Q")" ] && ok "the task moved to my address" || fail "claim didn't move it"
run in_api "$X" claim "$H/exchange/work/projects/api/alice/$(basename "$Q")"; assert_eq "$RC" 1 "repeated claim"; assert_contains "$OUT" "already with an agent"
# whoever pushes first wins the race
git -C "$W2" pull -q; printf -- '---\nfrom: carol/web\nto: @api\nkind: task\ndate: 2026-09-09T11:00:00Z\n---\n# Second task\n' > "$W2/projects/api/20260909-110000_carol_second.md"
( cd "$W2" && git add -A && git commit -qm t && git push -q ); "$X" sync >/dev/null
git -C "$W2" mv projects/api/20260909-110000_carol_second.md projects/api/bob/ 2>/dev/null || { mkdir -p "$W2/projects/api/bob"; git -C "$W2" mv projects/api/20260909-110000_carol_second.md projects/api/bob/; }
( cd "$W2" && git commit -qm claim && git push -q )
run in_api "$X" claim "$H/exchange/work/projects/api/20260909-110000_carol_second.md"
assert_eq "$RC" 1 "lost race"; assert_contains "$OUT" "already taken by bob"
[ -z "$(git -C "$H/exchange/work" status --porcelain)" ] && ok "the clone is clean after losing" || fail "the clone is dirty" "$(git -C "$H/exchange/work" status --short)"
D=$(ls "$H/exchange/work/projects/api/alice/"*queue.md)
run in_api "$X" done "$D"; assert_eq "$RC" 0 "done rc"; assert_contains "$OUT" "projects/api/alice/done/"
run in_api "$X" inbox; assert_not_contains "$OUT" "A task in the api queue"; ok "a closed task leaves the inbox"
N=$(ls "$H/exchange/work/all/"*friday.md)
run in_api "$X" done "$N"; assert_eq "$RC" 1 "a note can't be closed"; assert_contains "$OUT" "xchg seen"
run in_api "$X" claim "$N"; assert_eq "$RC" 1 "a note can't be claimed"

t "reply and thread"
P=$(ls "$H/exchange/work/people/alice/"*personal.md)
run in_api "$X" reply "$P" ok <<< '# Done it'; assert_eq "$RC" 0 "reply rc"
assert_contains "$OUT" "sent: work:projects/api/bob/"; ok "the reply goes to the sender's agent, not the person"
R=$(ls -t "$H/exchange/work/projects/api/bob/"*ok.md | head -1)
assert_contains "$(cat "$R")" "re: $(basename "$P")"
# the status column is compared exactly: broken output contains both words inside the script text
run in_api "$X" thread "$R"; assert_contains "$OUT" "Personal request"; assert_contains "$OUT" "Done it"
assert_not_contains "$OUT" "syntax error"; assert_eq "$(awk '/Personal request/ {print $3}' <<< "$OUT")" "open" "status of an open task"
run in_api "$X" done "$P" ; run in_api "$X" thread "$R"
assert_not_contains "$OUT" "syntax error"; assert_eq "$(awk '/Personal request/ {print $3}' <<< "$OUT")" "closed" "a closed task is read from history"
run in_api "$X" sent; assert_contains "$OUT" "projects/api/bob/"; assert_contains "$OUT" "Done it"

t "wait: waiting without a human"
git -C "$W2" pull -q
run in_api "$X" inbox; assert_eq "$RC" 0 "inbox before waiting"
run in_api "$X" wait --timeout 2 --interval 1; assert_eq "$RC" 3 "what was shown doesn't wake"; assert_contains "$OUT" "no new messages"
( sleep 2; git -C "$W2" pull -q
  printf -- '---\nfrom: bob/api\nto: @api:alice\nkind: task\ndate: 2026-09-10T09:00:00Z\n---\n# Wake up\n' > "$W2/projects/api/alice/20260910-090000_bob_wake.md"
  ( cd "$W2" && git add -A && git commit -qm wake && git push -q ) ) &
BG=$!
run in_api "$X" wait --timeout 30 --interval 1; wait "$BG" 2>/dev/null || true
assert_eq "$RC" 0 "a new message wakes"; assert_contains "$OUT" "Wake up"; assert_contains "$OUT" "xchg: 1 new message"
run in_api "$X" wait --timeout 2 --interval 1; assert_eq "$RC" 3 "the same message doesn't wake again"
run in_api "$X" send @api:alice note-to-self <<< '# A note to self'
run in_api "$X" wait --timeout 2 --interval 1; assert_eq "$RC" 3 "my own message doesn't wake"
git -C "$W2" pull -q
printf -- '---\nfrom: carol/web\nto: @api\nkind: task\ndate: 2026-09-10T09:10:00Z\n---\n# Queue for claim\n' > "$W2/projects/api/20260910-091000_carol_q2.md"
( cd "$W2" && git add -A && git commit -qm q2 && git push -q )
run in_api "$X" inbox; assert_contains "$OUT" "Queue for claim"
run in_api "$X" claim "$H/exchange/work/projects/api/20260910-091000_carol_q2.md"; assert_eq "$RC" 0 "claim of a shown task"
run in_api "$X" wait --timeout 2 --interval 1; assert_eq "$RC" 3 "a claimed task moved, but doesn't wake again"
run in_api "$X" wait --timeout abc; assert_eq "$RC" 2 "bad timeout is a usage error"

t "the client file was rewritten in place while a command ran"
assert_eq "$(tail -n 1 "$X")" 'main "$@"; exit $?' "the last line calls main and exits"
XC="$SB/client-copy"; mkdir -p "$XC/bin" "$XC/hub"; cp "$X" "$XC/bin/xchg"; cp "$ROOT/hub/README.md" "$XC/hub/"
( cd "$SB/repos/api" && "$XC/bin/xchg" wait --interval 1 > "$SB/rw.out" 2> "$SB/rw.err"; echo $? > "$SB/rw.rc" ) &
BG=$!; sleep 2
{ head -n 1 "$XC/bin/xchg"; printf '# %0200d\n' 0; tail -n +2 "$XC/bin/xchg"; } > "$XC/new"; cat "$XC/new" > "$XC/bin/xchg"   # same inode, as an editor does
git -C "$W2" pull -q
printf -- '---\nfrom: bob/api\nto: @api:alice\nkind: task\ndate: 2026-09-11T08:00:00Z\n---\n# While the client was rewritten\n' > "$W2/projects/api/alice/20260911-080000_bob_rewrite.md"
( cd "$W2" && git add -A && git commit -qm rewrite && git push -q )
wait "$BG" 2>/dev/null || true
assert_eq "$(cat "$SB/rw.rc")" 0 "the command exited with its own code"
assert_eq "$(cat "$SB/rw.err")" "" "no script fragments in stderr"
assert_contains "$(cat "$SB/rw.out")" "While the client was rewritten"

t "mute and hooks: someone else's message doesn't wake or repeat"
hook() { local ev="$1"; shift; printf '{"session_id":"t","hook_event_name":"%s"}' "$ev" | "$@"; }
git -C "$W2" pull -q
printf -- '---\nfrom: carol/web\nto: alice\nkind: task\ndate: 2026-09-10T10:00:00Z\n---\n# Not for the api agent\n' > "$W2/people/alice/20260910-100000_carol_notmine.md"
( cd "$W2" && git add -A && git commit -qm notmine && git push -q )
run in_api hook UserPromptSubmit "$X" inbox --brief; assert_contains "$OUT" "Not for the api agent"; ok "the hook shows a new message"
# a hook gets JSON with additionalContext: the one form every supported harness adds to the model context
assert_eq "$(jq -r .hookSpecificOutput.hookEventName <<< "$OUT")" UserPromptSubmit "hook output is valid JSON with the event name"
assert_contains "$(jq -r .hookSpecificOutput.additionalContext <<< "$OUT")" $'new message (xchg inbox):\n'
run in_api hook UserPromptSubmit "$X" inbox --brief; assert_eq "$OUT" "" "a repeated hook on the same stays silent (0 bytes)"
run in_api hook SessionStart "$X" inbox --brief; assert_contains "$OUT" "in the inbox"; assert_contains "$OUT" "Not for the api agent"
ok "session start shows what is open again"
git -C "$W2" pull -q
printf -- '---\nfrom: bob/api\nto: @api:alice\nkind: task\ndate: 2026-09-10T09:50:00Z\n---\n# Quote "this" and back\\slash\n' > "$W2/projects/api/alice/20260910-095000_bob_quote.md"
( cd "$W2" && git add -A && git commit -qm quote && git push -q )
run in_api hook BeforeAgent "$X" inbox --brief; assert_eq "$(jq -r .hookSpecificOutput.hookEventName <<< "$OUT")" BeforeAgent "the other prompt event name works the same"
assert_contains "$(jq -r .hookSpecificOutput.additionalContext <<< "$OUT")" 'Quote "this" and back\slash'; ok "quotes and backslashes are escaped"
run in_api hook BeforeAgent "$X" inbox --brief; assert_eq "$OUT" "" "and stays silent on a repeat (0 bytes)"
run in_api hook SessionStart "$X" inbox --brief; assert_contains "$OUT" '"hookEventName":"SessionStart"'
run in_api bash -c "'$X' inbox --brief < /dev/null"; assert_not_contains "$OUT" "hookSpecificOutput"; ok "without hook JSON the output is plain text"
# other harnesses take the same text in a field of their own; the client is told which by --hook-format
run in_api hook SessionStart "$X" inbox --brief --hook-format hermes
assert_eq "$(jq -r .context <<< "$OUT" | head -1 | cut -c1-5)" "xchg:" "hermes gets the text in .context"
assert_not_contains "$OUT" "hookSpecificOutput"
run in_api bash -c "'$X' inbox --brief --session --hook-format cline < /dev/null"
assert_contains "$(jq -r .contextModification <<< "$OUT")" "in the inbox" "cline gets it in .contextModification, and --session shows everything open"
run in_api hook SessionStart "$X" inbox --brief --hook-format text; assert_not_contains "$OUT" "{"; ok "a harness without hook JSON takes plain text"
run in_api hook SessionStart "$X" inbox --brief --hook-format nosuch; assert_eq "$RC" 1 "an unknown hook format is an error"
NM="$H/exchange/work/people/alice/20260910-100000_carol_notmine.md"
run in_api "$X" mute; assert_eq "$RC" 2 "mute without a file is a usage error"
run in_api "$X" mute "$NM"; assert_eq "$RC" 0 "mute"; assert_contains "$OUT" "muted for agent @api"
run in_api "$X" inbox; assert_not_contains "$OUT" "Not for the api agent"; ok "not visible in this agent's inbox"
run in_api "$X" inbox --history; assert_contains "$OUT" "Not for the api agent"
run in_api hook SessionStart "$X" inbox --brief; assert_not_contains "$OUT" "Not for the api agent"; ok "nor on session start"
run in_web "$X" inbox; assert_contains "$OUT" "Not for the api agent"; ok "another agent of the same person sees it"
[ -f "$NM" ] && ok "the message in the hub is untouched" || fail "mute changed the hub"
git -C "$W2" pull -q
printf -- '---\nfrom: carol/web\nto: @web\nkind: task\ndate: 2026-09-10T10:05:00Z\n---\n# Web task\n' > "$W2/projects/web/20260910-100500_carol_webtask.md"
( cd "$W2" && git add -A && git commit -qm webtask && git push -q )
run in_api hook UserPromptSubmit "$X" inbox --brief; assert_contains "$OUT" "1 more message in other projects"
run in_api hook UserPromptSubmit "$X" inbox --brief; assert_not_contains "$OUT" "in other projects"; ok "the other-project counter doesn't repeat"
git -C "$W2" pull -q
printf -- '---\nfrom: carol/web\nto: @api\nkind: task\ndate: 2026-09-10T10:10:00Z\n---\n# Mute first, claim later\n' > "$W2/projects/api/20260910-101000_carol_later.md"
( cd "$W2" && git add -A && git commit -qm later && git push -q ); "$X" sync >/dev/null
LT="$H/exchange/work/projects/api/20260910-101000_carol_later.md"
run in_api "$X" mute "$LT"; assert_eq "$RC" 0 "mute a queued task"
run in_api "$X" claim "$LT"; assert_eq "$RC" 0 "claim a muted task"
run in_api "$X" inbox; assert_contains "$OUT" "Mute first, claim later"; ok "a task taken for myself is visible again"

t "second hub: my own agents between themselves"
run "$X" hub init me --login alice; assert_eq "$RC" 0 "personal hub"
run in_api "$X" seen me; assert_eq "$RC" 1 "me in two hubs is ambiguous"; assert_contains "$OUT" "exists in hubs: work me"
run in_api "$X" seen work:me; assert_eq "$RC" 0 "with a hub prefix it is unambiguous"; assert_contains "$OUT" "read: work:alice"
run in_api "$X" projects add api --hub me; assert_eq "$RC" 0 "project api in the personal hub"
run in_web "$X" projects add web --hub me; assert_eq "$RC" 0 "project web in the personal hub"
run in_api "$X" send me:@web:alice handoff <<< '# Continue the migration'; assert_eq "$RC" 0 "an agent writes to my other agent"
assert_contains "$OUT" "sent: me:projects/web/alice/"
run in_web "$X" inbox; assert_contains "$OUT" "Continue the migration"; assert_contains "$OUT" "me"
run in_api "$X" inbox; assert_not_contains "$OUT" "Continue the migration"; ok "another address isn't shown in this session"
run in_api "$X" send @api:alice self <<< '# A note to self'; assert_contains "$OUT" "exists in hubs: work me"
ok "the same address in two hubs is an error with a list"
run in_api "$X" send me:@api:alice self <<< '# A note to self'; assert_eq "$RC" 0 "a hub prefix resolves the ambiguity"

t "forward between hubs"
S=$(ls "$H/exchange/work/projects/api/alice/"*schema.md)
run in_api "$X" forward "$S" me:@api:alice --note "moving it to my hub"; assert_eq "$RC" 0 "forward rc"
FW=$(ls -t "$H/exchange/me/projects/api/alice/"*fwd*.md | head -1)
assert_contains "$(cat "$FW")" "forwarded_from: work/projects/api/alice/"; assert_contains "$(cat "$FW")" "moving it to my hub"
assert_contains "$(cat "$FW")" "--- forwarded from work (from bob/api) ---"
[ -e "$S" ] && ok "the original is untouched" || fail "the original is gone"

t "failed push: exit 4, sync delivers"
mv "$SB/bare-work" "$SB/bare-work.off"
run in_api "$X" send bob offline <<< '# Sent without network'; assert_eq "$RC" 4 "send to an unreachable hub exits 4"
assert_contains "$OUT" "sent: work:people/bob/"; assert_contains "$OUT" "xchg sync will send it"
run in_api "$X" sync; assert_eq "$RC" 4 "sync while the hub is down exits 4"; assert_contains "$OUT" "not sent to origin"
mv "$SB/bare-work.off" "$SB/bare-work"
run in_api "$X" sync; assert_eq "$RC" 0 "sync after the hub is back exits 0"; assert_not_contains "$OUT" "not sent"
git -C "$W2" pull -q; [ -n "$(ls "$W2/people/bob/"*_offline.md 2>/dev/null)" ] && ok "the message reached the hub" || fail "sync didn't deliver the message"

t "the hub refuses a push with an xchg: line"
printf '#!/bin/sh\necho "xchg: refusal test" >&2\nexit 1\n' > "$SB/bare-work/hooks/pre-receive"; chmod +x "$SB/bare-work/hooks/pre-receive"
WH="$H/exchange/work"; HEAD0=$(git -C "$WH" rev-parse HEAD)
run in_api "$X" send bob refused <<< '# Refused'; assert_eq "$RC" 1 "hub refusal exits 1, no retries"
assert_contains "$OUT" "xchg: refusal test"; assert_contains "$OUT" "[hub work]"; assert_not_contains "$OUT" "xchg sync will send it"
assert_eq "$(git -C "$WH" rev-parse HEAD)" "$HEAD0" "the local commit is rolled back"
[ -z "$(ls "$WH/people/bob/"*_refused.md 2>/dev/null)" ] && ok "no message file in the clone" || fail "the message stayed in the clone"
# sync with a stuck local commit shows the reason for the refusal
touch "$WH/stuck"; git -C "$WH" add stuck; git -C "$WH" commit -qm stuck
run in_api "$X" sync; assert_eq "$RC" 4 "sync on refusal exits 4"; assert_contains "$OUT" "hub work refused unsent commits: refusal test"
git -C "$WH" reset -q --hard "$HEAD0"; rm "$SB/bare-work/hooks/pre-receive"
run in_api "$X" send bob accepted <<< '# After removing the hook'; assert_eq "$RC" 0 "without the hook send goes through"

t "contacts, secrets, contract, unreachable hub"
run "$X" contact --name "Алиса Иванова" --aliases "аля"; assert_contains "$OUT" "| alice | Алиса Иванова | аля |"
run "$X" contact rm erin; assert_eq "$RC" 0 "contact rm of someone else's row"; assert_contains "$OUT" "removed from the contact book of hub work: erin"
assert_not_contains "$(cat "$H/exchange/work/contacts.md")" "| erin |"
[ -d "$H/exchange/work/people/erin" ] && ok "the directory of someone who left stays" || fail "contact rm touched people/erin"
assert_eq "$(git -C "$H/exchange/work" log -1 --format=%s)" "[xchg] contacts: -erin" "contact rm commit"
assert_eq "$(git -C "$H/exchange/work" rev-list --count '@{u}..HEAD')" 0 "contact rm pushed"
run in_api "$X" send erin x <<< '# x'; assert_eq "$RC" 1 "no messages to a removed person"; assert_contains "$OUT" "'erin' is no longer in hub work"
run "$X" contact rm erin; assert_eq "$RC" 1 "second rm: no row"; assert_contains "$OUT" "no 'erin'"
run "$X" contact rm alice; assert_eq "$RC" 1 "rm doesn't remove your own row"; assert_contains "$OUT" "xchg hub rm work"
run "$X" contact rm; assert_eq "$RC" 2 "contact rm without a login"
run "$X" who аля; assert_contains "$OUT" "work  | alice"
run "$X" who; assert_contains "$OUT" "projects: api, web"; ok "participation comes from agent directories"
run in_api "$X" send bob key <<< $'# key\nAKIAABCDEFGHIJKLMNOP'; assert_eq "$RC" 0 "a secret doesn't block"; assert_contains "$OUT" "looks like a secret"
run in_api "$X" post work:@api nofref <<< '# no link'; assert_contains "$OUT" "without --ref"
sed -i 's/^contract: 6/contract: 7/' "$H/exchange/work/README.md"
run in_api "$X" send bob z <<< '# z'; assert_eq "$RC" 1 "a foreign contract is refused"; assert_contains "$OUT" "contract 7"
git -C "$H/exchange/work" checkout -q README.md
mv "$SB/bare-work" "$SB/bare-work.off"
run in_api "$X" inbox --brief; assert_eq "$RC" 0 "an unreachable hub doesn't break inbox"; assert_contains "$OUT" "hub work is unreachable"
run in_api "$X" inbox --brief; assert_not_contains "$OUT" "unreachable"; ok "the repeat stays silent (once an hour)"
mv "$SB/bare-work.off" "$SB/bare-work"
run "$X" status; assert_contains "$OUT" "contract 6"
run "$X" hub rm me; assert_eq "$RC" 0 "hub rm"; run "$X" hubs; assert_not_contains "$OUT" "me "

t "repository name outside [a-z0-9._-]"
mkdir -p "$SB/repos/TRENDS-Frontend"; git init -q "$SB/repos/TRENDS-Frontend"
in_tf() { ( cd "$SB/repos/TRENDS-Frontend" && "$@" ); }
run in_tf "$X" agent; assert_contains "$OUT" "xchg projects add trends-frontend"
run in_tf "$X" projects add; assert_eq "$RC" 2 "without a name: refused with a hint"
assert_contains "$OUT" "xchg projects add trends-frontend"; assert_contains "$OUT" "git config xchg.project"
run in_tf "$X" projects add trends-frontend; assert_eq "$RC" 0 "with the normalized name"
assert_contains "$OUT" "is now project 'trends-frontend'"
assert_eq "$(git -C "$SB/repos/TRENDS-Frontend" config xchg.project)" trends-frontend "the name is remembered in the repository"
run in_tf "$X" agent; assert_eq "$OUT" "work:@trends-frontend:alice" "the agent is addressable under the new name"

t "config errors"
printf 'default = a\n[hub a]\npath = /tmp/a\nbogus line\n' > "$H/.config/xchg/xchg.conf"
run "$X" hubs; assert_eq "$RC" 1 "a bad line is an error"; assert_contains "$OUT" "xchg.conf:4: cannot parse"
run "$X" help; assert_eq "$RC" 0 "help works with a broken config"

echo; echo "passed: $PASS, failed: $FAIL"; [ "$FAIL" = 0 ]
