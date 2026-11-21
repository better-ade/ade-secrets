#!/bin/bash
# S1 AC2: `list` never shows a value (output scan).
. "$(dirname "$0")/lib.sh"
for kind in keychain pass age; do
  t_setup; STORE_KIND=$kind CLIP_KIND=xclip
  [ $kind = age ] && t_unlock 'fixture-pass-phrase'
  t_set openai 'fixture-value-list-a1' --kind api-key --used-by agents
  t_set github 'fixture-value-list-b2' --kind token --used-by ci
  t_set plain 'fixture-value-list-c3'
  t_tty -- @ list
  check "$kind: list succeeds" [ "$RC" = 0 ]
  check "$kind: list shows names, kinds and used-by" eval 'has "$OUT" openai && has "$OUT" github && has "$OUT" api-key && has "$OUT" token && has "$OUT" agents && has "$OUT" ci'
  check "$kind: list shows an age column" eval 'has "$OUT" AGE'
  check "$kind: list never shows a value" eval 'hasnt "$OUT" fixture-value'
  t_tty -- @ list --names
  check "$kind: list --names prints the names only" [ "$OUT" = "$(printf 'github\nopenai\nplain')" ]
  t_tty -- @ status
  check "$kind: status never shows a value" eval '[ "$RC" = 0 ] && hasnt "$OUT" fixture-value'
  check "$kind: nothing leaked" eval 'no_leak fixture-value-list-a1 && no_leak fixture-value-list-b2'
  t_cleanup
done
t_done
