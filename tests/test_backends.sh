#!/bin/bash
# S1 AC1: each backend round-trips set/copy/forget with values on stdin only (the fakes record argv and env).
. "$(dirname "$0")/lib.sh"
V1='fixture-value-one-7q'
V2='fixture value "two" \ $x'

for kind in keychain pass age; do
  t_setup; STORE_KIND=$kind CLIP_KIND=xclip
  if [ $kind = age ]; then t_unlock 'fixture-pass-phrase'; check "$kind: unlock creates the store" [ "$RC" = 0 ]; fi

  t_set alpha "$V1"
  check "$kind: set from the hidden prompt" [ "$RC" = 0 ]
  check "$kind: the typed value is not echoed" hasnt "$OUT" "$V1"
  case $kind in
    keychain) check "$kind: stored in the Keychain" [ "$(cat "$T/state/keychain/ade-secrets/alpha" 2>/dev/null)" = "$V1" ] ;;
    pass) check "$kind: stored in pass" [ "$(cat "$T/state/pass/ade-secrets/alpha" 2>/dev/null)" = "$V1" ] ;;
    age) check "$kind: stored as an age file" [ -s "$STORE/age/entries/alpha.age" ] ;;
  esac

  t_tty -- @ copy alpha --for 30
  check "$kind: copy puts the value on the clipboard" [ "$RC" = 0 -a "$(clip)" = "$V1" ]
  check "$kind: copy never shows the value" hasnt "$OUT" "$V1"

  t_set beta "$V2"
  t_tty -- @ copy beta --for 30
  check "$kind: a value with spaces, quotes and backslashes round-trips" [ "$(clip)" = "$V2" ]

  clip_put 'fixture-from-clipboard-3'
  t_tty -- @ set gamma --clipboard
  check "$kind: set --clipboard stores the clipboard" [ "$RC" = 0 ]
  check "$kind: set --clipboard clears the clipboard" [ -z "$(clip)" ]
  t_tty -- @ copy gamma --for 30
  check "$kind: the clipboard value round-trips" [ "$(clip)" = 'fixture-from-clipboard-3' ]

  t_tty "expect type the name" "send wrong\n" -- @ forget alpha
  check "$kind: forget refuses when the typed name differs" [ "$RC" != 0 ]
  t_tty -- @ copy alpha --for 30
  check "$kind: ... and the entry stays" [ "$RC" = 0 ]

  t_tty "expect type the name" "send alpha\n" -- @ forget alpha
  check "$kind: forget after typing the name" [ "$RC" = 0 ]
  clip_put ''
  t_tty -- @ copy alpha --for 30
  check "$kind: a forgotten entry is gone" [ "$RC" != 0 -a -z "$(clip)" ]
  case $kind in
    keychain) check "$kind: removed from the Keychain" [ ! -e "$T/state/keychain/ade-secrets/alpha" ] ;;
    pass) check "$kind: removed from pass" [ ! -e "$T/state/pass/ade-secrets/alpha" ] ;;
    age) check "$kind: the age file is removed" [ ! -e "$STORE/age/entries/alpha.age" ] ;;
  esac

  check "$kind: the backend tool was really called" grep -q "^CALL $( [ $kind = keychain ] && echo security || echo $kind) " "$T/state/calls.log"
  check "$kind: no value in any argv, environment, screen or file outside the store" eval 'no_leak "$V1" && no_leak "$V2" && no_leak fixture-from-clipboard-3'
  t_cleanup
done
t_done
