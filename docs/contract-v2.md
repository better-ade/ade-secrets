# ade-secrets contract (v2)

How a hub's `bin/secret` and `bin/keys` use `ade-secrets` from version **0.4.0**, and what each caller can rely on.
v1 (`docs/contract.md`) stays as written: every v1 command still works the same way (see "Compatibility"). Decision
record: `docs/decisions/0001-contract-v2.md`. `tests/test_contract.sh` runs the v2 block below as written.

## What changes from v1

| v1 | v2 |
|---|---|
| One entry per name for the whole machine | Each hub's entries are named `<scope>.<name>`; the scope is the hub's `HUB_NAME` |
| A value goes only to Claude Code's key helper | Also to one recorded program, through `run`, for entries marked `--run` |
| Presence checks need a terminal | `has <name>` answers everywhere and prints nothing |
| The hub delegates when `ade-secrets` is on `PATH` | The hub delegates only when a person recorded that choice for that hub |
| `set` replaces an entry without asking | `set` asks before it replaces one |
| No names-only rotation list; no release files | `list --due`; the release publishes `ade-secrets` and `vault.sh` with sha256 |

## Commands

| Command | Who may call it | stdout | Exit |
|---|---|---|---|
| `ade-secrets set <name> [--clipboard] [--kind K] [--used-by U] [USE]` | a person's terminal | nothing | 0 stored, 1 not stored or not replaced |
| `ade-secrets has <name>` | anyone (terminal, service, agent session, key helper) | nothing | 0 present, 1 absent |
| `ade-secrets run <name> -- <program> [args...]` | a terminal or a service; never an agent session | nothing from ade-secrets | before the start: 1, 2, 3, 5; after: the program's |
| `ade-secrets get <name>` (or `helper <name>`) | Claude Code's key helper, entries marked `--helper` | the value and a newline | 0 |
| `ade-secrets list [--scope S]` | a person's terminal | a table, never a value | 0 |
| `ade-secrets list --names [--scope S]` | a person's terminal | one name per line | 0 |
| `ade-secrets list --due [--scope S]` | a person's terminal | one name per line: entries past the rotation age | 0 |
| `ade-secrets forget`, `copy`, `store`, `vault`, `lock`, `unlock`, `status` | a person's terminal | as in v1 | as in v1 |
| `ade-secrets --version` (or `version`) | anyone | one line, `X.Y.Z` | 0 |

`USE` is at most one of: `--helper` (Claude Code's key helper may `get` it), `--run <program> --env <VAR>` or
`--run <program> --stdin` (`run` may hand it to that program), `--plain` (no consumer; `--no-helper` means the same).
On an existing entry, a `set` without `USE` keeps the entry's mark.

Exit codes for every command: 0 ok, 1 failed (nothing on stdout), 2 usage, no store chosen, or an
`ADE_SECRETS_STORE` that differs from the recorded store, 3 refused (an agent context, an entry not marked for that
use, a program that is not the recorded one), 4 no clipboard, 5 the age store (locked, or `get` and `run`, which it
cannot serve). Messages go to stderr, start with `ade-secrets:`, and never contain a value. After `run` has started
the program, the exit is the program's own, so an exit 3 there can be either; a refusal by `run` is the only case
that prints an `ade-secrets:` line.

## Names and scopes

Names stay `[A-Za-z0-9][A-Za-z0-9._-]{0,63}`, and a name that differs from an existing one only in case is refused.
A **scope** is the text before the first `.` of a name; a name without a `.` has none (every v1 entry). A hub names
its entries `<scope>.<key>`, for example `acme-ops.anthropic-api-key`. The scope is the hub's `HUB_NAME`, which
`bin/init` writes into `hub.conf` as `^[a-z0-9][a-z0-9-]*$`; a scope is at most 40 characters, so every hub key name
fits in 64. Because `HUB_NAME` lives in `hub.conf`, the scope stays the same when the hub folder moves.

`list` shows `SCOPE NAME KIND USED-BY AGE USE`: `NAME` without the scope, `-` for no scope, and `USE` as `helper`,
`run env:VAR <program>`, `run stdin <program>` or `-` (the program last, in full, so a person can check it).
`--scope S` keeps only scope `S`; with `--names` or `--due` it prints the names without the `S.` prefix, otherwise
full names. The vault shows the same `SCOPE` column; its search matches the full name.

`meta` gains two tab-separated fields after v1's seven: 8 `run` (the program's real path, or empty) and 9 `deliver`
(`env:VAR`, `stdin`, or empty). A line with seven fields is a v1 line and has no run mark.

