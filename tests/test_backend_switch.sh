#!/bin/bash
# S1 AC7: the backend never switches silently; a store with entries left behind after a switch is reported.
# Review fix: the store is recorded once (the first set, from ADE_SECRETS_STORE) and changes only through the
# explicit `ade-secrets store <name>` command; a different ADE_SECRETS_STORE later is refused, not followed.
. "$(dirname "$0")/lib.sh"
t_setup; CLIP_KIND=xclip
recorded() { cat "$STORE/store" 2>/dev/null; }
STORE_KIND=
t_tty -- @ list
check "with no store chosen, nothing is guessed" eval '[ "$RC" = 2 ] && has "$OUT" ADE_SECRETS_STORE'
STORE_KIND=bogus
t_tty -- @ list
check "an unknown store is refused" [ "$RC" = 2 ]

STORE_KIND=keychain
t_set alpha 'fixture-value-switch-1'
t_set beta 'fixture-value-switch-2'
check "the first set records the store" [ "$(recorded)" = keychain ]
STORE_KIND=
t_tty -- @ list --names
check "unset later, the recorded store is used (not another)" [ "$OUT" = "$(printf 'alpha\nbeta')" ]

STORE_KIND=pass
t_tty -- @ list
check "a different ADE_SECRETS_STORE is refused, not followed" eval '[ "$RC" = 2 ] && has "$OUT" "ade-secrets store pass"'
t_set gamma 'fixture-value-switch-3'
check "... set too, and nothing is written to either store" eval '[ "$RC" = 2 ] && [ "$(recorded)" = keychain ] && [ ! -e "$T/state/pass/ade-secrets/gamma" ] && [ ! -e "$T/state/keychain/ade-secrets/gamma" ]'

STORE_KIND=
t_tty -- @ store
check "store shows the recorded store" eval '[ "$RC" = 0 ] && has "$OUT" keychain'
t_remove_fake pass
t_tty -- @ store pass
check "a switch to a store whose tool is missing fails, and keeps the record" eval '[ "$RC" = 1 ] && has "$OUT" pass && [ "$(recorded)" = keychain ]'
cp "$TESTS_DIR/fakes/pass" "$T/bin/pass"
t_tty -- @ store bogus
check "a switch to an unknown store is refused" eval '[ "$RC" = 2 ] && [ "$(recorded)" = keychain ]'
t_tty -- @ store pass
check "an explicit switch is announced" eval '[ "$RC" = 0 ] && has "$OUT" "switched store: keychain -> pass" && [ "$(recorded)" = pass ]'
check "... with the entries it leaves behind, by name" eval 'has "$OUT" "2 entries left in keychain" && has "$OUT" alpha'
t_tty -- @ list
check "list reports the entries left in the old store" eval '[ "$RC" = 0 ] && has "$OUT" "2 entries left in keychain"'
t_tty -- @ status
check "status reports them too" eval 'has "$OUT" "2 entries left in keychain"'
t_copy alpha
check "an entry in the old store is not read from it" eval '[ "$RC" = 1 ] && has "$OUT" "ade-secrets store keychain" && [ -z "$(clip)" ]'
STORE_KIND=pass
t_tty -- @ list --names
check "ADE_SECRETS_STORE equal to the recorded store is fine" [ "$RC" = 0 ]

STORE_KIND=
t_tty -- @ store keychain
t_tty -- @ list --names
check "switching back finds the entries again" [ "$OUT" = "$(printf 'alpha\nbeta')" ]
t_tty -- @ list
check "... and reports nothing left behind" eval 'hasnt "$OUT" "left in"'
t_tty -- @claude @ store pass
check "store refuses inside an agent context" eval '[ "$RC" = 3 ] && [ "$(recorded)" = keychain ]'
t_done
