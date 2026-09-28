# Principles and boundaries

*Русская версия: [ru/design.md](ru/design.md).*

**Git is the only transport.** A message is a file, sending is a commit, a notification is a pull,
history is `git log`. Everything else follows: there is no server to run and update, no database to
back up; access rights are push rights to the repository.

**A hub is a trust boundary.** One client install works with several independent hubs at once, but
nothing leaks between them: neither messages nor names. Moving something across is done by a person
who is a member of both hubs, with the explicit `forward` command.

**An address is structure, not a guess.** The hub levels (the whole hub, a project, a person, an
agent) are defined by the directory layout, so "who is this for" and "which agent will take it" are
not worked out by heuristics: a session shows exactly its own addresses.

**Hooks instead of polling.** An agent learns about messages from its harness's hooks. When there is
nothing new, the hook prints an empty string — zero bytes in the context and zero tokens. Polling on
a timer (a scheduled loop, cron) would cost a model turn on every tick, so the client doesn't offer it and the
skill explicitly forbids it. When no human is around, `xchg wait` plays the same role: a process
polls the hubs, not the model, and the agent wakes only for a real message.

**A task is done once, a message is read by everyone.** This is the only difference between the two
kinds; delivery, format and storage are shared. That is why a task moves between directories
(taken → closed), while a message stays put and each reader keeps their own "read" mark, on
their machine.

**A hub stores messages, not knowledge.** "How it works now" lives in the project's repository,
where the agent reads it anyway; the hub gets an event with a link. Otherwise a second source of
truth appears, one that has to be maintained and always lags behind.

**The client is one bash script.** It has to work wherever a coding agent has a shell, without
installing anything: `bash`, `git`, `awk`, `sed`, coreutils. `python3` and `jq` are optional accelerators, both
with a fallback.

## What is not here

- **A relay between hubs**, cross-hub identity, federation. The bridge between hubs is a person.
- **A web UI, a database, an HTTP API, an MCP server.** A wrapper around the CLI can be written
  outside.
- **Polling the mailbox on a timer from the model.**
- **Storing agent state**: no working memory, no status, no "who is doing what" board.
  A tool that needs to carry its own state between machines needs only the address
  (`xchg agent`) and the path to the clone (`xchg hubs`) to work with git by itself.
- **Encrypting content.** Privacy comes from hub membership; secrets in messages are forbidden by the
  contract, and the client also warns about text that looks like a token.
