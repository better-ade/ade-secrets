# ade-secrets

A local-only key store and terminal vault for ADE: like a small 1Password that lives on your machine. It never runs
inside an agent session; the only programmatic read is Claude Code's own key helper. See `docs/stories/`.

```
export ADE_SECRETS_STORE=keychain        # or pass, or age; chosen once, never switched silently
ade-secrets set openai --helper          # hidden prompt (or --clipboard); --helper lets Claude Code's key helper read it
ade-secrets copy openai                  # to the clipboard, cleared after 20 s if unchanged
ade-secrets list | status | forget <name> | lock | unlock
```

In Claude Code's settings: `"apiKeyHelper": "ade-secrets helper openai"`. How a hub delegates, what tells the key
helper apart and the risk that remains: `docs/contract.md`. Verification: `bash tests/run.sh`.
