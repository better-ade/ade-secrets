# ade-secrets

A local-only key store and terminal vault for ADE: like a small 1Password that lives on your machine. It never runs
inside an agent session; the only programmatic read is Claude Code's own key helper, and an entry set `--helper` is
readable by Claude Code and anything it runs. See `docs/stories/`.

```
export ADE_SECRETS_STORE=keychain        # or pass, or age; recorded by the first set, switched only by `ade-secrets store`
ade-secrets set openai --helper          # hidden prompt (or --clipboard); --helper lets Claude Code's key helper read it
ade-secrets copy openai                  # to the clipboard, cleared after 10 s if unchanged
ade-secrets list | status | forget <name> | store [<name>] | unlock
```

In Claude Code's settings: `"apiKeyHelper": "ade-secrets helper openai"`. How a hub delegates, what tells the key
helper apart, the risk that remains and the owner's manual checks: `docs/contract.md`; Claude Code permission rules to
merge into your settings: `docs/claude-settings.json`. Verification: `bash tests/run.sh`.
