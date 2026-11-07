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

## Privacy

Only the install target (package names or a repository URL) is sent to alalanet, never your code or
files. Verdicts are signed into alalanet's public transparency log without any information about who
asked. If alalanet does not answer within 8 seconds, the hook stays silent and your normal permission
flow applies. Set `ALALANET_API` to use another endpoint.

License: MIT-0. Contact: info@alalanet.com
