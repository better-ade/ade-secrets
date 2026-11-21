#!/bin/bash
# S1 AC6: the age store is encrypted at rest, locks after idle, refuses copy while locked.
. "$(dirname "$0")/lib.sh"
V1='fixture-value-age-1'
t_setup; STORE_KIND=age CLIP_KIND=xclip

t_tty -- @ set alpha
check "a new age store refuses set until it is unlocked" [ "$RC" = 5 ]
t_unlock 'fixture-pass-phrase'
check "unlock creates a passphrase-protected identity" eval '[ "$RC" = 0 ] && [ -s "$STORE/age/identity.age" ]'
check "the identity is encrypted at rest" eval '! grep -q FAKE-AGE-IDENTITY "$STORE/age/identity.age"'
t_set alpha "$V1"
check "set while unlocked" [ "$RC" = 0 ]
b64="$(printf '%s' "$V1" | base64)"
check "the entry is encrypted at rest" eval '[ -s "$STORE/age/entries/alpha.age" ] && ! grep -r -q -F -- "$V1" "$STORE" && ! grep -r -q -F -- "$b64" "$STORE"'
check "the store folder is private" eval '[ "$(ls -ld "$STORE" | cut -c1-10)" = drwx------ ]'
t_tty -- @ status
check "status says unlocked" eval 'has "$OUT" unlocked'

t_tty -- @ lock
check "lock" [ "$RC" = 0 ]
t_tty -- @ status
check "status says locked" eval 'has "$OUT" locked && hasnt "$OUT" unlocked'
clip_put 'fixture-untouched'
t_tty -- @ copy alpha
check "copy refuses while locked" eval '[ "$RC" = 5 ] && has "$OUT" unlock'
check "... and leaves the clipboard alone" [ "$(clip)" = fixture-untouched ]

t_tty "expect Enter passphrase" "sleep 0.1" "send not-the-passphrase\n" -- @ unlock
check "a wrong passphrase does not unlock" [ "$RC" != 0 ]
t_tty -- @ copy alpha
check "... so copy still refuses" [ "$RC" = 5 ]

EXTRA_ENV=(ADE_SECRETS_IDLE=2)
t_unlock 'fixture-pass-phrase'
check "unlock again" [ "$RC" = 0 ]
t_tty -- @ copy alpha --for 30
check "copy while unlocked" eval '[ "$RC" = 0 ] && [ "$(clip)" = "$V1" ]'
sleep 5
check "the session locks itself after the idle time, with no command run" [ ! -e "$STORE/session/identity" ]
clip_put 'fixture-untouched'
t_tty -- @ copy alpha
check "copy refuses after the idle lock" eval '[ "$RC" = 5 ] && [ "$(clip)" = fixture-untouched ]'
EXTRA_ENV=(ADE_SECRETS_IDLE=3600)
t_unlock 'fixture-pass-phrase'
t_tty -- @ status
check "the idle time is capped at 5 minutes" eval 'has "$OUT" "300 s"'
EXTRA_ENV=()
t_tty -- @ lock
check "nothing leaked" no_leak "$V1"
t_done
