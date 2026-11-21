# S2: `ade-secrets vault`: the terminal interface

Status: Ready for development (2026-11-21). Risk: high. Depends on S1. Was ade-cli A14 (moved here; ade-cli's
`ade vault` just opens this in the user's terminal).

## Goal
A full-screen terminal vault: list and search (name, kind, used-by, last rotated; never values); add by clipboard,
hidden prompt or generate; copy (↵) via S1; rotate with the provider's live test (keep the old value until the new one
passes); opt-in timed reveal (off by default, 10 s, confirm first); notes; typed-name delete; rotation reminders
(default 90 days); lock/unlock. Local only, same rules as S1.

## Acceptance criteria (driven through tmux send-keys / capture-pane)
| AC | Criterion |
|---|---|
| 1 | No fixture value ever appears on screen (capture scan), unless reveal is enabled and confirmed, then gone after 10 s |
| 2 | Add (all three ways), copy, rotate, delete and notes work through S1's stdin-only paths |
| 3 | Rotation keeps the old value when the live test fails |
| 4 | Reminders show for keys past the rotation age |
| 5 | Inside an agent context the vault refuses to open |
