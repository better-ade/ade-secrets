#!/bin/bash
# S2 review fixes: the vault's runtime folders are private; a value taken from the clipboard is cleared on every exit
# path of add and rotate; the live-test command is shown and confirmed before it runs; notes and commands are drawn
# without control characters; the store line (and entries left in another store) stays on screen; the reveal ignores
# ^Z while the value is shown and restores it after; the age vault keeps its identity in memory only and locks itself
# after at most 300 idle seconds.
. "$(dirname "$0")/lib.sh"
V1='fixture-value-vrev-1'
kc() { cat "$T/state/keychain/ade-secrets/$1" 2>/dev/null; }
rawout() { cat "$T/run/out.$T_N"; }
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
T_TIMEOUT=60
t_set alpha "$V1"
check "setup: stored" [ "$RC" = 0 ]

# ---- runtime folders: refused when a symlink or not mode 700 (never repaired)
mkdir -m 700 "$T/elsewhere"
for d in notes tests; do
  rm -rf "$STORE/$d"; ln -s "$T/elsewhere" "$STORE/$d"
  t_tty -- @ vault
  check "the vault refuses a symlinked $d folder" eval '[ "$RC" = 1 ] && has "$OUT" symlink && hasnt "$OUT" "q quit" && [ -z "$(ls -A "$T/elsewhere")" ]'
  rm "$STORE/$d"; mkdir -m 755 "$STORE/$d"
  t_tty -- @ vault
  check "the vault refuses a $d folder that is not mode 700" eval '[ "$RC" = 1 ] && has "$OUT" 700 && hasnt "$OUT" "q quit"'
  rmdir "$STORE/$d"
done
t_tty "expect q quit" "send q" -- @ vault
check "the vault creates its folders private" eval '[ "$RC" = 0 ] && [ "$(ls -ld "$STORE/notes/keychain" | cut -c1-10)" = drwx------ ] && [ "$(ls -ld "$STORE/tests" | cut -c1-10)" = drwx------ ]'

# ---- add refuses a name that differs from an existing entry only in case (pass and age keep a file per name, and
# macOS paths ignore case: without the check, adding Alpha would replace alpha's value there)
t_tty "expect q quit" "send a" "expect name: " "send Alpha\n" "expect only in case" "send q" -- @ vault
check "add: a name equal to an existing one ignoring case is refused before any prompt, alpha intact" eval '[ "$RC" = 0 ] && has "$OUT" "Alpha differs from the entry alpha only in case" && hasnt "$OUT" "kind [" && ! grep -q "^Alpha	" "$STORE/meta" && [ "$(kc alpha)" = "$V1" ]'

# ---- the clipboard is cleared on every exit path of add and rotate
printf 'fixture-multi-line-5\nsecond' > "$T/state/clipboard"
t_tty "expect q quit" "send a" "expect name: " "send beta\n" "expect kind" "send \n" "expect used by" "send \n" \
  "expect value from" "send c" "expect one line" "send q" -- @ vault
check "add: a refused clipboard value is still cleared from the clipboard" eval '[ -z "$(clip)" ] && [ ! -e "$T/state/keychain/ade-secrets/beta" ]'
clip_put 'fixture-clip-rotate-6'
t_tty "expect q quit" "send r" "expect value from" "send c" "expect no live test" "send n" "expect old value is kept" "send q" -- @ vault
check "rotate: a clipboard value that is not stored is still cleared" eval '[ -z "$(clip)" ] && [ "$(kc alpha)" = "$V1" ]'

# ---- the live test is shown, with control characters stripped, and confirmed before it runs
cat > "$T/bin/provider-test" <<'EOF'
#!/bin/bash
v="$(cat)"; printf 'CALL provider-test argv=%s stdin-bytes=%s\n' "$*" "${#v}" >> "$FAKE_LOG"; exit 0
EOF
chmod +x "$T/bin/provider-test"
printf 'provider-test --check\007\n' > "$STORE/tests/keychain/alpha"
: > "$T/state/calls.log"
t_tty "expect q quit" "send r" "expect value from" "send p" "expect value for alpha" "sleep 0.2" "send good-fixture-7\n" \
  "expect run the live test" "send n" "expect old value is kept" "send q" -- @ vault
check "rotate shows the live-test command before it runs" has "$OUT" "provider-test --check"
check "... without its control characters" eval '! rawout | grep -q -F "$(printf "\007")"'
check "... and no means it does not run, and the old value is kept" eval '! grep -q "^CALL provider-test" "$T/state/calls.log" && [ "$(kc alpha)" = "$V1" ]'
t_tty "expect q quit" "send r" "expect value from" "send p" "expect value for alpha" "sleep 0.2" "send good-fixture-8\n" \
  "expect run the live test" "send y" "expect rotated alpha" "send q" -- @ vault
check "... yes runs it, and the new value is stored" eval 'grep -q "^CALL provider-test argv=--check stdin-bytes=14" "$T/state/calls.log" && [ "$(kc alpha)" = good-fixture-8 ]'