## `set`: asking before a replace

When the entry exists in the current store, `set` asks on the terminal, before the value prompt:
`replace acme-ops.anthropic-api-key (rotated 12d ago)? [y/N] `. Anything but `y` ends with exit 1 and
`kept acme-ops.anthropic-api-key unchanged`. A change of mark is a replace too: it asks, then takes a new value.
`--run <program>` must name an executable file by absolute path; the recorded value is its real path (symlinks
followed). `--env VAR` must match `^[A-Z][A-Z0-9_]{0,63}$` and must not be `PATH`, `HOME`, `SHELL`, `IFS`, `ENV`,
`PS4`, `SHELLOPTS`, `BASHOPTS`, `NODE_OPTIONS`, or start with `BASH`, `LD_` or `DYLD_` (exit 2). `--helper` and `--run`
together: exit 2. In the Keychain an entry marked `--helper` or `--run` trusts `/usr/bin/security` (no dialog, so a
service can read it); a `--plain` entry trusts none (`-T ""`), as in v1.

## `has`: presence without a value

`has <name>` exits 0 when the current store has the entry, 1 when it does not; it prints nothing on stdout. It runs
in every context: no terminal is needed and agent sessions are not refused. The reason: the caller already knows the
name, the answer is one bit, and every name is already readable by any process of the user in `~/.ade-secrets/meta`.
Only the start-up check (an exported function, `BASH_ENV` and the rest) can refuse it (exit 3). It reads `meta`
and then checks that the store holds the entry without reading a value: Keychain attributes only
(`security find-generic-password -s ade-secrets -a <name>`, no `-w`), the pass file
`${PASSWORD_STORE_DIR:-~/.password-store}/ade-secrets/<name>.gpg`, or the age file. When `meta` lists the entry but
the store has no item, `has` exits 1 and says `meta lists <name> but the <store> store has no item; set it again`.
No store chosen: exit 2.

**The hub's rule:** 0 and 1 are answers. Any other exit stops what the hub was doing, with ade-secrets' own stderr
line shown (never `2>/dev/null`) and the exit passed on. Never "missing", never the next candidate, never the login.

## `run`: a value for one program that is not Claude Code

```
ade-secrets run <name> -- <program> [args...]
```

`run` starts `<program>` with the value, then gets out of the way: it `exec`s the program, so the program's parent is
`run`'s parent. The value never appears on a command line, on stdout, in a log or in a file.

- **Delivery** is the one recorded at `set`. `env:VAR`: `VAR` is set (replacing any value it had) in the
  environment of that one process only, by `export` just before the `exec`. `stdin`: the program's stdin is the value,
  a newline, then `run`'s own stdin, through a pipe.
- **The program** is resolved the same way as at `set` (an absolute path, or a name looked up on `PATH`, then its real
  path) and must equal the recorded path, or `run` exits 3: `only <recorded> may receive <name>`. The arguments are
  free.
- **Who may call it** (`guard_run`): refused (3) when any of v1's session variables is set (`CLAUDE_CODE_ENTRYPOINT`
  included, so the key helper cannot call it), when a claude process is anywhere among its ancestors, or when an
  agent CLI the hub runs is detected (Gemini, see "To confirm" C4). No terminal is required, so a person's terminal
  and a service started by the person's own login session (a launchd LaunchAgent, a systemd user unit, a scheduled
  job) pass. These are v1's signals; nothing new is trusted.
