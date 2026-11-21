# S2 design note: `ade-secrets vault`

Story: `docs/stories/S2-terminal-vault.md`. Risk: high (secrets). Depends on S1.

## Shape
- `lib/vault.sh`, sourced by `bin/ade-secrets vault` after S1's local-only guard (so the vault refuses in an agent
  context exactly like every other command) and store choice. Bash 3.2: one key per `read -rsn1`, arrows decoded
  from their escape sequences, full redraw (clear screen) after every key, alternate screen restored on exit.
- Every action runs in a subshell (`v_act`): S1's `die` ends the action, not the vault, and the action's last stderr
  line (a message, never a value) becomes the status line. Prompts go to `/dev/tty`, so S1's `set`/`forget` prompts
  moved from `read -p` (stderr) to `read_hidden`/`read_line`; the hidden prompt now turns echo off before the
  prompt shows.
- Values use S1's paths only: `read_hidden`, `clip_get` (cleared after), a generator (`python3 secrets`, into a
  variable), `put_value`, `get_value`, `cmd_copy`.
- Rotate: a new value (prompt, clipboard or generated) is checked by the entry's live test before it replaces the old
  one. The live test is a command (`t`), stored in `tests/<store>/<name>`; before it runs the vault shows it (control
  characters stripped) and asks y/N, and runs exactly what it showed. It gets the value on stdin, its output goes to
  /dev/null, it has 30 s. A failed test keeps the old value. With no live test the vault asks first (default no).
- Reveal: off unless `ADE_SECRETS_REVEAL=on`; confirmed (y/N) each time; the screen (and scrollback) is cleared after
  10 s or a key; TSTP is ignored for its duration (^Z would stop the vault with the value on screen) and restored.
- age: `u` decrypts the identity into the vault process's memory (never a file) and hands it to age on a pipe; `l`,
  `ADE_SECRETS_IDLE` seconds without a key (default and cap 300) and quitting forget it. Locked, an action asks for the
  passphrase itself. The recipient comes from the identity (S1).
- Runtime folders `notes/`, `notes/<store>`, `tests/`, `tests/<store>` are created mode 700 and refused (the vault does
  not open) when a symlink, not the user's or not 700. A clipboard value is cleared by an EXIT trap in add and rotate.
- The header keeps the store line (recorded or not, how to switch: `ade-secrets store <name>`) and the entries left
  in another store.
- Reminders: entries whose last rotation is `ADE_SECRETS_ROTATE_DAYS` (default 90) or more ago are flagged on the
  header and their row (`rotate!`).
- Notes: one line per entry in `notes/<store>/<name>`, plain text, labelled "never a secret"; control characters are
  stripped when saved and when drawn. `forget` removes the
  note and the live test with the entry.

## Decision
- The story says tmux send-keys/capture-pane; tmux is not on every machine or CI image, so the tests use the stdlib
  pty harness from S1 (`tests/pty_run.py`): keys are sent the same way, and the screen check is stricter: the whole
  raw output stream is scanned, and "gone after 10 s" is the screen after the last clear. The story now says so.
- Tests for ^Z run the vault in its own foreground process group (`pty_run.py --own-pgrp`): by default the harness's
  group is orphaned and the system discards terminal stop signals, so a ^Z test there could not fail.
