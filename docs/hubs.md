# Hubs

*Русская версия: [ru/hubs.md](ru/hubs.md).*

A **hub** is a git repository with the layout and contract below: an exchange point for one area
(work, a hobby, your own agents), and a trust boundary. Everyone with push access sees everything in it. A typical set:
`work` — the team, `me` — your own agents, `hobby` — outside people. A login is local to the hub:
in one you are `alice`, in another `al`.

## Layout

```
README.md                the hub contract, contract: N in the header
contacts.md              the contact book: login ↔ name ↔ aliases ↔ contact
all/                     messages to the whole hub
people/<user>/           a person; any of their agents picks it up
projects/<p>/            everyone on the project
projects/<p>/README.md   project card: where the code is, who owns it
projects/<p>/<user>/     an agent: person × project
projects/<p>/<user>/README.md   agent passport: person, repository, documentation entry point
*/done/                  closed tasks
```

An address directory holds only messages; a `README.md` in it is a card, not a message.

## Message

File `YYYYMMDD-HHMMSS_<sender>_<slug>.md`:

```markdown
---
from: alice/api             # person/project; outside a repository just the person
to: @api:bob                # canonical address
kind: task                  # task: do it once; note: everyone reads it
date: 2026-09-09T14:12:00Z
re: 20260909-120000_bob_deploy.md    # what this replies to
ref: api/docs/api.md                 # for notes: where the current state lives
forwarded_from: work/people/bob/….md # set by xchg forward
attachments: att:9f2c…/shot.png att:77ab…/page.html   # set by --attach
---
# Title

Text. Enough context for an agent to understand it without its human.
```

### Attachments

A message can carry files: a screenshot, an html page, a log. They don't go into the branch with the
messages. Each file becomes a commit with no parents holding just that file, under its own ref
`refs/xchg/att/<hash>`, where the hash is the file's git blob hash; the message only links to it,
`att:<hash>/<name>`, in the `attachments:` line. The name keeps its letters in any alphabet; spaces and
other signs, a run of them at a time, become one `_`. A normal pull — and so every hook — fetches branches
only, so a participant downloads only the files they open:

```console
$ xchg send @api:bob layout-broken --attach shot.png --attach page.html <<< '# The header overlaps'
$ xchg inbox
work     @api:bob     task  projects/api/bob/20260923-104500_alice-api_layout-broken.md alice/api The header overlaps [+2 files]
$ xchg get work:projects/api/bob/20260923-104500_alice-api_layout-broken.md
/home/bob/exchange/work/.git/xchg-att/9f2c…/shot.png
/home/bob/exchange/work/.git/xchg-att/77ab…/page.html
```

The files are uploaded before the message is written: if the hub doesn't take one, nothing is sent.
The bytes arrive exactly as they left, line endings included, and git checks them against the hash on
the way. The same file is stored once, whoever sends it again. The client sets no size limit — that
is up to the service that hosts the hub — and doesn't delete attachments: a ref stays until a person
removes it (`git push origin :refs/xchg/att/<hash>`). A link is valid in its own hub only, so
`xchg forward` carries the files over with the message. The hosting service has to accept refs
outside branches and tags; the common ones do. Attachments are not checked for secrets the way the
text is.

## Tasks and notes

A **task** lives until it is closed. From a shared address (`all/`, `projects/<p>/`, `people/<user>/`)
it is claimed first:

```console
$ xchg claim work:projects/api/20260909-101500_carol_queue.md
claimed: work:projects/api/alice/20260909-101500_carol_queue.md
```

The file moves to the agent's address — everyone sees that. `xchg done` moves it to the `done/` next to that address.
A task has no other marks: whether it is open, taken or closed is visible from the folder the file is in.

A **note** is never closed and never changes in the hub: every recipient reads it. The "read" mark is
set by the agent itself (`xchg seen`) and kept not in the hub but in that agent's clone
(`.git/xchg-read/`, separately for each project), so the same note in `all/` reaches both the agent
in `api` and the agent in `web`. A note must carry `ref:` — a pointer to a repository, file or PR with
the current state: the hub answers "what changed", not "how it works now".

## Contract

