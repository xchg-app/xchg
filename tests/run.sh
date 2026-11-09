#!/usr/bin/env bash
# xchg e2e tests in a sandbox: HOME is replaced, hubs are local bare repositories.
# Run: tests/run.sh [-v]. Names are made up: alice/bob/carol, projects api and web.
# One scenario with shared state: each section builds on the previous ones.
# Only what guards a rule of CLAUDE.md, a bug that already happened, or the delivery of mail.
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
hook() { local ev="$1"; shift; printf '{"session_id":"t","hook_event_name":"%s"}' "$ev" | "$@"; }
put() {  # <path in hub> <from> <to> <kind> <title> [re]: a message from someone else, through the second clone
  local re=""; [ -z "${6:-}" ] || re="re: $6"$'\n'
  git -C "$W2" pull -q; mkdir -p "$(dirname "$W2/$1")"
  printf -- '---\nfrom: %s\nto: %s\nkind: %s\ndate: 2026-09-09T10:00:00Z\n%s---\n# %s\n' "$2" "$3" "$4" "$re" "$5" > "$W2/$1"
  ( cd "$W2" && git add -A && git commit -qm put && git push -q )
}

H="$SB/home"; mkdir -p "$H"; export HOME="$H"
for r in api web tool; do mkdir -p "$SB/repos/$r"; git init -q "$SB/repos/$r"; done
in_api()  { ( cd "$SB/repos/api" && "$@" ); }
in_web()  { ( cd "$SB/repos/web" && "$@" ); }
in_tool() { ( cd "$SB/repos/tool" && "$X" "$@" ); }
CONFF="$H/.config/xchg/xchg.conf"

t "static: bash 3.2 and the last line"
assert_eq "$(grep -c 'declare -A' "$X" || true)" 0 "no associative arrays"
BAD=$(LC_ALL=C awk '/\$[A-Za-z_][A-Za-z0-9_]*[\200-\377]/ {print FNR": "$0}' "$X")
assert_eq "$BAD" "" "no non-ASCII right after a variable name (under set -u the byte becomes part of the name)"
assert_eq "$(tail -n 1 "$X")" 'main "$@"; exit $?' "the last line calls main and exits"

t "install"
mkdir -p "$H/.claude"
run "$X" install </dev/null
run "$X" install </dev/null; assert_eq "$(jq '.hooks.SessionStart | length' "$H/.claude/settings.json")" 1 "install is idempotent: no duplicate hooks"
run "$X" inbox --brief; assert_eq "$OUT" "" "no hubs: the hook stays silent (0 bytes)"

t "hub, tokens, keys"
git init -q --bare "$SB/bare-work"
git config --global init.defaultBranch master   # the hub branch must not depend on the local default
run "$X" hub init work --remote "$SB/bare-work" --login alice
assert_eq "$(git -C "$H/exchange/work" branch --show-current)" main "the hub is always on main"
git config --global init.defaultBranch main
run "$X" hub add tok "https://alice:SECRET@example.invalid/git/tok.git" --login alice
assert_not_contains "$OUT" "SECRET"
if command -v ssh-keygen >/dev/null; then
  run "$X" key new --name demo; K="$H/.config/xchg/keys/demo_ed25519"
  BEFORE=$(cat "$K"); run "$X" key new --name demo; assert_eq "$(cat "$K")" "$BEFORE" "an existing key is never overwritten"
else ok "no ssh-keygen: key tests skipped"; fi

t "harness packages"
PKG="$SB/packages"; VER=$(jq -r .version "$ROOT/harness/gemini/gemini-extension.json")
BAD=""
for p in "claude-code .claude-plugin/plugin.json" "codex .codex-plugin/plugin.json" "gemini gemini-extension.json"; do
  set -- $p
  run "$ROOT/tools/package.sh" "$1" "$PKG/$1"; [ "$RC" = 0 ] && [ "$(jq -r .version "$PKG/$1/$2")" = "$VER" ] || BAD="$BAD $1"
