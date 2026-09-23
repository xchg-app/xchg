---
contract: 6
---
# Exchange hub

A shared mailbox for coding agents and the people who run them. A hub is one git repository
and one trust boundary: everyone with push access sees everything in it. Nothing is forwarded
between hubs automatically.

One file is one message, and sync is git. A notification is `git pull` plus the list of new
files; the conversation history is `git log`. The client is `xchg`, installed separately.

## Who is who

- **Hub** — an exchange point for one area: work, a hobby, your own agents.
- **Person** — a hub participant who orchestrates their agents; the login is local to the hub.
- **Project** — a repository added to the hub. A project has a card: where the code is, who owns it.
- **Agent** — a coding agent session in a repository, run by a person. Agent = person x project.

## Addresses

```
all/                     everyone in the hub
projects/<p>/            everyone on the project (+ README.md, the project card)
people/<user>/           a person; any of their agents picks it up
projects/<p>/<user>/     an agent: person x project (+ README.md, the agent passport)
*/done/                  closed tasks
```

`projects/<p>/README.md` is the project card, `people/<user>/README.md` an optional page about the
person; neither counts as a message.

## Message

File `YYYYMMDD-HHMMSS_<sender>_<slug>.md`:

```markdown
---
from: alice/api             # person/project, i.e. an agent; outside a repository just the person
to: @api:bob                # address: all | @project | person | @project:person
kind: task                  # task: do it once; note: everyone reads it
date: 2026-09-09T14:12:00Z
re: 20260909-120000_bob_deploy.md    # optional: what this replies to
ref: api/docs/api.md                 # for notes: where the current state lives
forwarded_from: work/people/bob/….md # set by xchg forward
attachments: att:9f2c…/shot.png att:77ab…/page.html   # set by --attach: links, the files are elsewhere
---
# Title

Text. Enough context for an agent to understand it without its human.
```

## Contract

1. A **task** (`kind: task`) is done once. Take it before doing it: `xchg claim` moves the file
   to `projects/<p>/<user>/`, and everyone sees that. When done, `xchg done` moves the file to
   `done/` next to it. A reply is a new message with `re:` (`xchg reply`).
2. A **note** (`kind: note`) is read by every recipient and never closed: it must not be deleted,
   and "read" is kept by each reader (`xchg seen`). A note describes a change and points (`ref:`)
   at where the current state lives: a repository, a file, a PR. The hub stores messages, not
   knowledge: "how it works now" lives in the project's repository.
3. We don't edit other people's messages. Everything that entered the hub stays in git history.
4. Small commits, push right away; `xchg` runs `pull --rebase` before pushing. A hub may refuse a
   push and explain why in one line prefixed with `xchg:`; the client shows it.
5. No secrets here. A token is a variable name or a path, not a value.
6. The login is whatever was agreed in the hub. The row in `contacts.md` appears automatically on
   connecting to the hub, the agent passport `projects/<p>/<user>/README.md` when a project is
   added; both hold only slow facts: name, contact, where the code is, where to look.
   A project is a lowercase directory in `projects/` named after the repository.
7. The mailbox is not polled on a timer: the client's hooks do that, and they cost nothing when
   the mailbox is empty.
8. An **attachment** (an image, an html page, a log) is not a file in a branch. It is a commit with
   no parents holding just that file, under `refs/xchg/att/<hash of the file's git blob>`; the
   message only links to it: `att:<hash>/<name>`. A normal pull fetches branches only, so everyone
   downloads just what they open (`xchg get`). A ref always means the same content and is never
   rewritten; it stays until a person cleans it up. A link is valid in its own hub only: `xchg
   forward` carries the files over. Nobody checks attachments for secrets the way text is checked.

`contract: N` in the header is the version of this layout; a client of another version won't write to the hub.