# ---- notes are drawn with control characters stripped
printf 'see the console \033[31mred\033]0;title\007 end\n' > "$STORE/notes/keychain/alpha"
t_tty "expect q quit" "send q" -- @ vault
check "a note's control characters are stripped before it is drawn" eval '! rawout | grep -q -F "$(printf "\033[31m")" && ! rawout | grep -q -F "$(printf "\007")" && has "$OUT" "see the console [31mred]0;title end"'
t_tty "expect q quit" "send n" "expect note for alpha" "send typed \033[1mbold\n" "expect note saved" "send q" -- @ vault
check "a typed note is saved without control characters" eval '[ "$(cat "$STORE/notes/keychain/alpha")" = "typed [1mbold" ]'

# ---- the store line, and the entries left in another store, stay on screen
STORE_KIND=
t_tty -- @ store pass
t_tty "expect q quit" "send x" "sleep 0.3" "snap $T/run/switched" "send q" -- @ vault
S="$(screen_of "$T/run/switched")"
check "after a switch the vault keeps showing the recorded store and how to switch" eval 'has "$S" "store: pass (recorded" && has "$S" "ade-secrets store <name>"'
check "... and the entries left in the old store, by name" eval 'has "$S" "1 entry left in keychain: alpha" && has "$S" "ade-secrets store keychain"'
STORE_KIND=keychain
t_tty -- @ vault
check "the vault refuses an ADE_SECRETS_STORE that differs from the recorded store" eval '[ "$RC" = 2 ] && has "$OUT" "ade-secrets store keychain" && hasnt "$OUT" "q quit"'
STORE_KIND=; t_tty -- @ store keychain; STORE_KIND=keychain

# ---- the reveal ignores ^Z while the value is on screen, and restores it after
EXTRA_ENV=(ADE_SECRETS_REVEAL=on) OWN_PGRP=1 T_TIMEOUT=25
t_tty "expect q quit" "send v" "expect for 10 s" "send y" "expect press a key" "sleep 0.3" "send \x1a" "sleep 0.5" \
  "send x" "expect hidden again" "send q" -- @ vault
check "reveal: ^Z while the value is shown does not stop the vault" eval '[ "$RC" = 0 ] && has "$OUT" "hidden again"'
t_tty "expect q quit" "send v" "expect for 10 s" "send y" "expect press a key" "send x" "expect hidden again" \
  "sleep 0.3" "send \x1a" "sleep 0.5" "send q" -- @ vault
check "... and after the reveal ^Z stops it again (TSTP restored)" [ "$RC" = 124 ]
EXTRA_ENV=() OWN_PGRP= T_TIMEOUT=60
check "nothing leaked (keychain)" eval 'no_leak "$V1" && no_leak good-fixture-7 && no_leak fixture-clip-rotate-6 && no_leak fixture-multi-line-5'
t_cleanup

# ---- the age vault: the identity in memory only, an idle lock of at most 300 s
t_setup; STORE_KIND=age CLIP_KIND=xclip
t_unlock; t_set alpha "$V1"
check "setup: an age entry" [ "$RC" = 0 ]
EXTRA_ENV=(ADE_SECRETS_IDLE=3600)
t_tty "expect q quit" "send u" "expect Enter passphrase" "sleep 0.1" "send $AGE_PW\n" "expect unlocked in this vault" \
  "run grep -r -l FAKE-AGE-IDENTITY '$T/home' '$T/tmp' > '$T/run/disk' 2>/dev/null; ls -A '$STORE' > '$T/run/ls'" \
  "send \r" "expect copied alpha" "send l" "expect locked: " "send \r" "expect Enter passphrase" "sleep 0.1" \
  "send $AGE_PW\n" "expect copied alpha" "send q" -- @ vault
check "age vault: unlocked, nothing plaintext is on disk and there is no session file" eval '[ "$RC" = 0 ] && [ ! -s "$T/run/disk" ] && [ -s "$T/run/ls" ] && ! grep -q session "$T/run/ls"'
check "age vault: unlocked, copy asks no passphrase; locked again, it asks" [ "$(printf '%s\n' "$OUT" | grep -o 'Enter passphrase' | wc -l | tr -d ' ')" = 2 ]
check "age vault: the idle lock is capped at 300 s" has "$OUT" "locks after 300 s idle"
EXTRA_ENV=(ADE_SECRETS_IDLE=2)
t_tty "expect q quit" "send u" "expect Enter passphrase" "sleep 0.1" "send $AGE_PW\n" "expect unlocked in this vault" \
  "expect locked after 2 s idle" "send q" -- @ vault
check "age vault: it locks itself after the idle time" eval '[ "$RC" = 0 ] && has "$OUT" "locked after 2 s idle"'
EXTRA_ENV=()
printf 'age1fixtureattackerrecipient\n' > "$STORE/age/recipient"; : > "$T/state/calls.log"
t_tty "expect q quit" "send u" "expect Enter passphrase" "sleep 0.1" "send $AGE_PW\n" "expect unlocked in this vault" \
  "send a" "expect name: " "send beta\n" "expect kind" "send \n" "expect used by" "send \n" "expect value from" "send g" \
  "expect stored beta" "send q" -- @ vault
check "age vault: add encrypts to the identity's recipient, never a file in the store" eval 'grep -q "argv=.*age1fakerecipientfortests" "$T/state/calls.log" && ! grep -q "argv=.*age1fixtureattacker" "$T/state/calls.log"'
check "nothing leaked (age)" no_leak "$V1"
t_done
