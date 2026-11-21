#!/bin/bash
# S1 AC4 (reworded after review): `get` prints the value only for an entry the user enabled for the key helper, and
# only in a key-helper-like context. Claude Code gives the helper no marker (docs/contract.md), so the context checks
# (no tool/hook markers, no terminal, claude as the nearest non-shell parent) are an accident guard, not a boundary:
# anything Claude Code runs can strip the markers and read a helper entry. Entries not enabled for the helper are
# never returned, whatever the context.
. "$(dirname "$0")/lib.sh"
V1='fixture-value-helper-1'
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
t_set apikey "$V1" --helper
t_set other 'fixture-value-not-helper-2'
check "setup: stored" [ "$RC" = 0 ]

helper() { t_notty -- @claude /bin/sh -c "\"$BIN\" $1"; }
for verb in get helper; do
  EXTRA_ENV=(CLAUDE_CODE_ENTRYPOINT=cli)
  helper "$verb apikey"
  check "$verb: prints the value in the key-helper context" [ "$RC" = 0 -a "$OUT" = "$V1" -a -z "$ERR" ]
  EXTRA_ENV=()
  helper "$verb apikey"
  check "$verb: ... also without CLAUDE_CODE_ENTRYPOINT" [ "$RC" = 0 -a "$OUT" = "$V1" ]
  t_notty -- @claude @ $verb apikey
  check "$verb: ... and when claude runs it directly (sh exec'd it)" [ "$RC" = 0 -a "$OUT" = "$V1" ]

  for v in "CLAUDECODE=1 CLAUDE_CODE_CHILD_SESSION=1" CLAUDECODE=1 CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_PID=1 \
           CLAUDE_CODE_SESSION_ID=fixture CLAUDE_PROJECT_DIR=/tmp; do
    EXTRA_ENV=($v)
    t_notty -- @claude /bin/bash -c "\"$BIN\" $verb apikey"
    check "$verb: accident guard: refuses with the Bash tool markers ($v)" [ "$RC" = 3 -a -z "$OUT" ]
  done
  EXTRA_ENV=()
  t_notty -- @claude /bin/bash -c "\"$BIN\" $verb apikey"
  check "$verb: documented limit: with the markers stripped, a Bash-tool-like context reads a helper entry" [ "$RC" = 0 -a "$OUT" = "$V1" ]
  t_notty -- @claude /bin/bash -c "\"$BIN\" $verb other"
  check "$verb: ... but never an entry not enabled for the helper" [ "$RC" = 3 -a -z "$OUT" ]
  t_notty -- /bin/sh -c "\"$BIN\" $verb apikey"
  check "$verb: refuses without a claude parent" [ "$RC" = 3 -a -z "$OUT" ]
  t_notty -- @claude python3 -c 'import subprocess, sys; sys.exit(subprocess.call(sys.argv[1:]))' "$BIN" $verb apikey
  check "$verb: refuses when a non-shell process sits between claude and it" [ "$RC" = 3 -a -z "$OUT" ]
  t_tty -- @claude @ $verb apikey
  check "$verb: refuses in a terminal" eval '[ "$RC" = 3 ] && hasnt "$OUT" "$V1"'
  helper "$verb other"
  check "$verb: refuses an entry not enabled for the helper" [ "$RC" = 3 -a -z "$OUT" ]
  helper "$verb missing"
  check "$verb: an unknown name prints nothing" [ "$RC" != 0 -a -z "$OUT" ]
  helper "$verb ../x"
  check "$verb: an invalid name is refused" [ "$RC" != 0 -a -z "$OUT" ]
done
check "the value never reached an argv or environment" eval '! grep -q -F -- "$V1" "$T/state/calls.log"'
check "no refusal printed the value on stderr" eval '! grep -q -F -- "$V1" "$T"/run/e.*' 
t_done