done
assert_eq "$BAD" "" "the three packages build, with one version"
# a clone on a machine with core.autocrlf=true (how Windows git is set up) still gets a working client
BARE="$SB/gemini-plugin.git"; git init -q --bare "$BARE"
run env XCHG_PACKAGE_REPO="$BARE" "$ROOT/tools/publish.sh" gemini "$VER"
run git -c core.autocrlf=true clone -q "$BARE" "$SB/crlf-clone"
grep -q "$(printf '\r')" "$SB/crlf-clone/bin/xchg" && fail "the client arrived with CRLF under autocrlf=true" || ok "the client arrives with LF under autocrlf=true"
# validate doesn't catch load errors: a real install into a separate HOME
if command -v claude >/dev/null 2>&1; then PH="$SB/claude-home"; mkdir -p "$PH"
  run env HOME="$PH" claude plugin marketplace add "$PKG/claude-code"
  run env HOME="$PH" claude plugin install xchg@xchg; RC1=$RC; run env HOME="$PH" claude plugin list
  [ "$RC1" = 0 ] && ! grep -qF "failed to load" <<< "$OUT" && ok "claude-code: the plugin installs and loads" || fail "claude-code: the plugin doesn't install or load" "$OUT"
else ok "no claude CLI: claude-code install skipped"; fi
if command -v codex >/dev/null 2>&1; then PH="$SB/codex-home"; mkdir -p "$PH/.codex"
  run env HOME="$PH" CODEX_HOME="$PH/.codex" codex plugin marketplace add "$PKG/codex"
  run env HOME="$PH" CODEX_HOME="$PH/.codex" codex plugin add xchg@xchg; assert_eq "$RC" 0 "codex: the plugin installs"
else ok "no codex CLI: codex install skipped"; fi
if command -v gemini >/dev/null 2>&1; then PH="$SB/gemini-home"; mkdir -p "$PH"
  run bash -c "yes y | HOME='$PH' gemini extensions install '$PKG/gemini' --consent"; assert_eq "$RC" 0 "gemini: the extension installs"
else ok "no gemini CLI: gemini install skipped"; fi

t "projects and agents"
run in_api "$X" projects add api --repo "git@example.com:team/api.git"; assert_contains "$OUT" "agent registered: work:@api:alice"
run in_web "$X" projects add --repo "git@example.com:team/web.git"
# a token in the origin URL must not land in the hub
mkdir -p "$SB/repos/sec"; git init -q "$SB/repos/sec"; git -C "$SB/repos/sec" remote add origin "https://alice:SECRET@example.invalid/team/sec.git"
run bash -c "cd '$SB/repos/sec' && '$X' projects add sec"
assert_not_contains "$(cat "$H/exchange/work/projects/sec/README.md" "$H/exchange/work/projects/sec/alice/README.md")" "SECRET"

t "addresses"
printf '| bob | Борис Петров | боря | bob@example.com |\n| carol | Кэрол | | carol@example.com |\n' >> "$H/exchange/work/contacts.md"
mkdir -p "$H/exchange/work/people/bob" "$H/exchange/work/people/carol"
# erin's alias equals the login bob: the login wins
awk '{print} /^\|---/ {print "| erin | Эрин | bob | erin@example.com |"}' "$H/exchange/work/contacts.md" > "$SB/c.md" && mv "$SB/c.md" "$H/exchange/work/contacts.md"
( cd "$H/exchange/work" && git add -A && git commit -qm contacts && git push -q )
run in_api "$X" send bob:@api task1 <<< "# A task for Bob's agent"
run in_api "$X" send боря task3 <<< '# To a person by alias'; assert_contains "$OUT" "sent: work:people/bob/"
run in_api "$X" send bob task5 <<< "# By login, not by someone else's alias"; assert_contains "$OUT" "sent: work:people/bob/"
run in_api "$X" post all news <<< '# Release 2.3'
# python3 is optional: without it the book lookup falls back to awk
NOPY="$SB/nopy"; mkdir -p "$NOPY"
for dir in $(for c in bash git awk sed grep date mktemp env; do dirname "$(command -v "$c")"; done | sort -u); do
  for f in "$dir"/*; do case "${f##*/}" in (python3*) continue;; esac
  [ -x "$f" ] && [ ! -e "$NOPY/${f##*/}" ] && ln -s "$f" "$NOPY/${f##*/}"; done; done; true
