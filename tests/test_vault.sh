#!/bin/bash
# S2: `ade-secrets vault`, driven like a terminal (tests/pty_run.py sends keys and records the screen).
# AC1 no value on screen (unless reveal is enabled and confirmed, then gone after 10 s); AC2 add (three ways), copy,
# rotate, delete and notes through S1's stdin-only paths; AC3 a failed live test keeps the old value; AC4 rotation
# reminders; AC5 the vault refuses inside an agent context.
. "$(dirname "$0")/lib.sh"
V1='fixture-value-vault-1'
VC='fixture-value-vault-clip-2'
BAD='bad-fixture-rotation-3'
GOOD='good-fixture-rotation-4'
kc() { cat "$T/state/keychain/ade-secrets/$1" 2>/dev/null; }
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
T_TIMEOUT=60

# ---- AC5: refuses inside an agent context
for v in CLAUDECODE=1 CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_SESSION_ID=fixture; do
  EXTRA_ENV=("$v"); t_tty -- @ vault
  check "AC5: the vault refuses to open with ${v%%=*}" eval '[ "$RC" = 3 ] && has "$OUT" "own terminal" && hasnt "$OUT" "q quit"'
done
EXTRA_ENV=()
t_tty -- @claude @ vault
check "AC5: the vault refuses to open with a claude ancestor" eval '[ "$RC" = 3 ] && hasnt "$OUT" "q quit"'
t_notty -- @ vault
check "AC5: the vault refuses to open without a TTY" [ "$RC" = 3 ]

# ---- AC2: add three ways, copy, notes, search, delete
clip_put "$VC"
t_tty "expect q quit" \
  "send a" "expect name: " "send alpha\n" "expect kind" "send api-key\n" "expect used by" "send agents\n" \
  "expect value from" "send p" "expect value for alpha" "sleep 0.2" "send $V1\n" "expect stored alpha" \
  "send a" "expect name: " "send beta\n" "expect kind" "send \n" "expect used by" "send \n" \
  "expect value from" "send c" "expect stored beta" \
  "send a" "expect name: " "send gamma\n" "expect kind" "send \n" "expect used by" "send \n" \
  "expect value from" "send g" "expect stored gamma" \
  "send q" -- @ vault
GEN="$(kc gamma)"
check "AC2: the vault opens and quits" [ "$RC" = 0 ]
check "AC2: add from the hidden prompt" [ "$(kc alpha)" = "$V1" ]
check "AC2: add from the clipboard" [ "$(kc beta)" = "$VC" ]
check "AC2: ... which clears the clipboard" [ -z "$(clip)" ]
check "AC2: add by generating a value" [ ${#GEN} -ge 24 ]
check "AC2: the list shows name, kind and used-by" eval 'has "$OUT" alpha && has "$OUT" api-key && has "$OUT" agents && has "$OUT" gamma'

t_tty "expect q quit" "send \r" "expect copied alpha" "send q" -- @ vault
check "AC2: enter copies the selected entry" [ "$(clip)" = "$V1" ]
t_tty "expect q quit" "send j" "send \r" "expect copied beta" "send \033[A" "send \033[B" "send \033[B" "send \r" "expect copied gamma" "send q" -- @ vault
check "AC2: moving down (j, arrows) and copying" [ "$(clip)" = "$GEN" ]

t_tty "expect q quit" "send n" "expect note for alpha" "send rotate it in the console\n" "expect note saved" "send q" -- @ vault
t_tty "expect q quit" "send q" -- @ vault
check "AC2: a note is saved and shown" eval 'has "$OUT" "rotate it in the console"'

t_tty "expect q quit" "send /" "expect search: " "send gam\n" "expect search: gam" "sleep 0.3" "snap $T/run/search" "send q" -- @ vault
S="$(screen_of "$T/run/search")"
check "search filters the list" eval 'has "$S" gamma && hasnt "$S" alpha && hasnt "$S" beta'

t_tty "expect q quit" "send j" "send d" "expect type the name" "send alpha\n" "expect not confirmed" "send q" -- @ vault
check "AC2: delete refuses a different typed name" [ "$(kc beta)" = "$VC" ]
t_tty "expect q quit" "send j" "send d" "expect type the name" "send beta\n" "expect forgot beta" "send q" -- @ vault
check "AC2: delete after typing the name" eval '[ -z "$(kc beta)" ] && [ ! -e "$T/state/keychain/ade-secrets/beta" ]'

# ---- AC3: rotation with the provider's live test (value on stdin; its output never on screen)
cat > "$T/bin/provider-test" <<'EOF'
#!/bin/bash
v="$(cat)"; { printf 'CALL provider-test argv=%s stdin-bytes=%s\n' "$*" "${#v}"; env | sed 's/^/  env /'; } >> "$FAKE_LOG"
case "$v" in good-*) exit 0 ;; *) echo "provider says no to $v"; exit 1 ;; esac
EOF
chmod +x "$T/bin/provider-test"
t_tty "expect q quit" "send t" "expect live test for alpha" "send provider-test\n" "expect live test saved" \
  "send r" "expect value from" "send p" "expect value for alpha" "sleep 0.2" "send $BAD\n" "expect run the live test" "send y" \
  "expect failed" "send q" -- @ vault
