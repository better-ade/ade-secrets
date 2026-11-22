# 0001: contract v2: per-hub keys, `has`, `run`, and an explicit opt-in

Status: proposed (2026-11-22). Contract: `docs/contract-v2.md`. Replaces nothing: v1 (`docs/contract.md`) stays.

## Context

v1 lets a hub's `bin/secret` hand every call to ade-secrets and promises that a value goes only to Claude Code's key
helper. The review of the hub's side (ade-brain story H2) found that the two do not fit:

- The hub reads values itself in six places: the provider and Anthropic key checks before a launch, `gemini_auth read`,
  `bin/gemini-run` (the Gemini CLI takes its key only from its environment), and three in `bin/chat` (the Telegram
  token). Under v1 all six are refused.
- Presence checks (`list --names`) are refused without a terminal and in agent sessions, so jobs, hooks and the
  orchestrator cannot tell "no key" from "cannot ask"; one path hid the refusal and ran on the Claude login instead.
- One entry per name for the machine: a person with one hub per customer overwrites one customer's key with another's.
- No store is chosen at first use; on Linux the age store can never serve the helper.
- Delegation switches on when `ade-secrets` is on `PATH`, and the store decision does not reach the helper line.
- ade-cli needs release files with sha256 to install the tool, and a names-only list of keys due for rotation.

## Decision

1. **`run <name> -- <program> [args]`** hands a value to one recorded program, by one environment variable or on
   stdin, for entries marked `--run <program> --env VAR|--stdin` at `set`. Callers: a terminal or a service; never an
   agent session (v1's variables and claude ancestry). Reason: the Gemini CLI and the bot need their keys and are not
   Claude Code; refusing agent sessions keeps the "never an agent session" rule for every caller we can detect.
2. **`has <name>`** answers everywhere, exit 0 or 1, nothing printed. Reason: a known name, one bit, and names are
   already readable in `meta`. The hub's rule: 0 and 1 are answers; anything else stops with the real reason.
3. **The check before a launch is presence only.** Reason: a pre-read is a second read path for the same value; a
   present but unreadable key fails at launch, in the helper or in `run`, with the store's reason. Conditional on C1.
4. **Per-hub entries by name: `<HUB_NAME>.<key>`.** Reason: no new field, no new flag on `get`; `HUB_NAME` is already
   the hub's identity on the machine (state folder, Keychain service, launchd label) and moves with `hub.conf`.
   `set` asks before a replace; `list` and the vault show the scope; v1 entries are left alone.
5. **The opt-in is a record per hub**, `<state dir>/secrets`, written by `bin/keys store` in a person's terminal,
   holding the store, scope, the tool's real path and the hub's real path. Reason: outside every checkout, read not
   sourced, and it removes `PATH` from every decision after the choice. The age store is never offered to a hub.
6. **`--helper` only for keys Claude Code runs on** (Anthropic and provider keys); the Gemini key and the bot token get
   `--run`. Reason: a helper entry is readable by Claude Code and all it runs; the others need not be.
7. **The helper line is `'<path>' get '<scope>.<key>'`**, from `bin/secret --helper-line`, written with each session's
   settings. Reason: the store decision travels in the line itself (review finding 3).
8. **Release files** `ade-secrets` and `vault.sh` with sha256 in `release.json`; the version is in the script;
   `list --due` prints names only. Reason: what ade-cli's install and reminder need, and nothing more.

## Alternatives considered

- **A daemon or agent socket that hands out values.** Not chosen: a long-lived process holding keys, a socket any
  process of the user can reach, and no better test of who asks than v1's signals.
- **`run` callable from agent sessions, protected by the allow-list alone.** Not chosen: the allow-list pins the
  program, not its arguments or content; it would turn an accident guard into an open door for any instruction.
- **`run` with any child command.** Not chosen: `ade-secrets run telegram -- env` would print the token.
- **A `check <name>` that reads and validates shape.** Not chosen: a read verb that agent sessions could call, for
  little gain over presence plus a clear failure at launch.
- **A `--scope` field and flag.** Not chosen: a new column, a flag on every command and in the helper line; a name
  prefix gives the same separation with no new path through `get`.
- **The opt-in in `hub.conf`, or `HUB_SECRETS` in the environment.** Not chosen: `hub.conf` is a tracked file that
  any checkout or pull can change; the environment does not reach the key helper (finding 3).
- **The age store for hub keys, asking the passphrase at `run`.** Not chosen: a service has no one to ask.

## Consequences

- The hub stops reading values; `bin/secret <name>` is refused under delegation.
- Gemini by key starts only from a terminal or a service; a delegated Gemini run from an agent session needs the
  Google sign-in, and the hub says so before it picks that candidate.
- Telegram sends from hooks and agent sessions are queued for the forwarder, never sent directly.
- A moved or copied hub must be re-recorded (`bin/keys store`); the Telegram token is bound to `<hub>/bin/chat` and is
  entered again.
- Each person re-enters each hub key once (`bin/keys set <tool>`); nothing is copied from v1 entries.
- Honest limit: nothing here holds against an agent that has the shell and means to read a key. The gain over the
  hub's own store is that no plain call prints a value, no hub process holds one, and customers' keys are apart.

## Open points for the owner (each with the default applied unless the owner says otherwise)

| # | Point | Default |
|---|---|---|
| 1 | Gemini by API key under ade-secrets: its key is readable by that Gemini session and what it runs | allowed, through `run`, like a helper key |
| 2 | The bot token ends with the channel plugin under the orchestrator's session | accepted: it is how the channel works |
| 3 | Sends from hooks and agent sessions | queued for the forwarder; "kept" said plainly |
| 4 | No record while ade-secrets is installed | the hub stops and asks; never guesses builtin |
| 5 | A moved hub's bot token | entered again; no verb to rebind a program |
| 6 | v1 entries | not migrated; no move verb |
| 7 | The age store for `run` | refused (exit 5), as for `get` |
| 8 | The version that carries contract v2 | 0.4.0 |
| 9 | Rotation age for `list --due` | `ADE_SECRETS_ROTATE_DAYS`, default 90, as in the vault |

## Proposed stories (not written here)

| Order | Id | Repo | One line | Risk | Depends on |
|---|---|---|---|---|---|
| 1 | S3 | ade-secrets | scopes in names, `list` and the vault; `has`; ask before a replace; `list --due`; the version in the script | high | none |
| 2 | S4 | ade-secrets | `run` and the `--run` mark (env or stdin); `guard_run`; the Gemini CLI as an agent context; the v2 block under test; residual risk and owner check | high | S3, and C2, C4, C6-C8 confirmed |
| 3 | S5 | ade-secrets | release 0.4.0 with `ade-secrets` and `vault.sh` and their sha256 in `release.json` | medium | S3, S4, C10 |
| 4 | H4 | ade-brain | adopt v2: the record and `bin/keys store`, the v2 block, helper lines from `--helper-line`, scoped names and marks, presence-only checks, Gemini and Telegram through `--run`, queued sends, pinned fixtures | high | S5, and C1, C3, C5 confirmed |
| 5 | A15 | ade-cli | install ade-secrets from the release files with the sha256 check; store hub keys through `bin/keys store` and `bin/keys set` with the terminal attached; a weekly reminder from `list --due` | high | S5, H4 |

H4 is the largest. If its story passes about ten criteria, split it: H4 (the record, the block, the Claude Code paths)
and H5 (Gemini and Telegram through `--run`).