- Entry not marked `--run`: 3 (`<name> is not marked for run; in your terminal: ade-secrets set <name> --run ...`).
  The age store: 5 (it asks for a passphrase on every read). Store unreadable (a locked keychain, gpg-agent with no
  cached passphrase and no terminal): 1, with the store's reason.

**What `run` cannot do.** It cannot keep a value from an agent that has the shell. Such an agent can hide from the
guard (unset the variables, leave the process tree, open a new terminal window, write a LaunchAgent), run the
recorded program with arguments of its choosing, or edit the program when it is a file the user can write (a hub
script, an npm-installed CLI). The program allow-list and the guard are an **accident guard, like `get`'s**: they stop
`ade-secrets run telegram -- env`, a plain `bin/secret <name>`, and use by instruction, not a deliberate agent.

What is still gained over the hub's own store, where `bin/secret <name>` prints any hub key to an agent's shell:

| | Hub's own store (today) | v2 |
|---|---|---|
| An agent's plain `bin/secret <name>` | prints the value | refused (exit 3) |
| Who receives a value | whoever asked | Claude Code's key helper, or the one recorded program |
| Values in the hub's own shells and files | read in six places | none; only `bin/chat`'s 0600 `.env` for the plugin (below) |
| Each customer's hub keeps its own keys | per Keychain service | per scope |
| Against a deliberate agent with the shell | nothing | nothing |

## Choosing the store, and the hub's opt-in

ade-secrets keeps one recorded store for the machine, as in v1 (`ADE_SECRETS_STORE` for the first set, then only
`ade-secrets store <name>`). A hub never sets `ADE_SECRETS_STORE`.

**The hub's record** is `<state dir>/secrets` (`~/.agent-hub/<HUB_NAME>/secrets`): outside the hub repo and every
checkout, mode 600, written only by `bin/keys store` in a person's own terminal (the hub refuses it with a session
variable set, a claude ancestor, or no terminal on stdin; `ade key store` runs it with the terminal attached). It is
read line by line, never sourced:

```
store=ade-secrets
scope=acme-ops
path=/Users/<user>/.local/bin/ade-secrets
hub=/Users/<user>/hubs/acme-ops
```

`store=builtin` (with `hub=`) keeps the hub's own store. `path` is the tool's real path, so `PATH` never decides
anything after the choice. `hub` is the hub folder's real path: a record for another folder stops the hub (a copied or
moved hub must be re-recorded; the scope, and so the keys, stay). `bin/keys store ade-secrets`:

1. needs ade-secrets 0.4.0 or later (`--version`), and `HUB_NAME` in `hub.conf` matching `^[a-z0-9][a-z0-9-]{0,39}$`;
2. reads `ade-secrets store`; with none recorded it offers the Keychain on macOS and pass on Linux (only when `pass`
   is initialised), and runs `ade-secrets store <choice>`. **The age store is never offered**, and a recorded `age`
   store stops the opt-in: age cannot serve `get` or `run`, and every hub key is one Claude Code, the Gemini CLI or
   the bot runs on;
3. writes the record (a temporary file, then `mv`), and names each key to enter again with `bin/keys set <tool>`.

No record and ade-secrets on `PATH`: the hub stops every key call with exit 2 and
`this hub has not chosen its key store: run bin/keys store in your own terminal (ade-secrets or builtin)`.
No record and no ade-secrets: the hub's own store, as before. `HUB_SECRETS` in the environment is no longer read.

## The delegation block v2 (bin/secret)

A hub's `bin/secret` puts this right after the line that sources `bin/lib.sh` (it uses `hub_root` and `state_dir`).
The marker differs from v1's on purpose, so that tools written for v1 do not take a v2 hub for a v1 one.