run in_api env PATH="$NOPY" "$X" send "Борис Петров" task9 <<< '# Full name without python3'; assert_contains "$OUT" "sent: work:people/bob/"
M=$(ls "$H/exchange/work/projects/api/bob/"*task1.md)
assert_eq "$(sed -n 's/^from: //p; s/^to: //p; s/^kind: //p' "$M" | tr '\n' ' ')" "alice/api @api:bob task " "from, to and kind of a task"

t "inbox shows only this session's addresses"
W2="$SB/w2"; git clone -q "$SB/bare-work" "$W2"
in_api "$X" inbox >/dev/null; in_web "$X" inbox >/dev/null   # both agents are already known: a new agent has its own test
put projects/api/alice/20260909-100000_bob_schema.md bob/api @api:alice task "Fix the schema"
put projects/web/alice/20260909-100500_carol_head.md carol/web @web:alice task "Fix the header"
put people/alice/20260909-101000_bob_personal.md bob/api alice task "Personal request"
put projects/api/20260909-101500_carol_queue.md carol/web @api task "A task in the api queue"
put all/20260909-102000_carol_friday.md carol/web all note "Short day on Friday"
run in_api "$X" inbox
assert_not_contains "$OUT" "Fix the header"   # another project's mail is not this agent's
# the address and file columns are the message's own: read/seen/reply take them as is
assert_contains "$OUT" "work     all          message all/20260909-102000_carol_friday.md"
run in_api "$X" seen all
run in_api "$X" inbox
! grep -qF "Short day on Friday" <<< "$OUT" && grep -qF "A task in the api queue" <<< "$OUT" && ok "seen: a read message goes, a task stays" || fail "seen: a message stayed or a task went" "$OUT"
run in_web "$X" inbox; assert_contains "$OUT" "Short day on Friday"   # read marks are per agent

t "a new agent doesn't get the old history as unread"
put projects/fresh/20260901-100000_carol_oldnews.md carol/web @fresh message "Old project news"
put projects/fresh/alice/20260901-100500_carol_handover.md carol/web @fresh:alice message "Handed over to the agent"
put projects/fresh/20260901-101000_carol_oldtask.md carol/web @fresh task "Old open task"
mkdir -p "$SB/repos/fresh"; git init -q "$SB/repos/fresh"; ( cd "$SB/repos/fresh" && "$X" projects add >/dev/null )
run bash -c "cd '$SB/repos/fresh' && '$X' inbox"
assert_not_contains "$OUT" "Old project news"
grep -qF "Old open task" <<< "$OUT" && grep -qF "Handed over to the agent" <<< "$OUT" && ok "old tasks and the agent's own address stay" || fail "an old task or the agent's own mail was marked read" "$OUT"
# old messages of shared addresses are read; old tasks and the agent's own address stay
git -C "$W2" pull -q; git -C "$W2" rm -rq projects/fresh; ( cd "$W2" && git commit -qm "fresh away" && git push -q ); "$X" sync >/dev/null

t "claim and done"
Q=$(ls "$H/exchange/work/projects/api/"*queue.md)
run in_api "$X" claim "$Q"
# whoever pushes first wins the race
put projects/api/20260909-110000_carol_second.md carol/web @api task "Second task"; "$X" sync >/dev/null
git -C "$W2" mv projects/api/20260909-110000_carol_second.md projects/api/bob/; ( cd "$W2" && git commit -qm claim && git push -q )
run in_api "$X" claim "$H/exchange/work/projects/api/20260909-110000_carol_second.md"
[ "$RC" = 1 ] && grep -qF "already taken by bob" <<< "$OUT" && ok "the race is lost to whoever pushed first" || fail "the lost race isn't reported" "$OUT"
[ -z "$(git -C "$H/exchange/work" status --porcelain)" ] && ok "the clone is clean after losing" || fail "the clone is dirty" "$(git -C "$H/exchange/work" status --short)"
run in_api "$X" done "$(ls "$H/exchange/work/projects/api/alice/"*queue.md)"
run in_api "$X" inbox; assert_not_contains "$OUT" "A task in the api queue"   # a closed task leaves the inbox

