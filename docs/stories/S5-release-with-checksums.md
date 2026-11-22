# S5: release 0.4.0 with its files and their checksums

Status: Ready for development (2026-11-22). Risk: medium. Depends on S3 and S4. Contract: `docs/contract-v2.md`,
"Release files and version"; "To confirm" item C10. Verification command: `bash tests/run.sh`.

## Acceptance criteria
| AC | Criterion | Test |
|---|---|---|
| 1 | The release workflow publishes `ade-secrets` and `vault.sh` as release files, and `release.json` names each with its sha256, in the form ade-cli reads (confirm C10 against the shared workflow and ade-cli's reader first) | `release_assets_listed` |
| 2 | A test fails when a file the tool needs at run time is not among the release files | `release_assets_complete` |
| 3 | `VERSION` is 0.4.0, the script's own version line matches it, and the changelog's 0.4.0 section says what contract v2 adds and what a 0.3.0 user must know | `release_version_and_notes` |
| 4 | README and `docs/contract-v2.md` say how the tool is installed from release files and checked | `release_docs` |