```bash
# >>> ade-secrets v2 (docs/contract-v2.md in better-ade/ade-secrets)
# The hub's record decides, never PATH: <state dir>/secrets, written by bin/keys store in a person's own terminal.
ade_rec="$(state_dir)/secrets" ade_store="" ade_scope="" ade_bin="" ade_hub=""
if [ -e "$ade_rec" ] || [ -L "$ade_rec" ]; then
  { [ -f "$ade_rec" ] && [ ! -L "$ade_rec" ] && [ -O "$ade_rec" ]; } ||
    { echo "secret: $ade_rec is not a plain file of yours; refused (bin/keys store writes it)" >&2; exit 2; }
  while IFS='=' read -r ade_k ade_v; do
    case "$ade_k" in store) ade_store="$ade_v" ;; scope) ade_scope="$ade_v" ;; path) ade_bin="$ade_v" ;; hub) ade_hub="$ade_v" ;; esac
  done < "$ade_rec"
  [ "$ade_hub" = "$(cd "$(hub_root)" && pwd -P)" ] ||
    { echo "secret: $ade_rec was made for the hub at $ade_hub; if this hub moved, run bin/keys store in your own terminal" >&2; exit 2; }
elif command -v ade-secrets >/dev/null 2>&1; then
  ade_store=unchosen
fi
case "$ade_store" in
  ""|builtin) ;;
  unchosen) echo "secret: this hub has not chosen its key store: run bin/keys store in your own terminal (ade-secrets or builtin)" >&2; exit 2 ;;
  ade-secrets)
    [[ "$ade_scope" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || { echo "secret: $ade_rec has no valid scope; run bin/keys store in your own terminal" >&2; exit 2; }
    case "$ade_bin" in /*) ;; *) ade_bin="" ;; esac; case "$ade_bin" in *\'*) ade_bin="" ;; esac
    [ -n "$ade_bin" ] && [ -x "$ade_bin" ] || { echo "secret: ade-secrets is not where $ade_rec says; install it again, or run bin/keys store in your own terminal" >&2; exit 2; }
    ade_ver="$("$ade_bin" --version 2>/dev/null </dev/null)"
    case "$ade_ver" in 0.[4-9].*|0.[1-9][0-9]*|[1-9]*) ;; *) echo "secret: ade-secrets at $ade_bin is ${ade_ver:-of unknown version}; this hub needs 0.4.0 or later (contract v2)" >&2; exit 2 ;; esac
    ade_n="$ade_scope.${2:-}"
    case "${1:-}" in
      --set) [ -n "${2:-}" ] || exit 2; shift 2; exec "$ade_bin" set "$ade_n" --kind api-key --used-by "hub:$ade_scope" "$@" ;;
      --has) [ $# -eq 2 ] && [ -n "$2" ] || exit 2; exec "$ade_bin" has "$ade_n" ;;
      --forget) [ $# -eq 2 ] && [ -n "$2" ] || exit 2; exec "$ade_bin" forget "$ade_n" ;;
      --list) [ $# -eq 1 ] || exit 2; exec "$ade_bin" list --names --scope "$ade_scope" ;;
      --run) [ -n "${2:-}" ] && [ "${3:-}" = -- ] || exit 2; shift 2; exec "$ade_bin" run "$ade_n" "$@" ;;
      --helper-line) [ $# -eq 2 ] && [ -n "$2" ] || exit 2; printf "'%s' get '%s'\n" "$ade_bin" "$ade_n"; exit 0 ;;
      ""|-*) echo "usage: bin/secret --set <name> [use] | --has <name> | --forget <name> | --list | --run <name> -- <program> [args] | --helper-line <name>" >&2; exit 2 ;;
      *) echo "secret: this hub keeps its keys in ade-secrets, which hands a value only to the program it was stored for; bin/secret prints none" >&2; exit 3 ;;
    esac ;;
  *) echo "secret: $ade_rec names an unknown store; run bin/keys store in your own terminal" >&2; exit 2 ;;
esac
# <<< ade-secrets v2
```