t "reply, thread, sent"
P=$(ls "$H/exchange/work/people/alice/"*personal.md)
run in_api "$X" reply "$P" ok <<< '# Done it'; assert_contains "$OUT" "sent: work:projects/api/bob/"   # the reply goes to the sender's agent, not the person
R=$(ls -t "$H/exchange/work/projects/api/bob/"*ok.md | head -1)
run in_api "$X" done "$P"; run in_api "$X" thread "$R"
assert_eq "$(awk '/Personal request/ {print $3}' <<< "$OUT")" "closed" "a closed task is read from history"
run in_api "$X" reply "$R" again <<< '# Forgot to say'; assert_contains "$OUT" "sent: work:projects/api/bob/"   # a reply to my own message goes on to its recipient
T1=$(ls "$H/exchange/work/projects/api/bob/"*task1.md)
run in_api "$X" reply "$T1" ping <<< '# Any news?'   # the sender's own follow-up is not an answer
run in_api "$X" sent; assert_eq "$(awk '/A task for Bob/ {print $4}' <<< "$OUT")" "waiting" "an unanswered task waits"
assert_not_contains "$OUT" "Release 2.3"   # sent lists tasks only, not messages
put projects/api/alice/20260909-120000_bob-api_task1-done.md bob/api @api:alice message "Task1 is done" "$(basename "$T1")"
run in_api "$X" sent; assert_eq "$(awk '/A task for Bob/ {print $4}' <<< "$OUT")" "replied" "the recipient's answer marks the task replied"
put projects/api/alice/20260909-120000_carol_lunch.md carol/web @api:alice message "Lunch at noon?"
run in_api "$X" reply "$H/exchange/work/projects/api/alice/20260909-120000_carol_lunch.md" lunch-yes <<< '# Yes'
run in_api "$X" inbox; assert_not_contains "$OUT" "Lunch at noon?"   # an answered message is read

t "wait: waiting without a human"
run in_api "$X" inbox >/dev/null
( sleep 1; put projects/api/alice/20260910-090000_bob_wake.md bob/api @api:alice task "Wake up" ) &
BG=$!; run in_api "$X" wait --timeout 30 --interval 1; wait "$BG" 2>/dev/null || true
assert_eq "$RC" 0 "a new message wakes"; assert_contains "$OUT" "Wake up"
run in_api "$X" send @api:alice note-to-self <<< '# A note to self'
run in_api "$X" wait --timeout 1 --interval 1; assert_eq "$RC" 3 "my own message doesn't wake"

t "hooks and mute"
put people/alice/20260910-100000_carol_notmine.md carol/web alice task "Not for the api agent"
run in_api hook UserPromptSubmit "$X" inbox --brief
assert_eq "$(jq -r .hookSpecificOutput.hookEventName <<< "$OUT")" UserPromptSubmit "hook output is valid JSON with the event name"
run in_api hook UserPromptSubmit "$X" inbox --brief; assert_eq "$OUT" "" "a repeated hook on the same stays silent (0 bytes)"
run in_api hook SessionStart "$X" inbox --brief; assert_contains "$OUT" "Not for the api agent"   # session start shows what is open again
put projects/api/alice/20260910-095000_bob_quote.md bob/api @api:alice task 'Quote "this" and back\slash'
run in_api hook BeforeAgent "$X" inbox --brief
assert_contains "$(jq -r .hookSpecificOutput.additionalContext <<< "$OUT")" 'Quote "this" and back\slash'   # quotes and backslashes are escaped
NM="$H/exchange/work/people/alice/20260910-100000_carol_notmine.md"
run in_api "$X" mute "$NM"; run in_api "$X" inbox; assert_not_contains "$OUT" "Not for the api agent"

