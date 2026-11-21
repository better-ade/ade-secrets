#!/bin/bash
# S1 AC3: every command except `get` refuses with CLAUDECODE=1 (and the other Claude Code session variables), with a
# claude ancestor, and without a TTY; it refuses before touching the store.
. "$(dirname "$0")/lib.sh"
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
t_set alpha 'fixture-value-local-1'
check "setup: a normal terminal works" [ "$RC" = 0 ]
: > "$T/state/calls.log"

COMMANDS="list status lock unlock set@alpha copy@alpha forget@alpha"
words() { echo "$1" | tr '@' ' '; }
refused() { [ "$RC" = 3 ] && has "$OUT$ERR" "own terminal"; }

for c in $COMMANDS; do
  for v in CLAUDECODE=1 CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_SESSION_ID=fixture CLAUDE_PID=1 CLAUDE_CODE_ENTRYPOINT=cli \
           CLAUDE_PROJECT_DIR=/tmp CLAUDE_PLUGIN_ROOT=/tmp; do
    EXTRA_ENV=("$v"); ERR=
    t_tty -- @ $(words "$c")
    check "$(words "$c") refuses with ${v%%=*}" refused
  done
  EXTRA_ENV=(); ERR=
  t_tty -- @claude @ $(words "$c")
  check "$(words "$c") refuses with a claude ancestor" refused
  t_tty -- @claude /bin/sh -c "\"$BIN\" $(words "$c")"
  check "$(words "$c") refuses with a claude ancestor further up" refused
  t_notty -- @ $(words "$c")
  check "$(words "$c") refuses without a TTY" refused
done

check "no refusal touched the store or the clipboard" [ ! -s "$T/state/calls.log" ]
check "the entry is still there" [ -f "$T/state/keychain/ade-secrets/alpha" ]
t_done
