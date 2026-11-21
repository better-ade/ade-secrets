#!/bin/bash
# S1 AC7: the backend never switches silently; a store with entries left behind after a switch is reported.
. "$(dirname "$0")/lib.sh"
t_setup; CLIP_KIND=xclip
STORE_KIND=
t_tty -- @ list
check "with no store chosen, nothing is guessed" eval '[ "$RC" = 2 ] && has "$OUT" ADE_SECRETS_STORE'
STORE_KIND=bogus
t_tty -- @ list
check "an unknown store is refused" [ "$RC" = 2 ]

STORE_KIND=keychain
t_set alpha 'fixture-value-switch-1'
t_set beta 'fixture-value-switch-2'
STORE_KIND=
t_tty -- @ list --names
check "unset later, the recorded store is used (not another)" [ "$OUT" = "$(printf 'alpha\nbeta')" ]

STORE_KIND=pass
t_tty -- @ list
check "an explicit switch is reported" eval 'has "$OUT" "switched" && has "$OUT" keychain'
check "entries left in the old store are reported by name" eval 'has "$OUT" "2 entries left in keychain" && has "$OUT" alpha'
t_tty -- @ status
check "status reports them too" eval 'has "$OUT" "2 entries left in keychain"'
t_tty -- @ copy alpha
check "an entry in the old store is not read from it" eval '[ "$RC" = 1 ] && has "$OUT" "ADE_SECRETS_STORE=keychain" && [ -z "$(clip)" ]'

: > "$T/state/calls.log"
t_remove_fake pass
t_set gamma 'fixture-value-switch-3'
check "a missing backend tool fails" eval '[ "$RC" = 1 ] && has "$OUT" pass'
check "... without falling back to another store" eval '! grep -q "^CALL " "$T/state/calls.log" && [ ! -e "$T/state/keychain/ade-secrets/gamma" ]'

STORE_KIND=keychain
t_tty -- @ list --names
check "switching back finds the entries again" [ "$OUT" = "$(printf 'alpha\nbeta')" ]
t_tty -- @ list
check "... and reports nothing left behind" eval 'hasnt "$OUT" "left in"'
t_done