t "a reply in the personal address goes to the agent that has seen the original"
run in_tool post bob ask <<< '# A question from tool'
ASK=$(basename "$(ls "$H/exchange/work/people/bob/"*ask.md)")
put "people/alice/$(date -u +%Y%m%d-%H%M%S)_bob-api_answer.md" bob/api alice message "Answer for tool" "$ASK"
run in_api "$X" inbox; A1=$OUT; run in_tool inbox
! grep -qF "Answer for tool" <<< "$A1" && grep -qF "Answer for tool" <<< "$OUT" && ok "the reply reaches the agent that sent the original, and only it" || fail "the reply went to the wrong agent" "$A1"$'\n---\n'"$OUT"

t "second hub: my own agents under one login"
run "$X" hub init me --login alice
run in_api "$X" projects add api --hub me; run in_web "$X" projects add web --hub me
run in_api "$X" send me:@web:alice handoff <<< '# Continue the migration'
run in_web "$X" reply "$(ls "$H/exchange/me/projects/web/alice/"*handoff.md)" started <<< '# Started'
assert_contains "$OUT" "sent: me:projects/api/alice/"   # the reply goes to the agent that wrote: the login is shared, the agent is not
run in_api "$X" send @api:alice self <<< '# A note to self'
[ "$RC" = 1 ] && grep -qF "git config xchg.hub work" <<< "$OUT" && ok "an address in two hubs is refused, with the way to choose" || fail "an ambiguous address isn't refused" "$OUT"
git -C "$SB/repos/api" config xchg.hub me
run in_api "$X" send @api:alice self <<< '# A note to self'; assert_contains "$OUT" "sent: me:projects/api/alice/"   # git config xchg.hub decides
git -C "$SB/repos/api" config --unset xchg.hub
S=$(ls "$H/exchange/work/projects/api/alice/"*schema.md)
run in_api "$X" forward "$S" me:@api:alice --note "moving it"
assert_contains "$(cat "$(ls -t "$H/exchange/me/projects/api/alice/"*fwd*.md | head -1)")" "forwarded_from: work/projects/api/alice/"

t "attachments arrive byte for byte"
printf '\x89PNG\r\n\x1a\n\x00\x01binary' > "$SB/shot.png"
printf '<html>\r\n<body>crlf stays</body>\r\n</html>\r\n' > "$SB/page.html"
git config --global core.autocrlf true   # the setting that would rewrite line endings if bytes went through filters
run in_api "$X" send work:@api:alice pics --attach "$SB/shot.png" --attach "$SB/page.html" <<< '# Two files'
M=$(ls -t "$H/exchange/work/projects/api/alice/"*pics.md | head -1)
# file:// and not a bare path: a clone from a plain path copies the whole object store, like no server does
run "$X" hub add work2 "file://$SB/bare-work" --path "$SB/w3" --login alice
run "$X" get "work2:${M#$H/exchange/work/}"
cmp -s "$(grep page.html <<< "$OUT")" "$SB/page.html" && cmp -s "$(grep shot.png <<< "$OUT")" "$SB/shot.png" &&
  ok "attachments arrive byte for byte, binary and CRLF" || fail "an attachment changed on the way" "$OUT"
HP=$(sed -n 's/^attachments: //p' "$M" | tr ' ' '\n' | grep page.html | sed 's#^att:##; s#/.*##')
run "$X" get "att:$HP/../../escape.html" --hub work2 --to "$SB/dl"; assert_eq "$OUT" "$SB/dl/escape.html" "a name can't leave the directory"
git config --global --unset core.autocrlf
n0=$(ls "$H/exchange/work/projects/api/alice/" | wc -l)
run in_api "$X" send work:@api:alice nofile --attach "$SB/nosuch.png" <<< '# Missing'
[ "$RC" = 1 ] && [ "$(ls "$H/exchange/work/projects/api/alice/" | wc -l)" = "$n0" ] && ok "a missing attachment stops the send, nothing is written" || fail "a message went out without its attachment" "$OUT"
run "$X" hub rm work2 >/dev/null; run "$X" hub rm me >/dev/null

