#!/bin/bash
# Review fixes: the store folders are private (refused when a symlink, not the user's, or not mode 700); names that
# differ only in case are refused (pass and age keep a file per name, and macOS paths ignore case); the script runs
# as `bash -p` with its options reset, so an exported function, BASH_ENV or SHELLOPTS cannot reach a value, and the
# guards call /bin/ps by path.
. "$(dirname "$0")/lib.sh"

# ---- private folders
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
mkdir -p "$T/elsewhere"; chmod 700 "$T/elsewhere"; ln -s "$T/elsewhere" "$STORE"
t_set alpha 'fixture-value-hard-1'
check "a symlinked store folder is refused" eval '[ "$RC" = 1 ] && has "$OUT" symlink && [ -z "$(ls -A "$T/elsewhere")" ]'
rm "$STORE"; mkdir "$STORE"; chmod 755 "$STORE"
t_tty -- @ list
check "a store folder that is not mode 700 is refused" eval '[ "$RC" = 1 ] && has "$OUT" 700 && [ "$(ls -ld "$STORE" | cut -c1-10)" = drwxr-xr-x ]'
chmod 700 "$STORE"
t_set alpha 'fixture-value-hard-1'
check "a private store folder works" [ "$RC" = 0 ]
t_cleanup
t_setup; STORE_KIND=age CLIP_KIND=xclip
mkdir -m 700 "$STORE" "$T/elsewhere"; ln -s "$T/elsewhere" "$STORE/age"
t_unlock
check "a symlinked age folder is refused" eval '[ "$RC" = 1 ] && has "$OUT" symlink && [ -z "$(ls -A "$T/elsewhere")" ]'
rm "$STORE/age"; mkdir -m 755 "$STORE/age"
t_unlock
check "an age folder that is not mode 700 is refused" eval '[ "$RC" = 1 ] && has "$OUT" 700'
t_cleanup
# (a folder owned by another user cannot be made without root; the check is `[ -O dir ]`)

# ---- names that differ only in case (macOS temp folders are case-insensitive, so there this runs on such a path)
for kind in keychain pass age; do
  t_setup; STORE_KIND=$kind CLIP_KIND=xclip
  [ $kind = age ] && t_unlock
  t_set alpha 'fixture-value-case-1'
  t_set Alpha 'fixture-value-case-2'
  check "$kind: a name equal to an existing one ignoring case is refused" eval '[ "$RC" = 2 ] && has "$OUT" alpha'
  t_tty -- @ list --names
  check "$kind: ... and only the first exists" [ "$OUT" = alpha ]
  t_copy alpha --for 30
  check "$kind: ... with its value intact (on a case-insensitive path too)" [ "$(clip)" = fixture-value-case-1 ]
  t_set alpha 'fixture-value-case-3'
  check "$kind: the same name, same case, still replaces" [ "$RC" = 0 ]
  t_cleanup
done

# ---- bash -p and the option reset
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
printf 'set -x\nprintf() { builtin printf "%%s" "$*" >> "%s/leak.bashenv"; builtin printf "$@"; }\n' "$T" > "$T/input/bashenv"
EXTRA_ENV=("BASH_FUNC_printf%%=() { builtin printf '%s' \"\$*\" >> $T/leak.func; builtin printf \"\$@\"; }" "BASH_ENV=$T/input/bashenv" SHELLOPTS=xtrace:allexport)
t_notty -- /bin/bash -c 'printf "%s" fixture-value-p-0 >/dev/null'
check "-p: the hostile environment does reach a plain /bin/bash (so the checks below can fail)" eval 'grep -q -F fixture-value-p-0 "$T/leak.bashenv"'
rm -f "$T/leak.func" "$T/leak.bashenv"
t_set alpha 'fixture-value-p-1'
check "-p: set works with a hostile environment" [ "$RC" = 0 ]
t_copy alpha --for 30
check "-p: copy works with a hostile environment" [ "$RC" = 0 -a "$(clip)" = fixture-value-p-1 ]
# (the bash fakes on PATH do import the function and run BASH_ENV; what matters is that ade-secrets does not, so the
# checks look for the value, which only ade-secrets' own printf ever handles)
check "-p: an exported printf function is not imported" eval '! grep -q -F fixture-value-p-1 "$T/leak.func" 2>/dev/null'
check "-p: BASH_ENV is not run" eval '! grep -q -F fixture-value-p-1 "$T/leak.bashenv" 2>/dev/null'
check "-p: SHELLOPTS=xtrace traces nothing (no value on screen)" eval 'hasnt "$OUT" "+ " && no_leak fixture-value-p-1'
check "-p: SHELLOPTS=allexport exports no value to the tools" eval '! grep -q -F fixture-value-p-1 "$T/state/calls.log"'
rm -f "$T/leak.func" "$T/leak.bashenv"; clip_put ''
t_tty -- /bin/bash "$BIN" copy alpha --for 30
check "-p: started as 'bash ade-secrets', it starts again as bash -p" eval '[ "$RC" = 0 ] && [ "$(clip)" = fixture-value-p-1 ] && no_leak fixture-value-p-1'
EXTRA_ENV=("BASH_FUNC_ps%%=() { echo 1; }")
t_tty -- @claude @ list
check "a function named ps cannot hide a claude ancestor" [ "$RC" = 3 ]
EXTRA_ENV=()
check "the guards call ps by absolute path" eval 'grep -q "/bin/ps -o" "$BIN" && ! grep -E -q "(^|[^/])\\bps -o" "$BIN"'
check "the shebang is bash -p" [ "$(head -1 "$BIN")" = "#!/bin/bash -p" ]
t_done
