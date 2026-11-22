# S3 design note: scopes, `has`, ask before a replace, `list --due`, the version in the script

Story: `docs/stories/S3-scopes-has-and-due.md`. Contract: `docs/contract-v2.md`. Risk: high (secrets).

## Names
- `valid_name` keeps v1's rule and, for a name with a `.`, checks the scope (text before the first `.`) against
  `^[a-z0-9][a-z0-9-]{0,39}$` and requires the key to start with a letter or digit. It runs before any store call;
  v1's case rule (`same_but_case`) is unchanged.
- The stores keep the full name flat: Keychain account `<scope>.<key>` (service `ade-secrets`), pass entry
  `ade-secrets/<scope>.<key>` (file `<scope>.<key>.gpg`), age file `entries/<scope>.<key>.age`. No folder per scope,
  so an entry named `acme-ops` and `acme-ops.key` are two files, and the fixed suffixes keep `x` and `x.age` apart.

## `has`
- Not behind `guard_local`; the start-up check at the top of the script still runs. Checks: `private_dir`,
  `private_meta`, `pick_store quiet` (2 for no store or a mismatch), a valid name (2), the age store created (5),
  meta lists the exact name in the current store (else 1, silent), then the store's record of the item without a
  value: `security find-generic-password` without `-w`, the `.gpg` file under `${PASSWORD_STORE_DIR:-~/.password-store}`,
  the age file. Meta without the item: 1 with the contract's line. Other failures keep v1's exit 1 with one line.
- One exact name: awk `==` on meta, exact paths; no listing, glob or prefix.

## `set`
- With a meta entry in the current store, `read_line` asks `replace <name> (rotated <age> ago)? [y/N] ` after the
  clipboard trap (so a no still clears a clipboard value) and before `need_open`. Only `y` goes on. `--plain` is
  `--no-helper`.

## `list`, `status`, the vault
- `meta_clean` (`tr -c '\t\n -~' '?'`, C locale) is the only way meta reaches the screen: `list` (every mode),
  `meta_names` (so `status` and `report_left`), `same_but_case`, the vault's rows. The vault treats a non-numeric
  rotation time as 0 (it used to reach bash arithmetic, which runs `$(...)` in an array subscript).
- `list --due` is computed in awk from the rotation field; `rotate_days` is the vault's rule.

## Version
- `ADE_SECRETS_VERSION=0.3.0` (equal to `VERSION`; S5 raises both). `--version` prints the variable.

## Tests
`tests/test_scopes.sh` (AC1, AC2), `test_set_replace.sh` (AC3), `test_has.sh` (AC4, AC5), `test_due.sh` (AC6),
`test_list_control.sh` (AC7), `test_version.sh` (AC8), `test_contract_v2.sh` (AC9, AC10). `tests/lib.sh`'s `t_set`
answers `y` when it replaces an entry; the fake `pass` also writes the `.gpg` file the real one keeps.