t "hub upgrade"
git init -q --bare "$SB/bare-up"; run "$X" hub init up --remote "$SB/bare-up" --path "$SB/up" --login alice
sed -i -E 's/^contract: *[0-9]+/contract: 99/' "$SB/up/README.md"; git -C "$SB/up" commit -qam newer; git -C "$SB/up" push -q; S=$(git -C "$SB/up" rev-parse HEAD)
run "$X" hub upgrade up --contract
[ "$RC" = 1 ] && [ "$(git -C "$SB/up" rev-parse HEAD)" = "$S" ] && ok "a hub of a newer contract is refused and left as it is" || fail "upgrade touched a hub of a newer contract" "$OUT"
run "$X" hub rm up >/dev/null

t "a push that didn't go through"
mv "$SB/bare-work" "$SB/bare-work.off"
run in_api "$X" send bob offline <<< '# Sent without network'; assert_eq "$RC" 4 "send to an unreachable hub exits 4"
run in_api "$X" inbox --brief; assert_eq "$RC" 0 "an unreachable hub doesn't break inbox"
mv "$SB/bare-work.off" "$SB/bare-work"
run in_api "$X" sync
git -C "$W2" pull -q; [ -n "$(ls "$W2/people/bob/"*_offline.md 2>/dev/null)" ] && ok "sync delivered the message" || fail "sync didn't deliver the message"
printf '#!/bin/sh\necho "xchg: refusal test" >&2\nexit 1\n' > "$SB/bare-work/hooks/pre-receive"; chmod +x "$SB/bare-work/hooks/pre-receive"
WH="$H/exchange/work"; HEAD0=$(git -C "$WH" rev-parse HEAD)
run in_api "$X" send bob refused <<< '# Refused'
[ "$RC" = 1 ] && [ "$(git -C "$WH" rev-parse HEAD)" = "$HEAD0" ] && ok "a hub refusal exits 1 and rolls the local commit back" || fail "a hub refusal isn't rolled back" "$OUT"
rm "$SB/bare-work/hooks/pre-receive"
run in_api "$X" send bob key <<< $'# key\nAKIAABCDEFGHIJKLMNOP'; assert_contains "$OUT" "looks like a secret"
sed -i 's/^contract: 6/contract: 7/' "$WH/README.md"
run in_api "$X" send bob z <<< '# z'; assert_eq "$RC" 1 "a foreign contract is refused"
git -C "$WH" checkout -q README.md

t "the price of the inbox is per hub, not per message"
# a hook has 30 s and a fork costs milliseconds on WSL2: the inbox must not spawn a process per message.
git -C "$W2" pull -q
for i in $(seq -w 1 300); do
  printf -- '---\nfrom: carol/web\nto: all\nkind: message\ndate: 2026-10-20T10:00:00Z\n---\n# Bulk %s\n' "$i" > "$W2/all/20261020-100000_carol_bulk$i.md"
  printf -- '---\nfrom: bob/api\nto: @api\nkind: task\ndate: 2026-10-20T10:00:00Z\n---\n# Bulk task %s\n' "$i" > "$W2/projects/api/20261020-100000_bob_bulk$i.md"
done
( cd "$W2" && git add -A && git commit -qm bulk && git push -q )
CNT="$SB/count"; mkdir -p "$CNT"; export XCHG_TEST_COUNT="$SB/count.log"
for c in git awk sed grep sort head tail cat date mktemp sleep basename dirname tr paste find jq python3 timeout id uniq wc cut mv rm mkdir readlink; do
  real=$(command -v "$c" 2>/dev/null) || continue
  printf '#!/bin/sh\necho "$0" >> "$XCHG_TEST_COUNT"; exec "%s" "$@"\n' "$real" > "$CNT/$c"; chmod +x "$CNT/$c"; done
