# ade-secrets

A local-only key store and terminal vault for ADE: like a small 1Password that lives on your machine. It never runs
inside an agent session; the only programmatic read is Claude Code's own key helper, and an entry set `--helper` is
readable by Claude Code and anything it runs. See `docs/stories/`.

Install (macOS or Linux; Bash 3.2 or later, plus `pass` or `age` if you use that store), the latest release:

```
git clone --branch v0.3.1 https://github.com/better-ade/ade-secrets ~/ade-secrets
ln -s ~/ade-secrets/bin/ade-secrets ~/.local/bin/ade-secrets   # any folder on your PATH
ade-secrets version                                            # 0.3.1
```

```
export ADE_SECRETS_STORE=keychain        # or pass, or age; recorded by the first set, switched only by `ade-secrets store`
ade-secrets set openai --helper          # hidden prompt (or --clipboard); --helper lets Claude Code's key helper read it
ade-secrets copy openai                  # to the clipboard, cleared after 10 s if unchanged (--for N)
ade-secrets list [--names] | status | forget <name> | store [keychain|pass|age] | lock | unlock
ade-secrets vault                        full screen: search, add, copy, rotate (live test), notes, reminders
```

In Claude Code's settings: `"apiKeyHelper": "ade-secrets helper openai"`. How a hub delegates, what tells the key
helper apart, the risk that remains and the owner's manual checks: `docs/contract.md`; Claude Code permission rules to
merge into your settings: `docs/claude-settings.json`. Verification: `bash tests/run.sh`.

Where it fits: [ade](https://github.com/better-ade/ade-cli) is the command, [ade-brain](https://github.com/better-ade/ade-brain)
the hub, [ade-method](https://github.com/better-ade/ade-method) the rules, [ade-skills](https://github.com/better-ade/ade-skills)
the skills, ade-secrets (this repo) the keys, [ade-terminal](https://github.com/better-ade/ade-terminal) the desktop
app, and [ade-computer](https://github.com/better-ade/ade-computer) an isolated desktop to run it in. More at
[ade.ardata.tech](https://ade.ardata.tech/).
