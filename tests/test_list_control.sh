#!/bin/bash
# S3 AC7 list_strips_control: `list` and `status` never print a control, direction-changing or invisible character
# from an entry's fields: a hostile `meta` (terminal escapes, C1 controls, bidi overrides, zero-width characters, a
# byte-order mark) is the test. meta's own checks (ownership, mode, symlink) still hold. The vault draws the same
# fields, so it is held to the same rule, and a hostile rotation time is never evaluated as shell arithmetic.
. "$(dirname "$0")/lib.sh"
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
T_TIMEOUT=60
t_set acme-ops.good-key fixture-value-ctl-1
# hostile lines, in the current store and in another one (report_left names those); every field carries something
python3 - "$STORE/meta" "$T/pwned" <<'EOF'
import sys, time
meta, pwned = sys.argv[1], sys.argv[2]
bad = ["\x1b]0;owned\x07", "\x1b[2J\x1b[31m", "\udc9b31m", "\u009b2J", "\u202e", "\u2066", "\u200f", "\u200b", "\u2060",
       "\ufeff", "\u00ad", "\x7f", "\r", "\x08", "\x00"]
t = str(int(time.time()) - 200 * 86400)
rows = []
for i, b in enumerate(bad):
    rows.append(["acme-ops.k%d%s" % (i, b), "keychain", "kind" + b, "used" + b, t, t + b, "yes" + b])
rows.append(["evil" + bad[0], "pass", "k" + bad[1], "u", t, t, "no"])
rows.append(["acme-ops.math", "keychain", "k", "u", t, "a[$(touch %s)]" % pwned, "no"])
with open(meta, "ab") as f:
    for r in rows:
        f.write(("\t".join(r) + "\n").encode("utf-8", "surrogateescape"))
EOF
# clean <file>: only printable ASCII, tabs and newlines (no control, direction-changing or invisible character)
clean() { python3 -c 'import sys; d = open(sys.argv[1], "rb").read(); sys.exit(any(not (32 <= c < 127 or c in (9, 10)) for c in d))' "$1"; }
for args in "list" "list --names" "list --due" "list --scope acme-ops" "list --names --scope acme-ops" "status"; do
  t_tty -- /bin/sh -c "'$BIN' $args > '$T/run/stdout' 2> '$T/run/stderr'"
  check "list_strips_control: $args: runs (exit 0)" [ "$RC" = 0 ]
  check "list_strips_control: $args: stdout has no control, direction-changing or invisible character" clean "$T/run/stdout"
  check "list_strips_control: $args: stderr neither" clean "$T/run/stderr"
done
t_tty -- /bin/sh -c "'$BIN' list > '$T/run/stdout'"
check "list_strips_control: the hostile entries still show (their characters replaced)" eval 'grep -q "k0?" "$T/run/stdout" && grep -q "acme-ops.*good-key" "$T/run/stdout"'
t_tty -- /bin/sh -c "'$BIN' status > '$T/run/stdout' 2>&1"
check "list_strips_control: status names the other store's entry without its escapes" eval 'clean "$T/run/stdout" && grep -q "evil?" "$T/run/stdout"'

# the vault: its own drawing uses escapes, so look for the hostile ones in the raw stream
t_tty "expect q quit" "sleep 0.3" "send q" -- @ vault
check "list_strips_control: the vault opens on a hostile meta" [ "$RC" = 0 ]
raw="$T/run/out.$T_N"
check "list_strips_control: the vault draws none of the hostile characters" python3 -c '
import sys
d = open(sys.argv[1], "rb").read()
bad = [b"\x1b]", b"\x07", b"\x1b[31m", b"\xc2\x9b", b"\x9b", b"\xe2\x80\xae", b"\xe2\x81\xa6", b"\xe2\x80\x8f", b"\xe2\x80\x8b",
       b"\xe2\x81\xa0", b"\xef\xbb\xbf", b"\xc2\xad", b"\x7f", b"\x08", b"\x00"]
sys.exit(any(b in d for b in bad))' "$raw"
check "list_strips_control: a hostile rotation time is never run as shell arithmetic" [ ! -e "$T/pwned" ]

# meta's own checks still hold for list and status
chmod 620 "$STORE/meta"
t_tty -- @ list
check "list_strips_control: a meta others can write is still refused by list" eval '[ "$RC" = 1 ] && has "$OUT" meta'
t_tty -- @ status
check "list_strips_control: ... and by status" eval '[ "$RC" = 1 ] && has "$OUT" meta'
chmod 600 "$STORE/meta"; mv "$STORE/meta" "$T/meta.real"; ln -s "$T/meta.real" "$STORE/meta"
t_tty -- @ list --due
check "list_strips_control: a symlinked meta is still refused" eval '[ "$RC" = 1 ] && has "$OUT" symlink'
check "list_strips_control: nothing leaked" eval 'no_leak fixture-value-ctl-1'
t_done