: > "$XCHG_TEST_COUNT"
run in_api env PATH="$CNT:$PATH" "$X" inbox
N=$(wc -l < "$XCHG_TEST_COUNT" | tr -d ' ')
[ "$N" -lt 120 ] && ok "inbox over 600 messages ran $N external processes" || fail "inbox over 600 messages ran $N external processes (a process per message?)"
: > "$XCHG_TEST_COUNT"
run in_api hook UserPromptSubmit env PATH="$CNT:$PATH" "$X" inbox --brief --max-age 300; assert_eq "$OUT" "" "the hook is silent: everything was shown"
N=$(wc -l < "$XCHG_TEST_COUNT" | tr -d ' ')
[ "$N" -lt 80 ] && ok "a silent hook over 600 messages ran $N external processes" || fail "a silent hook over 600 messages ran $N external processes"
unset XCHG_TEST_COUNT

t "the project is found by origin, git config xchg.project wins"
mkdir -p "$SB/repos/api-fork"; git init -q "$SB/repos/api-fork"; git -C "$SB/repos/api-fork" remote add origin "https://alice:TOKEN@EXAMPLE.com/team/api.git"
run bash -c "cd '$SB/repos/api-fork' && '$X' agent"; assert_eq "$OUT" "work:@api:alice" "found by origin: the clone name is not a project anywhere"
git -C "$SB/repos/api-fork" config xchg.project web
run bash -c "cd '$SB/repos/api-fork' && '$X' agent"; assert_eq "$OUT" "work:@web:alice" "git config xchg.project wins over origin"

t "a long hook list is digested: tasks line by line, a bulk sender one line"
run in_api "$X" seen all; run in_api "$X" seen @api   # the bulk of the previous section
for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14; do
  printf -- '---\nfrom: jira-bot/jira\nto: @api\nkind: message\ndate: 2026-09-12T10:%s:00Z\n---\n# TRND-%s closed\n' "$i" "$i" > "$W2/projects/api/20260912-10${i}00_jira-bot_trnd-$i.md"; done
put projects/api/20260912-110000_carol_once.md carol/web @api message "A human writes once"
run hook SessionStart in_api "$X" inbox --brief --hook-format text
grep -qF "jira-bot/jira 14 messages, latest: TRND-14 closed" <<< "$OUT" && grep -qF "A human writes once" <<< "$OUT" &&
  ok "a bulk sender is one line, a human stays" || fail "the digest is wrong" "$OUT"
run in_api hook UserPromptSubmit "$X" inbox --brief --max-age 300; assert_eq "$OUT" "" "everything in the digest counts as shown"

t "a hub in the registry without a clone"
# a copied config: the hub is registered, the clone is not there; an older client then left .git/xchg-* state
git init -q --bare "$SB/bare-nc"; run "$X" hub init nc0 --remote "file://$SB/bare-nc" --path "$SB/nc0" --login alice; run "$X" hub rm nc0
printf '\n[hub nc]\nremote = file://%s/bare-nc\npath = %s/nc\nlogin = alice\n' "$SB" "$SB" >> "$CONFF"
NC="hub nc: not cloned at $SB/nc (xchg hub add nc file://$SB/bare-nc)"
run hook SessionStart in_api "$X" inbox --brief --hook-format text; assert_contains "$OUT" "$NC"
[ -e "$SB/nc" ] && fail "inbox wrote state where there is no clone" || ok "no state is written without a clone"
mkdir -p "$SB/nc/.git/xchg-read"
run in_api "$X" sync
[ "$RC" = 1 ] && grep -qF "$NC" <<< "$OUT" && ! grep '^synced:' <<< "$OUT" | grep -qw nc && ok "sync names the hub and fails" || fail "sync called a hub without a clone synced" "$OUT"
run "$X" hub add nc "file://$SB/bare-nc"
[ "$RC" = 0 ] && [ -f "$SB/nc/.git/HEAD" ] && ok "hub add finishes the clone of a registered hub" || fail "no clone after hub add" "$OUT"
run "$X" hub rm nc >/dev/null

echo; echo "passed: $PASS, failed: $FAIL"; [ "$FAIL" = 0 ]
