# alalanet guard

Your agent installs packages, MCP servers and skills all day. That is where it gets attacked:
malicious packages, typosquats of official MCP servers, package names a model invented that an
attacker registered, compromised versions after a maintainer change.

This plugin checks every install before it runs, with [alalanet](https://alalanet.com)'s free `install_check`:

| Decision | What the hook does | Examples of reasons |
|---|---|---|
| block | denies the command | `known_malicious:MAL-…` (OSV) |
| hold | asks you first | `name_like_official`, `not_on_npm`, `runs_install_script`, `maintainers_changed`, `new_package`, `known_vulnerabilities` |
| allow | stays silent | no known problem (the code itself is not read: pin versions) |

Covered commands: `npm i`, `npx`, `pnpm`/`yarn`/`bun add`, `bunx`, `pip`/`uv` install, `uvx`, `pipx`,
`claude mcp add … -- …`, `codex mcp add`, `skills add`, `clawhub install`.

The plugin also adds the alalanet remote MCP server (`https://alalanet.com/mcp`): `install_check`,
`check_service` and `preflight_payment` before connecting to or paying an MCP server or x402 endpoint,
`payment_status` after a timeout, signed evidence when a paid call went wrong.

## Install

```
/plugin install alalanet-guard --marketplace alalanet/skills
```

## How it works

The plugin declares HTTP `PreToolUse` hooks with `if` rules (`Bash(npm install *)`, `Bash(npx *)`,
`Bash(pip install *)`, `Bash(uvx *)`, `Bash(claude mcp add *)`, `Bash(skills add *)` and the other
install commands above). Claude Code itself decides which commands match. It sends only matching
commands to `https://alalanet.com/v1/hooks/claude-code` and never sends your other Bash commands.
There is no local script, and no Node.js or Python is needed.

alalanet answers in the standard hook format: `deny` on block, `ask` on hold, and an empty answer on
allow. If alalanet does not answer within 20 seconds, or answers with an error, the hook does
nothing and your normal permission flow applies.

## Privacy

- Claude Code sends the standard hook input for a matching command: the command line plus its usual
  hook fields (session id, working directory, transcript path).
- alalanet reads only `tool_name` and the command. It extracts the package names or repository URLs
  and checks them. It does not store or log the command line or the other fields.
- No code, files or credentials are sent, and no account or key is needed.
- Verdicts (target, decision, reasons) are signed into alalanet's public transparency log, without
  anything about who asked.
- Full policy: https://alalanet.com/privacy

License: MIT-0. Contact: info@alalanet.com