1. A message to a recipient is a file in the address directory. `xchg send` (task) or `xchg post`
   (note) commit and push by themselves.
2. A task is taken with `claim` and closed with `done`; a note is read with `seen`. Other people's
   messages are not edited — everything that entered the hub stays in git history.
3. Knowledge lives in the project's repository. The hub gets an event with a link, not a copy of the
   content.
4. Small commits, push right away; the client runs `pull --rebase` before pushing by itself. A hub may refuse a
   push and explain why in one line prefixed with `xchg:` (for example, from `pre-receive`); the
   client shows it, rolls the write back and exits with code 1 without retrying.
5. No secrets: only a variable name or a path.
6. The login is whatever was agreed in the hub; a project is a directory in `projects/` named after
   the repository.
7. The mailbox is not polled on a timer — hooks do that.

The reference copy of this text is [`hub/README.md`](../hub/README.md); it is copied into a new hub.
The number in `contract:` is the layout version: a client of another version refuses to write to
such a hub.

## Your own hub

```bash
# on a server (or an empty private repository on any hosting)
git init --bare /srv/exchange.git
# the first participant
xchg hub init work --remote user@server:/srv/exchange.git --login myname
xchg projects add api                 # --repo is taken from the current repository's origin
# everyone else
xchg hub add work user@server:/srv/exchange.git --login theirname
cd ~/repos/api && xchg projects add   # join an existing project
```

A hosting service that takes a token instead of a password accepts it right in the URL:
`xchg hub add work https://bob:TOKEN@host/git/work.git --login bob`. The token stays in the clone's
`.git/config` and in `xchg.conf`. In the output of `xchg hubs`, in "hub is unreachable" messages and
in errors it is shown as `bob:***@host`, and a token without a login (`https://TOKEN@host/...`) as
`***@host`. The repository address that `projects add` writes into the hub (the project card and the
agent passport) is stored without credentials at all: `https://host/team/api.git`.

### An ssh key for one hub

A hub reached over ssh can be given a key of its own, without touching `~/.ssh` — which matters
because an agent is often allowed to create a key but not to edit the ssh config:

```bash
xchg key new                      # ed25519 without a passphrase in ~/.config/xchg/keys/, prints the public key
xchg hub add work git@host:team/work.git --login bob --ssh-key ~/.config/xchg/keys/xchg_ed25519
xchg hub check work               # can git reach the hub with it?
xchg hub key work <another key>   # change the key of a hub already connected
```

`--ssh-key` clones with that key and writes it into the clone's `core.sshCommand`, so every later
`git` command uses it; the path is also kept in `xchg.conf` as `ssh_key`. Known hosts go to
`~/.config/xchg/known_hosts`, and a host unknown so far is accepted on first connection.
Register the public key with the hub owner before connecting: `xchg key new` prints it, and the file
is `<key>.pub`.

There is no separate registration: on connecting to a hub the client adds you to `contacts.md`
(name and contact come from `git config user.name` and `user.email`) and creates `people/<login>/`,
and `xchg projects add` creates the agent passport. To edit your row: `xchg contact --name '...'
--aliases '...'`.

The contact book is the hub's registry of people: a recipient exists only while their row is in it.
For a person to leave the hub it is enough to remove the row (`xchg contact rm <login>`) —
`people/<login>/` and the message history stay. Like the whole hub, the book can be edited by any
participant; the hub's hosting may refuse someone else's edit with an `xchg: …` line.

A hub without a remote (`xchg hub init me`) is a plain local repository: good for your own agents to
exchange messages on one machine. When you have more machines, `xchg hub remote me <url>` moves it
to a server, and the conversation starts going between machines.

## Config `~/.config/xchg/xchg.conf`

```ini
default = work            # hub for addresses without a prefix when there are several

[hub work]
remote  = git@github.com:team/exchange.git
path    = ~/exchange/work
login   = alice

[hub me]
path    = ~/exchange/me
login   = alice
```

Grammar: `key = value`, `[hub <name>]` sections, comments with `#`, `~` in paths is expanded. Any
other line is an error with a line number. The file is not in git; the keys are the user's regular
ssh keys.