A `builtin` record (or none, without ade-secrets) falls through to the hub's own code, which must answer
`--helper-line <name>` with its own line. **The store decision travels in the key helper line**: the hub writes
`apiKeyHelper` from `bin/secret --helper-line <name>` each time it writes a session's settings. Delegating, the line
is `'<path>' get '<scope>.<name>'`: ade-secrets itself, by the path in the record, with no `bin/secret`, `PATH` or
environment in between. With `builtin` it is the hub's own `bin/secret <name>` line, and a later switch to
ade-secrets makes that line refuse (exit 3), loudly, until the settings are written again.

### Calls a hub may make

| bin/secret | Goes to | Who calls it | Exit |
|---|---|---|---|
| `--set <key> --helper` (or a `--run` mark, or `--plain`) | `set <scope>.<key> --kind api-key --used-by hub:<scope> <use>` | `bin/keys set`, a person's terminal | passed on |
| `--has <key>` | `has <scope>.<key>` | any hub code, any context | 0, 1; else stop |
| `--run <key> -- <program> [args]` | `run <scope>.<key> -- <program> [args]` | `bin/gemini-run`, `bin/chat`; terminal or service | passed on |
| `--helper-line <key>` | nothing (prints the line) | the settings writers | 0 |
| `--forget <key>`, `--list` | `forget <scope>.<key>`, `list --names --scope <scope>` | `bin/keys`, a person's terminal | passed on |
| `<key>` | refused, exit 3 | nobody | 3 |

### Which hub key gets which mark

| Tool | Entry | Mark | Its consumer |
|---|---|---|---|
| anthropic | `<scope>.anthropic-api-key` | `--helper` | Claude Code, for `bin/agent` with a key and the live test |
| deepseek, glm | `<scope>.deepseek-api-key`, `<scope>.zai-api-key` | `--helper` | Claude Code on that provider |
| muse | `<scope>.meta-model-api-key` | `--plain` until `bin/lib.sh` has a provider row for it, then `--helper` | none yet |
| gemini | `<scope>.gemini-api-key` | `--run <real path of gemini> --env GEMINI_API_KEY` | the Gemini CLI, started by `bin/gemini-run` |
| telegram | `<scope>.telegram-bot-token` | `--run <hub>/bin/chat --stdin` | `bin/chat`, which writes the plugin's `.env` or sends a message |

### What the hub does with them

- **No reads outside a consumer.** `provider_key_ok`, `anthropic_key_ok` and `gemini_auth read` become presence
  checks (`--has`); the check before a launch is presence only. A present entry that cannot be read fails at launch,
  in Claude Code's key helper or in `run`, with the store's reason. (Before this ships, C1 below must hold.)
