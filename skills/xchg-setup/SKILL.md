---
name: xchg-setup
description: Set up xchg for this user and repository — connect a hub (or create one), check the contact book row, add the current repository as a project. Use when the user asks to set up, install or configure xchg, or gives a hub URL to connect to.
---

# xchg setup

The user may have given a hub URL, asked for a new hub of their own ("own", "new", in any language),
or said nothing about the hub.

Do the setup yourself; ask only what can't be learned from the system. Every step goes through
`xchg`. If `xchg` isn't on `PATH`, run the client by its path: it is `bin/xchg` two levels above this
skill's directory, and the documentation is in `docs/` next to `bin/`.

1. **What already exists.** `xchg status`. If hubs are already connected, show them and go to step 4.

2. **Hub.** Look at what the user gave:
   - looks like a git URL or `user@host:path` → `xchg hub add work <url>`;
   - a word like "own" or "new" (in any language) → ask whether there is an empty bare repository
     for the hub. If there is, `xchg hub init work --remote <url>`; if not, `xchg hub init me`
     (a local hub without a server, good for your own agents to exchange messages between
     repositories);
   - nothing → ask the user which hub to connect to, and offer both options.

   The login in the hub defaults to `$USER`. If it is different in the hub, add `--login <login>`.
   Ask about it only when connecting to someone else's hub and the login isn't obvious.

3. **Check registration.** `xchg who` — your person should appear in the contact book with the
   name and contact from `git config`. If the name is empty, suggest
   `xchg contact --name '...' --aliases '...'`.

4. **Project.** If the current directory is a git repository, run `xchg projects add`
   (it adds the project and the agent passport; if the project already exists, it just joins it).
   If the directory isn't a repository, say that a project is added from a repository, and skip
   the step.

5. **Check.** `xchg agent` and `xchg inbox`. Show the user their agent's address and explain in
   two lines: `xchg send <address> <slug>` is a task, `xchg post <address> <slug>` is a message,
   and incoming messages arrive by themselves through hooks.

Don't commit anything to the working repository and don't edit the agent's settings files: the
installed package provides the hooks, and `xchg install` sets them up for a standalone install.
