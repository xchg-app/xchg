#!/usr/bin/env bash
# Builds an installable package for one harness: the harness files from harness/<name>/
# plus real copies of what every package carries (the client, the skills, the hub template).
# The package repositories hold exactly this output; nothing there is written by hand.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
usage() { echo "usage: tools/package.sh <claude-code|codex|gemini> <output directory>" >&2; exit 2; }

name="${1:-}"; out="${2:-}"
[ -n "$name" ] && [ -n "$out" ] || usage
src="$ROOT/harness/$name"
[ -d "$src" ] || { echo "no harness $name in $ROOT/harness" >&2; exit 1; }

case "$name" in
  claude-code) title="Claude Code plugin"; manifest=".claude-plugin/plugin.json"
    install='```
/plugin marketplace add xchg-app/claude-code-plugin
/plugin install xchg@xchg
```' ;;
  codex) title="Codex CLI plugin"; manifest=".codex-plugin/plugin.json"
    install='```bash
codex plugin marketplace add xchg-app/codex-plugin
codex plugin add xchg@xchg
```' ;;
  gemini) title="Gemini CLI extension"; manifest="gemini-extension.json"
    install='```bash
gemini extensions install https://github.com/xchg-app/gemini-plugin
```' ;;
  *) usage ;;
esac

rm -rf "$out"; mkdir -p "$out"
# the harness files: manifests, hooks, commands
(cd "$src" && find . -mindepth 1 -maxdepth 1 -exec cp -R {} "$out/" \;)
# the shared part, dereferenced: a package must stand on its own
for shared in bin skills hub LICENSE; do cp -RL "$ROOT/$shared" "$out/$shared"; done
# the package is installed by a plain git clone: with core.autocrlf=true the client would arrive
# with CRLF and fail on "bash\r", so the package repository pins LF itself
printf '* text=auto eol=lf\n' > "$out/.gitattributes"

version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$out/$manifest" | head -1)
[ -n "$version" ] || { echo "no version in $manifest" >&2; exit 1; }

cat > "$out/README.md" <<EOF
# xchg — $title

Messaging between coding agents through git hubs: tasks and notes, addressed to a hub, a project,
a person or a single agent. No server and no database, just git.

$install

After installing, restart the session and run the setup command, or ask the agent to set up xchg.
What the package brings and how to update or remove it:
[docs/harnesses.md](https://github.com/xchg-app/xchg/blob/main/docs/harnesses.md).

## This repository is generated

Every file here is built from [xchg-app/xchg](https://github.com/xchg-app/xchg) and
overwritten on each release, so changes made here are lost. Issues and pull requests belong in that
repository; this one only ships version $version of the package.

[MIT](LICENSE) © Nikolay Pronchev.
EOF

echo "$name $version -> $out"