check "AC3: a new value that fails the live test is not stored" [ "$(kc alpha)" = "$V1" ]
check "AC3: ... the vault says the old value is kept" eval 'has "$OUT" "old value is kept"'
check "AC3: the live test got the value on stdin" grep -q "^CALL provider-test argv= stdin-bytes=${#BAD}" "$T/state/calls.log"
t_tty "expect q quit" "send r" "expect value from" "send p" "expect value for alpha" "sleep 0.2" "send $GOOD\n" \
  "expect run the live test" "send y" "expect rotated alpha" "send q" -- @ vault
check "AC3: a new value that passes replaces the old one" [ "$(kc alpha)" = "$GOOD" ]
old="$(kc gamma)"
t_tty "expect q quit" "send j" "send r" "expect value from" "send g" "expect no live test" "send n" "expect old value is kept" "send q" -- @ vault
check "AC3: without a live test, rotation asks first and keeps the old value on no" [ "$(kc gamma)" = "$old" ]
t_tty "expect q quit" "send j" "send r" "expect value from" "send g" "expect no live test" "send y" "expect rotated gamma" "send q" -- @ vault
check "AC3: ... and stores it untested on yes" eval '[ -n "$(kc gamma)" ] && [ "$(kc gamma)" != "$old" ]'
GEN2="$(kc gamma)"

# ---- AC4: rotation reminders
now="$(date +%s)"
awk -F'\t' -v OFS='\t' -v t=$((now - 100 * 86400)) '$1 == "alpha" { $6 = t } { print }' "$STORE/meta" > "$T/meta" && cat "$T/meta" > "$STORE/meta"
t_tty "expect q quit" "send q" -- @ vault
check "AC4: a key past 90 days is flagged" eval 'has "$OUT" "past 90 days: alpha" && printf "%s\n" "$OUT" | grep -q "alpha.*100d.*rotate!"'
check "AC4: a fresh key is not" eval '! printf "%s\n" "$OUT" | grep -q "gamma.*rotate!"'
EXTRA_ENV=(ADE_SECRETS_ROTATE_DAYS=200)
t_tty "expect q quit" "send q" -- @ vault
check "AC4: the rotation age is configurable" eval 'hasnt "$OUT" "rotate!"'
EXTRA_ENV=()

# ---- AC1: no fixture value ever reached the screen, an argv, the environment or a file outside the store
for v in "$V1" "$VC" "$BAD" "$GOOD" "$GEN" "$GEN2"; do
  check "AC1: no value on any screen, argv, environment or file (${v:0:12}...)" no_leak "$v"
done
t_tty "expect q quit" "send v" "expect reveal is off" "send q" -- @ vault
check "AC1: reveal is off by default" eval 'hasnt "$OUT" "$GOOD"'
EXTRA_ENV=(ADE_SECRETS_REVEAL=on)
t_tty "expect q quit" "send v" "expect for 10 s" "send n" "expect not shown" "send q" -- @ vault
check "AC1: reveal asks first, and no means no" eval 'hasnt "$OUT" "$GOOD"'
t_tty "expect q quit" "send v" "expect for 10 s" "sleep 0.2" "snap $T/run/before" "send y" "expect $GOOD" "snap $T/run/shown" \
  "sleep 11" "snap $T/run/after" "send q" -- @ vault
check "AC1: nothing shown before the confirmation" eval 'hasnt "$(cat "$T/run/before")" "$GOOD"'
check "AC1: confirmed, the value is shown" eval 'has "$(screen_of "$T/run/shown")" "$GOOD"'
check "AC1: ... and gone from the screen after 10 s" eval 'hasnt "$(screen_of "$T/run/after")" "$GOOD" && has "$(screen_of "$T/run/after")" "q quit"'
# the raw stream, in order: the alternate screen is on before the value is drawn, and the scrollback is cleared after
check "AC1: the alternate screen (?1049h) comes before the value, a scrollback clear (3J) after it" python3 -c '
import sys; d = open(sys.argv[1], "rb").read(); v = sys.argv[2].encode(); i = d.find(v)
sys.exit(0 if i > 0 and 0 <= d.find(b"\x1b[?1049h") < i and d.find(b"\x1b[3J", i + len(v)) > i else 1)' "$T/run/out.$T_N" "$GOOD"
EXTRA_ENV=()
t_cleanup

# ---- lock and unlock (age store)
t_setup; STORE_KIND=age CLIP_KIND=xclip
t_unlock
t_set alpha "$V1"
t_tty "expect q quit" "send u" "expect Enter passphrase" "sleep 0.1" "send $AGE_PW\n" "expect unlocked in this vault" \
  "send \r" "expect copied alpha" "send l" "expect locked: " "send q" -- @ vault
check "lock and unlock in the vault" eval '[ "$RC" = 0 ] && [ "$(clip)" = "$V1" ]'
check "the age vault leaks nothing" no_leak "$V1"
t_done