- `bin/gemini-run` ends with `exec "$H/bin/secret" --run gemini-api-key -- "$G" "${PRE[@]}" ...`. Gemini by key
  therefore starts only from a terminal or a service (`bin/work`'s new window counts); a delegated Gemini run from
  inside an agent session is refused by `run`, and the hub says so before it picks that candidate.
- `bin/chat start` gets the token through `bin/secret --run telegram-bot-token -- "$H/bin/chat" <internal step>`,
  which writes the plugin's 0600 `.env` (deleted once the plugin has read it, or after 60 s, as today). A send from
  a terminal, a job or the forwarder uses `--run` the same way. A send from a hook or an agent session (exit 3 from
  `run`) is kept in `<state dir>/chat/pending/` for the forwarder, and says so, including when no forwarder runs.

## Release files and version

`.github/workflows/release.yml` adds one input: `assets: "bin/ade-secrets lib/vault.sh"`. The shared workflow names
each asset by its file name, so the release carries `ade-secrets` and `vault.sh`, and its `release.json` holds each
one's sha256 under those names. An install puts them back as `<dir>/bin/ade-secrets` and `<dir>/lib/vault.sh` (the
script finds `lib/` from its real path). The version is written into the script (`ADE_SECRETS_VERSION=0.4.0`), since
`VERSION` is not a release file; a test holds it equal to `VERSION`. `ade-secrets --version` prints that one line in
every context, after the start-up check. `list --due` uses `ADE_SECRETS_ROTATE_DAYS` (default 90, the vault's rule):
entries whose last rotation is that many days old or more, by full name, sorted, exit 0 (empty when none).

## Compatibility

| Case | What happens |
|---|---|
| v1 hub (H2 block) with tool 0.4.0 | Every v1 call works as with 0.3.0 (`set --helper`, `list --names`, `forget`, `get`); `set` now asks before a replace. The hub keeps its v1 limits. |
| v1 entries (no scope) | Left alone, shown with scope `-`, still served by `get` when marked `--helper`. A v2 hub never uses them; `bin/keys` in a terminal names any that match one of its keys and says how to enter it again and forget the old one. Nothing is copied. |
| v2 hub with tool 0.3.0 | `bin/keys store` refuses to record it; a record made earlier stops every key call at the block's version check (exit 2, the line names both versions). |
| meta written by 0.4.0, then `set` by 0.3.0 | 0.3.0 writes seven fields and drops the run mark; `run` then refuses (exit 3, not marked for run). |
| ade-cli built for v1 (A13) | It takes a hub for a delegating one by v1's marker line, which a v2 hub does not carry; its `bin/keys set` with the key piped on stdin is refused by `set` (no terminal), and ade reports "could not store". |

## The key helper and the guards

v1's section "The key helper: what it can and cannot tell apart" and "Start-up" hold unchanged for `get`. `has`
skips the context guards, `run` uses `guard_run` above, every other command uses v1's local guard. The Gemini CLI
joins Claude Code as an agent context for `run` and the local guard, once C4 confirms its signals.

| Caller | Session variable | claude ancestor | Terminal | `has` | `run` | `get` | others |
|---|---|---|---|---|---|---|---|
| A person's terminal | no | no | yes | yes | yes | no | yes |
| A service or job of the person's login session | no | no | no | yes | yes | no | no |
| An agent session (tool, hook, MCP server, plugin) | yes, or | yes | any | yes | no | no | no |
| Claude Code's key helper | `CLAUDE_CODE_ENTRYPOINT` only | parent | no | yes | no | yes | no |

## Residual risk (v2 additions)

v1's list stays true. Added, plainly:

- **Run entries are as readable as helper entries.** In the Keychain they trust `/usr/bin/security`, so any process
  of the user reads them with `security find-generic-password -w`, no dialog (the deny rule matches that plain command
  only); in pass, while gpg-agent holds the passphrase. Through ade-secrets: the recorded program and anything it
  runs; any process the guard does not take for an agent (a terminal, a service, a job, and an agent that hid its
  traces, opened a terminal window or wrote a LaunchAgent).
- **The allow-list is a path, not a program's content.** Whoever can write the recorded file (the user, so an agent)
  can change what it does; the arguments are free (for example the Gemini CLI with a prompt of the caller's choice).
- **An environment variable is readable** by the program's children unless the program removes it (the hub sets the
  Gemini CLI's variable redaction, C4), and by other processes of the user where the system shows a process's
  environment (C8). The Gemini key is therefore readable by that Gemini session and what it runs: the same class as a
  helper key and Claude Code.
- **The Telegram bot token** ends with the channel plugin, an MCP server that the orchestrator's Claude Code starts:
  that session and anything it runs can reach it (the `.env` for up to 60 s, the plugin's memory, C5).
- **`has` answers everywhere**, one bit per name; names were already readable in `meta`.
- **The run mark lives in `meta`**, like the helper flag: anything running as the user can mark an entry for `run`
  with any program. A closed Keychain item (`--plain`) still raises the dialog on that read; pass does not.
- **The hub's record is a file of the user's.** An agent can rewrite it (another scope, another path, `builtin`); the
  block checks only that it belongs to this hub folder. Check it with `bin/keys store`.

## To confirm before building

Each must be checked by the builder against the real program, written into this file with the version and date, and
the design changed (not worked around) where one does not hold.

- **C1, Claude Code key helper failure:** what Claude Code does when `apiKeyHelper` exits non-zero or prints
  nothing: stop with a message, or fall back to its OAuth login and send that to `ANTHROPIC_BASE_URL`. If it falls
  back, a provider session's config folder (`.local/providers/<p>`) must hold no login, or presence-only checks are
  not enough. Also whether the helper's stderr is shown. (H4)
- **C2, the helper's context:** still no session marker, no terminal, claude (or `/bin/sh`) as its parent, on the
  current version; a line `'<absolute path>' get '<name>'` runs under `/bin/sh` as written. (S4, H4)
- **C3, channel plugins:** whether the Telegram channel plugin is started with `CLAUDECODE` (an MCP server) and so
  could never call ade-secrets itself. (H4)
- **C4, the Gemini CLI:** that it takes its key only from `GEMINI_API_KEY` in its environment; that
  `security.environmentVariableRedaction.blocked` keeps it out of `run_shell_command`'s children; which variable, if
  any, it sets in the shell commands it runs; how a gemini process shows in `ps` (`comm`, `args`) for the ancestor
  check; whether the real path of `gemini` changes on an upgrade. (S4, H4)
- **C5, the Telegram plugin:** that it reads the token from `$TELEGRAM_STATE_DIR/.env` once at start; whether it puts
  it into its own environment (inherited by its children); that it never reads the file again. (H4)
- **C6, launchd:** a LaunchAgent's environment has no Claude Code variable; a double-forked child of a job is
  reparented to launchd; `security` reads a `/usr/bin/security`-trusted item from a LaunchAgent without a dialog while
  the login keychain is unlocked, and what it returns when it is locked. (S4, H4)
- **C7, systemd user units:** no session variable; orphans are reparented to the user manager (no claude ancestor);
  `pass` from a unit with no terminal: works with a cached passphrase, fails (with which message) without. (S4, H4)
- **C8, process environments:** whether another process of the same user can read a process's environment
  (Linux `/proc/<pid>/environ`; macOS `ps -E` or `ps eww`), for the residual risk wording. (S4)
- **C9, Keychain attributes:** `security find-generic-password -s ade-secrets -a <name>` without `-w` raises no
  dialog on a `-T ""` item. (S3) Not confirmed by the S3 builder (2026-11-22): builders run fakes only and never
  touch a real keychain; `has` is built as written above (meta, then the attributes) and step 6 of the owner check
  below confirms it.
- **C10, the shared release workflow:** that `assets` takes repository paths separated by spaces, names each asset
  by its base name, and writes the name and sha256 into `release.json` in the form ade-cli's `manifest_py` reads. (S5)

## Owner check (v2 additions)

With throwaway values, in your own terminal, as in v1: (1) `ade-secrets set owner.check --helper`, then
`ade-secrets set owner.check` again: it asks `replace ...? [y/N]`; `n` keeps it. (2) From a Claude Code session's
shell: `ade-secrets has owner.check` exits 0 with no dialog; `ade-secrets run owner.check -- /usr/bin/true` is
refused. (3) `ade-secrets set owner.run --run /usr/bin/wc --stdin` (type `throwaway-5`), then
`ade-secrets run owner.run -- wc -c </dev/null` prints `12` (the value, its newline, no more) and `ade-secrets run owner.run --
/bin/cat` is refused. (4) A LaunchAgent that runs step 3's `wc` writes `12` to a file with no dialog. (5) Forget both.
(6, C9) `ade-secrets set owner.closed --plain` (type `throwaway-6`), then `ade-secrets has owner.closed; echo $?` and
`security find-generic-password -s ade-secrets -a owner.closed >/dev/null; echo $?`: each prints `0` and no dialog
shows (a dialog here means `has` must change). Then `ade-secrets forget owner.closed`.
