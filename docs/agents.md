# Agents and projects

*Русская версия: [ru/agents.md](ru/agents.md).*

## Agent = person × project

An agent is a coding agent session in a specific repository, run by a specific person. It has no separate
name: its address is made of the project and the person, so `@api:alice` and `alice:@api` are one
and the same mailbox.

The current session's project is the name of the main repository (for a worktree, the primary
repository is used, not the working copy). If the clone is named differently from the project in
the hub, the repository says so itself:

```bash
git config xchg.project api
```

A project name is only `[a-z0-9._-]`. If the repository is named otherwise (for example,
`TRENDS-frontend`), `xchg projects add` without a name suggests a normalized one, and
`xchg projects add trends-frontend` in that repository adds the project and writes `xchg.project`
by itself.

`xchg agent` prints this session's addresses — one per hub where such a project exists:

```console
$ cd ~/repos/api && xchg agent
work:@api:alice
me:@api:alice
```

All sessions, worktrees and machines over one repository are one recipient: a message is picked up
by whichever session starts first.

## A repository becomes a project

Until a repository is added as a project, the agent in it can't be addressed:

```console
$ cd ~/repos/api && xchg projects add
project added: work:projects/api (card: projects/api/README.md)
```

The command does three things: adds the project with a card (if it doesn't exist yet), puts you in
the hub's contact book and creates your agent's passport. If someone else has already added the
project, `projects add` just joins you to it.

The project card and the agent passport are the only files with knowledge in a hub, and they are
narrow on purpose: pointers, not state.

```markdown
# api                                    ← projects/api/README.md

Repository: git@github.com:team/api.git
Owner: bob
```

```markdown
# alice on project api                   ← projects/api/alice/README.md

Person: alice
Repository: git@example.com:team/api.git
Repository docs: AGENTS.md
```

The repository and the documentation entry point come from the current clone (`origin` and the first
one found of `.claude-docs/index.md`, `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `README.md`), so the passport doesn't need to be
filled in by hand.

`xchg projects` shows the hubs' projects, marks the one you are in and prints the repository line
from the card. `xchg who` shows people and the projects where they have agents.

## What a session sees

`xchg inbox` shows **this** session's addresses:

| | |
|---|---|
| `all` | messages to the whole hub |
| `me` | `people/<you>` — to you as a person |
| `@<project>` | your project's queue |
| `@<project>:me` | to your agent personally |

Messages addressed to you in other projects collapse into a counter line: they wait for a session
in that repository. `xchg inbox --all` shows them without switching. A message in a shared address
that doesn't concern this agent can be muted for it: `xchg mute <file>`.

A message to a shared address (`all`, `me`) must be read by each of your agents: the "read" mark is
kept separately for each of them, so the agent in `api` doesn't "eat" it for the agent in `web`.

The exception is a reply (`re:`) that came to you as a person: it goes to the agent that has seen the
original message (sent it, or got it in its inbox). For your other agents such a reply lands in the counter
of other projects, and `xchg inbox --all` shows it. If no agent on this machine has seen the original, the
reply is shown to each of them.

A reply comes to you as a person when the original was sent from a repository that is not a project in
that hub: its signature carries no project then. The client warns about it on sending; `xchg projects add`
makes the agent addressable, and replies go straight to it.

## Your own agents between themselves

Create a hub without a remote — it lives locally and is visible to no one but you:

```console
$ xchg hub init me
$ cd ~/repos/api && xchg projects add --hub me
$ cd ~/repos/web && xchg projects add --hub me

$ cd ~/repos/api && xchg send me:@web:alice handoff <<'MSG'
# Continue the migration
The schema is in api/docs/db.md; what's left is moving the indexes.
MSG
sent: me:projects/web/alice/20260909-111506_alice-api_handoff.md
```

The next session in `~/repos/web` sees this message in a hook. `from` is `alice/api`, so
`xchg reply` answers exactly that agent. When you have more machines, `xchg hub remote me <url>`
moves the hub to a server, and the same conversation goes between machines.
