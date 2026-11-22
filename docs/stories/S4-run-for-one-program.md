# S4: `run`, a value for one program that is not Claude Code

Status: Ready for development once its facts are confirmed (2026-11-22). Risk: high (it widens who can be handed a
value). Depends on S3. Contract: `docs/contract-v2.md` (sections "`run`", "The delegation block v2", "The key helper
and the guards", "Residual risk (v2 additions)", "Owner check (v2 additions)", and "To confirm before building": items
C2, C4, C6, C7, C8). The contract wins over this story. Verification command: `bash tests/run.sh`.

## Why
The hub starts two programs that need a key and are not Claude Code: the Gemini CLI (its API key) and the Telegram
bot (its token). Under contract v1 the hub read those values itself, which the store refuses. `run` hands the value
to one recorded program and to nothing else.

## First step, before any code
Confirm C2, C4, C6, C7 and C8 from documentation and by harmless experiment, and write what was found into the
contract's checklist. If one of them does not hold, stop and report: the design may change.

## Acceptance criteria (fakes only)
| AC | Criterion | Test |
|---|---|---|
| 1 | `set <name> --run <program> --env VAR` and `--run <program> --stdin` record the program's real path and how the value is handed over; `--run` and `--helper` cannot both be set; `list` shows the mark, never the value | `run_mark` |
| 2 | `run <name> -- <program> [args]` starts exactly the recorded program (compared by real path) with the value in that one variable of that one process, or on its standard input, and nothing else changed; the value is in no argument list, no file and no output of `ade-secrets` | `run_hands_over` |
| 3 | Any other program, a path that resolves elsewhere, a symlink swapped after recording, or an entry without the mark is refused with the contract's exit code and one line; nothing is started | `run_refuses_other_programs` |
| 4 | `run` answers for a person's terminal and for a service (no terminal, no agent markers, no agent ancestor) and refuses inside an agent session, using the guards the contract names; each case is a test with a faked process tree | `run_guard` |
| 5 | A session of the Gemini CLI is treated as an agent session by every guard, in the way C4 confirms | `gemini_is_an_agent_context` |
| 6 | The age store refuses `run` (exit 5) and says why | `run_age_refused` |
| 7 | The delegation block v2 in the contract is run as written by a test with a fixture hub, for each call in its table | `block_v2_as_written` |
| 8 | "Residual risk" says plainly what `run` cannot do (keep a value from an agent that has the shell and can start the recorded program) and what is still gained; "Owner check" gains the steps that can only be done by hand | `docs_residual_risk_v2` |
| 9 | A 0.3.0 tool that rewrites an entry drops the run mark; `run` then refuses loudly, never falling back to anything | `mark_lost_is_loud` |

## Out of scope
The release (S5). The hub adopting v2 (ade-brain H4).
