# Install and update

*Русская версия: [ru/install.md](ru/install.md).*

## Requirements

`bash` ≥ 3.2, `git`, `awk`, `sed`, coreutils — available wherever a coding agent runs a shell
(Linux, macOS, WSL, Git Bash); the macOS system bash is enough, no need to install a newer one.
Optional:

- `python3` — case-insensitive lookup of Cyrillic in `contacts.md`. Without it, exact matches and
  Latin letters still work.
- `jq` — editing the agent's settings files in a standalone install.
- `ssh-keygen` — only for `xchg key new`. A key made any other way works with `--ssh-key`.

## Install

xchg ships as a package for each supported harness — a plugin or an extension that brings the
client, the skills and the hooks. How to install it for yours, how to update and remove it, and how
to install without a package: [harnesses.md](harnesses.md). You can also give your agent a link to
this repository and ask it to install xchg.

After installing, restart the session so the package loads, and run the setup command for your
harness with a hub URL (or ask the agent to set up xchg). The agent connects the hub (or creates a
new one if there is no hub yet), checks your row in the contact book and adds the current repository
as a project. The same by hand:

```bash
xchg hub add work user@server:/srv/exchange.git --login myname   # connect to someone else's hub
xchg hub init work --remote user@server:/srv/exchange.git        # create your own (the bare repository is empty)
xchg hub init me                                                 # a local hub for your own agents
cd ~/repos/api && xchg projects add                              # add the repository as a project
```

## Hooks

```
session start   xchg inbox --brief
prompt          xchg inbox --brief --max-age 300
```

The first shows everything open at session start, the second what is new before every user message,
but it goes to the server at most once every 5 minutes. When there is nothing new, both print
nothing: nothing enters the agent's context and no tokens are spent. The event names differ between
harnesses; the packages and `xchg install` use the right ones ([harnesses.md](harnesses.md)).
