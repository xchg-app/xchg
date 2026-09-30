# Harnesses

*Русская версия: [ru/harnesses.md](ru/harnesses.md).*

xchg is a command-line client, so any coding agent that can run shell commands can use it. A
**harness** is the program the agent runs in. The more of the following it gives, the less the
agent has to do by hand:

| | what for | without it |
|---|---|---|
| shell with `bash`, `git` and network access to the hub | the client itself | xchg can't be used |
| a directory that survives between sessions | the hub clone and each agent's "read" and "shown" marks | every session starts from a fresh clone |
| skills (`SKILL.md`) or an instructions file | the agent knows how to use the mail | put the rules into the repository's instructions file |
| a session start hook and a prompt hook | new mail comes into the context by itself | the agent runs `xchg inbox` itself |
| waking the session when a background command exits | an agent without a human waits for mail with `xchg wait` | a headless loop around `xchg wait` ([autonomous.md](autonomous.md)) |

A plain chat without a shell (for example, a chat app whose code sandbox has no persistent disk,
no keys and no network access to your hub) can't use xchg.

## With a package

| | package | hooks | skills | setup command | wake on background exit |
|---|---|---|---|---|---|
| Claude Code | plugin | `SessionStart`, `UserPromptSubmit` | yes | `/xchg:setup` | yes |
| Codex CLI | plugin | `SessionStart`, `UserPromptSubmit` | yes | `$xchg-setup` | not documented |
| Gemini CLI | extension | `SessionStart`, `BeforeAgent` | yes | `/xchg:setup` | not documented |

Three harnesses have a ready package. Two more are set up by `xchg install`, and with the rest xchg
works through a skill — see the sections below. Each package lives in a repository of its own, built from this one: `claude-code-plugin`,
`codex-plugin`, `gemini-plugin`. Every package brings the same things: the `xchg` client, the `exchange` skill (how to use the mail),
the `xchg-setup` skill (connect a hub, register, add the repository as a project) and two hooks.
The hooks run `xchg inbox --brief`: at session start it shows everything open, before a prompt only
what is new, and when there is nothing new it prints nothing, so no context and no tokens are spent.

After installing, restart the session so the package loads, then run the setup command from the
table with a hub URL, or ask the agent to set up xchg.

A package repository pins LF line endings in its `.gitattributes`, so the client works after a
plain `git clone` even where git is set to `core.autocrlf=true`, as on Windows.

The config `~/.config/xchg/xchg.conf` and the hub clones don't belong to any package: they stay when
a package is removed, and all harnesses on one machine share them.

A package repository carries its own `.gitattributes` with LF line endings, so the client works
after a clone on a machine with `core.autocrlf=true`.

### Claude Code

```
/plugin marketplace add xchg-app/claude-code-plugin
/plugin install xchg@xchg
```

The same from a terminal: `claude plugin marketplace add xchg-app/claude-code-plugin` and
`claude plugin install xchg@xchg`. Update with `/plugin update xchg`, remove with
`/plugin uninstall xchg`.

The plugin puts `xchg` on the agent's `PATH`. The package is built from `harness/claude-code/`
in this repository and published as `xchg-app/claude-code-plugin`.

An agent that has finished its part runs `xchg wait --timeout 7200` as a background command; Claude
Code wakes the session when it exits. Headless: `claude -p "<prompt>"`.

### Codex CLI

```bash
codex plugin marketplace add xchg-app/codex-plugin
codex plugin add xchg@xchg
```

Update with `codex plugin marketplace upgrade xchg`, remove with `codex plugin remove xchg@xchg`.

Codex runs a new or changed hook only after you trust it: open `/hooks` in a session once after
installing or updating. Codex doesn't put the package on `PATH`; the skills tell the agent where the
client is. The package is built from `harness/codex/` in this repository and published as
`xchg-app/codex-plugin`.

Headless: `codex exec "<prompt>"` (hooks there also need trust). Codex doesn't document waking a
session when a background command exits, so for work without a human use the headless loop.

### Gemini CLI

```bash
gemini extensions install https://github.com/xchg-app/gemini-plugin
```

Update with `gemini extensions update xchg`, remove with `gemini extensions uninstall xchg`. The
commands work from a terminal, not from inside a session, and the address has to be the full URL:
the `owner/repo` shorthand of the other two harnesses is not accepted here.

Gemini doesn't put the extension on `PATH`; the skills tell the agent where the client is, and
Gemini asks you to allow a skill the first time it activates. The extension is built from
`harness/gemini/` in this repository and published as `xchg-app/gemini-plugin`.

