#!/bin/bash
# S1 AC5: `copy` clears after N s only if unchanged; macOS concealed marker set; over SSH without a clipboard it refuses.
. "$(dirname "$0")/lib.sh"
V1='fixture-value-copy-1'
t_setup; STORE_KIND=keychain CLIP_KIND=xclip
t_set alpha "$V1"

t_tty -- @ copy alpha --for 1
check "copy --for 1 puts the value on the clipboard" [ "$(clip)" = "$V1" ]
sleep 3
check "... and clears it after 1 s" [ -z "$(clip)" ]

t_tty -- @ copy alpha --for 1
clip_put 'fixture-user-copied-this'
sleep 3
check "copy leaves the clipboard alone when it changed since" [ "$(clip)" = 'fixture-user-copied-this' ]

t_tty -- @ copy alpha --for 0
check "copy refuses a bad --for" [ "$RC" = 2 ]
t_tty -- @ copy alpha --for x
check "copy refuses a non-number --for" [ "$RC" = 2 ]

for k in xsel wayland; do
  CLIP_KIND=$k; clip_put ''
  t_tty -- @ copy alpha --for 1
  check "copy works with $k" [ "$RC" = 0 -a "$(clip)" = "$V1" ]
  sleep 3
  check "... and $k clears" [ -z "$(clip)" ]
done

CLIP_KIND=macos; clip_put ''
t_tty -- @ copy alpha --for 30
check "macOS: copy puts the value on the pasteboard" [ "$RC" = 0 -a "$(clip)" = "$V1" ]
check "macOS: the concealed marker is set" [ -f "$T/state/clipboard.concealed" ]
check "macOS: the value went to osascript on stdin, not in its script" eval '! grep -q -F -- "$V1" "$T/state/calls.log"'
t_tty -- @ copy alpha --for 1
check "macOS: copy --for 1 puts it on the pasteboard" [ "$(clip)" = "$V1" ]
sleep 3
check "macOS: ... and the timed clear empties the pasteboard and drops the marker" eval '[ -z "$(clip)" ] && [ ! -f "$T/state/clipboard.concealed" ]'

clip_put 'fixture-untouched'; : > "$T/state/calls.log"
for k in macos xclip; do
  CLIP_KIND=$k EXTRA_ENV=(SSH_CONNECTION="192.0.2.1 50000 192.0.2.2 22" SSH_TTY=/dev/ttys009)
  t_tty -- @ copy alpha --for 30
  check "over SSH without a clipboard copy refuses ($k)" eval '[ "$RC" = 4 ] && has "$OUT" SSH'
done
check "... before reading the value or touching the clipboard" eval '[ "$(clip)" = fixture-untouched ] && ! grep -q "^CALL security" "$T/state/calls.log"'
CLIP_KIND= EXTRA_ENV=(SSH_CONNECTION="192.0.2.1 50000 192.0.2.2 22")
t_tty -- @ copy alpha --for 30
check "over SSH with no clipboard tool chosen copy refuses" [ "$RC" = 4 ]
EXTRA_ENV=() CLIP_KIND=xclip
t_tty -- @ copy alpha
check "copy defaults to clearing after 10 s (last: its clearer outlives the test)" eval '[ "$RC" = 0 ] && has "$OUT" "10 s"'
check "nothing leaked" no_leak "$V1"
t_done
