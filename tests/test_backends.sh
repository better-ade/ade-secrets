#!/bin/bash
# S1 AC1: each backend round-trips set/copy/forget with values on stdin only (the fakes record argv and env).
# Review fixes: Keychain entries not enabled for the key helper trust no application (-T ""), so every read is the
# user's own approval in the macOS dialog; helper entries trust /usr/bin/security. The age store keeps no session:
# set and copy ask for the passphrase each time. A value taken from the clipboard is cleared on every exit path.
. "$(dirname "$0")/lib.sh"
V1='fixture-value-one-7q'
V2='fixture value "two" \ $x'

for kind in keychain pass age; do
  t_setup; STORE_KIND=$kind CLIP_KIND=xclip
  if [ $kind = age ]; then t_unlock; check "$kind: unlock creates the store" [ "$RC" = 0 ]; fi

  t_set alpha "$V1"
  check "$kind: set from the hidden prompt" [ "$RC" = 0 ]
  check "$kind: the typed value is not echoed" hasnt "$OUT" "$V1"
  case $kind in
    keychain) check "$kind: stored in the Keychain" [ "$(cat "$T/state/keychain/ade-secrets/alpha" 2>/dev/null)" = "$V1" ] ;;
    pass) check "$kind: stored in pass" [ "$(cat "$T/state/pass/ade-secrets/alpha" 2>/dev/null)" = "$V1" ] ;;
    age) check "$kind: stored as an age file" [ -s "$STORE/age/entries/alpha.age" ] ;;
  esac

  t_copy alpha --for 30
  check "$kind: copy puts the value on the clipboard" [ "$RC" = 0 -a "$(clip)" = "$V1" ]
  check "$kind: copy never shows the value" hasnt "$OUT" "$V1"

  t_set beta "$V2"
  t_copy beta --for 30
  check "$kind: a value with spaces, quotes and backslashes round-trips" [ "$(clip)" = "$V2" ]

  clip_put 'fixture-from-clipboard-3'
  _t_pw; t_tty ${PW_STEPS[@]+"${PW_STEPS[@]}"} -- @ set gamma --clipboard
  check "$kind: set --clipboard stores the clipboard" [ "$RC" = 0 ]
  check "$kind: set --clipboard clears the clipboard" [ -z "$(clip)" ]
  t_copy gamma --for 30
  check "$kind: the clipboard value round-trips" [ "$(clip)" = 'fixture-from-clipboard-3' ]

  printf 'fixture-multi-line-4\nsecond line' > "$T/state/clipboard"
  _t_pw; t_tty ${PW_STEPS[@]+"${PW_STEPS[@]}"} -- @ set delta --clipboard
  check "$kind: a refused clipboard value is still cleared from the clipboard" [ "$RC" = 1 -a -z "$(clip)" ]

  t_tty "expect type the name" "send wrong\n" -- @ forget alpha
  check "$kind: forget refuses when the typed name differs" [ "$RC" != 0 ]
  t_copy alpha --for 30
  check "$kind: ... and the entry stays" [ "$RC" = 0 ]

  t_tty "expect type the name" "send alpha\n" -- @ forget alpha
  check "$kind: forget after typing the name" [ "$RC" = 0 ]
  clip_put ''
  t_copy alpha --for 30
  check "$kind: a forgotten entry is gone" [ "$RC" != 0 -a -z "$(clip)" ]
  case $kind in
    keychain) check "$kind: removed from the Keychain" [ ! -e "$T/state/keychain/ade-secrets/alpha" ] ;;
    pass) check "$kind: removed from pass" [ ! -e "$T/state/pass/ade-secrets/alpha" ] ;;
    age) check "$kind: the age file is removed" [ ! -e "$STORE/age/entries/alpha.age" ] ;;
  esac

  check "$kind: the backend tool was really called" grep -q "^CALL $( [ $kind = keychain ] && echo security || echo $kind) " "$T/state/calls.log"
  check "$kind: no value in any argv, environment, screen or file outside the store" eval 'no_leak "$V1" && no_leak "$V2" && no_leak fixture-from-clipboard-3 && no_leak fixture-multi-line-4'
  t_cleanup
done

# Keychain access lists: what macOS enforces outside ade-secrets
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
acl() { cat "$T/state/keychain/ade-secrets/$1.acl" 2>/dev/null; }
kc() { cat "$T/state/keychain/ade-secrets/$1" 2>/dev/null; }
t_set closed 'fixture-value-acl-1'
t_set opened 'fixture-value-acl-2' --helper
check "keychain: an entry not for the key helper trusts no application (-T \"\")" [ "$(acl closed)" = closed ]
check "keychain: a key-helper entry trusts /usr/bin/security" [ "$(acl opened)" = security ]
: > "$T/state/calls.log"; t_copy closed --for 30
check "keychain: copying a closed entry goes through the macOS allow dialog" eval '[ "$RC" = 0 ] && grep -q "^DIALOG read closed" "$T/state/calls.log"'
: > "$T/state/calls.log"; t_copy opened --for 30
check "keychain: a key-helper entry is read without a dialog" eval '[ "$RC" = 0 ] && ! grep -q "^DIALOG" "$T/state/calls.log"'
clip_put 'fixture-untouched'; EXTRA_ENV=(FAKE_DENY=1); t_copy closed --for 30; EXTRA_ENV=()
check "keychain: Deny in the dialog means nothing is copied" [ "$RC" = 1 -a "$(clip)" = fixture-untouched ]
t_set closed 'fixture-value-acl-3' --helper
check "keychain: enabling the helper re-creates the entry with security trusted" eval '[ "$(acl closed)" = security ] && [ "$(kc closed)" = fixture-value-acl-3 ]'
t_set closed 'fixture-value-acl-4' --no-helper
check "keychain: disabling the helper closes the entry again" eval '[ "$(acl closed)" = closed ] && [ "$(kc closed)" = fixture-value-acl-4 ]'
EXTRA_ENV=(FAKE_DENY=1); t_set closed 'fixture-value-acl-5'; EXTRA_ENV=()
check "keychain: a replacement refused in the dialog is reported, not claimed" eval '[ "$RC" = 1 ] && [ "$(kc closed)" = fixture-value-acl-4 ]'
t_set closed 'fixture-value-acl-6'
check "keychain: a replacement in the same second is still verified" eval '[ "$RC" = 0 ] && [ "$(kc closed)" = fixture-value-acl-6 ]'
check "keychain: no value leaked" eval 'no_leak fixture-value-acl-1 && no_leak fixture-value-acl-3 && no_leak fixture-value-acl-6'
t_done
