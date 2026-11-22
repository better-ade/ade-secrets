# S3: per-hub keys, presence without a value, and keys due

Status: Ready for development (2026-11-22). Risk: high (secrets). Contract: `docs/contract-v2.md` (sections "Names and
scopes", "`set`: asking before a replace", "`has`: presence without a value", "Release files and version");
decision record `docs/decisions/0001-contract-v2.md`. Where this story and the contract differ, the contract wins:
stop and say so. Verification command: `bash tests/run.sh`.

## Why
A review of the hub's side (ade-brain H2, 2026-11-22) found that one entry per name for the whole machine lets one
customer's key silently replace another's, that the hub cannot ask "is there a key named X" from a job or a session,
and that ade-cli has no names-only way to learn which keys are due for rotation. This story adds those three things
and nothing that hands out a value.

## Acceptance criteria (fakes only; never the real Keychain, `pass`, `gpg`, `age` or clipboard)
| AC | Criterion | Test |
|---|---|---|
| 1 | A name may carry a scope, `<scope>.<key>`, with the contract's rules for each part; every command accepts it; a name that breaks the rules is refused before the store is touched | `scope_names` |
| 2 | `list` and the vault show a SCOPE column and can be limited to one scope; entries made by 0.3.0 show an empty scope and are left exactly as they are | `scope_list_and_vault` |
| 3 | `set` on a name that exists asks before replacing, at the terminal, and says which entry (scope and key, never a value); no answer or a no changes nothing; a new name is stored as before | `set_asks_before_replace` |
| 4 | `has <name>` prints nothing and exits 0 when the entry exists, 1 when it does not; it answers without a terminal and inside an agent session; it never reads a value and, on macOS, never raises a dialog (it reads the tool's own record of names, as the contract says) | `has_presence_only` |
| 5 | Every other exit of `has` (no store chosen, a locked age store, a bad name) is the contract's code with one line on stderr | `has_other_exits` |
| 6 | `list --due [--scope S]` prints one name per line for entries older than the rotation age (`ADE_SECRETS_ROTATE_DAYS`, default 90) and nothing else; it is guarded like `list` | `list_due_names_only` |
| 7 | `list` and `status` never print a control, direction-changing or invisible character from an entry's fields (a hostile `meta` file is the test) | `list_strips_control` |
| 8 | The tool's version is written in the script itself and printed by `--version` without reading another file | `version_in_script` |
| 9 | Every v1 call in `docs/contract.md` still behaves as its table says (the existing contract test passes unchanged) | `v1_unchanged` |
| 10 | `docs/contract-v2.md`'s tables for these commands are run as written by a test, so the document and the behaviour agree | `contract_v2_tables` |

## Out of scope
`run` and its mark (S4). The release (S5). Anything in ade-brain or ade-cli.