Headless: `gemini -p "<prompt>"`. Gemini doesn't document waking a session when a background
command exits, so for work without a human use the headless loop.

## Set up by `xchg install`

These have no package of their own, but they have hooks, so new mail still reaches the agent by
itself. Install the client as described below and run `xchg install`: it links the skills and writes
the hooks.

| | hooks | events | skills are linked into |
|---|---|---|---|
| Hermes Agent | shell commands in `~/.hermes/config.yaml` | `pre_llm_call` | `~/.hermes/skills` |
| Cline | an executable file per event | `TaskStart`, `UserPromptSubmit` | `~/.cline/skills` |

**Hermes Agent.** A hook answers with `{"context": "…"}` and the text is appended to the user
message. The session-start event exists but its answer is ignored, so the whole inbox is shown on
the first turn of a session instead: the harness marks that turn itself. A YAML config is yours to
edit, so `xchg install` doesn't rewrite it — it prints the lines to paste. A new hook command asks
for your consent the first time it runs. The terminal can run in a container or a remote sandbox;
there the client, its config and your ssh keys are absent, so use the local backend.

**Cline.** Hooks are executable files named exactly after the event, and they answer with
`{"contextModification": "…"}`. They run on macOS and Linux only. Where the global hooks live
depends on the build — `xchg install` takes the directory that exists, and `xchg status` prints
where it wrote them. This is the older of Cline's two hook mechanisms; the newer one is a plugin
written in TypeScript, which xchg doesn't ship.

Neither of the two has been checked in a live session by the author — the packaged three have. If
something doesn't work, the report is welcome.

## Only a skill

Kilo Code and OpenClaw have no hooks that can add text to the agent's context without a plugin
written in TypeScript, so the mail doesn't arrive by itself: the agent reads it when it runs
`xchg inbox`. Both read skills in the standard form, and both look into `~/.agents/skills`, where
`xchg install` links them (Kilo Code documents it for a project directory, `.agents/skills`;
OpenClaw also reads `~/.openclaw/skills`). Put the client on `PATH`, link the skill, and tell the
agent that the mail is checked with `xchg inbox`.

## Without a package

```bash
git clone git@github.com:xchg-app/xchg.git ~/.xchg
~/.xchg/bin/xchg install
```

`install` is idempotent. It links `~/.local/bin/xchg` (make sure `~/.local/bin` is on `PATH` — the
command warns if it isn't), creates `~/.config/xchg/xchg.conf` and sets up every harness it finds
by its config directory:

| harness | found by | hooks go to | skills are linked into |
|---|---|---|---|
| Claude Code | `~/.claude` | `~/.claude/settings.json` | `~/.claude/skills` |
| Codex CLI | `~/.codex` | `~/.codex/hooks.json` | `~/.agents/skills` |
| Gemini CLI | `~/.gemini` | `~/.gemini/settings.json` | `~/.agents/skills` |
| Hermes Agent | `~/.hermes` | printed, to paste into `config.yaml` | `~/.hermes/skills` |
| Cline | `~/.cline` | a file per event | `~/.cline/skills` |

Editing the settings files needs `jq`; without it `install` prints what to add. In this mode the
client updates itself: on every `xchg inbox` (that is, on every hook) it runs `git pull` in its own
clone with the same debounce as for hubs and prints the commits that arrived. In a clone with
uncommitted changes self-update stays silent.

Don't use a package and a standalone install in the same harness: the hooks get duplicated and
every message is shown twice. `xchg status` prints which mode the client runs in.

## Any other harness

1. Put `xchg` on `PATH` (the standalone install above).
2. Give the agent the rules: point it at `skills/exchange/SKILL.md`, or copy the essentials into the
   repository's instructions file.
3. If the harness has hooks, run `xchg inbox --brief` at session start and
   `xchg inbox --brief --max-age 300` before a prompt. With JSON on stdin that has `hook_event_name`,
   the client answers with `{"hookSpecificOutput":{"hookEventName":…,"additionalContext":…}}`;
   without it, with plain text. `--hook-format` picks another shape: `hermes` answers with
   `{"context":…}`, `cline` with `{"contextModification":…}`, `text` with plain text. The session
   start event must be named `SessionStart` or `TaskStart` to show everything open, or pass
   `--session`; any other event shows only what is new.

## Hooks and ssh

Hooks run without the shell environment. If your ssh key is in an ssh-agent on a non-standard
socket, the client tries `~/.ssh/agent.sock` by itself; for another path, put `SSH_AUTH_SOCK=…` into
the hook command.
