# alalanet guard

Your agent installs packages, MCP servers and skills all day. That is where it gets attacked:
malicious packages, typosquats of official MCP servers, package names a model invented that an
attacker registered, compromised versions after a maintainer change.

This plugin gives Claude the **install-guard** skill and the alalanet remote MCP server
(`https://alalanet.com/mcp`). Before an install, Claude calls alalanet's free `install_check` with what
it is about to install, and acts on the decision:

| Decision | What Claude does | Examples of reasons |
|---|---|---|
| block | does not install, tells you why | `known_malicious:MAL-…` (OSV) |
| hold | asks you first | `name_like_official`, `not_on_npm`, `runs_install_script`, `maintainers_changed`, `new_package`, `known_vulnerabilities` |
| allow | goes ahead | no known problem (the code itself is not read: pin versions) |

It covers packages and commands such as `npm i`, `npx`, `pnpm`/`yarn`/`bun add`, `bunx`, `pip`/`uv` install,
`uvx`, `pipx`, `claude mcp add … -- …`, `codex mcp add`, `skills add`, `clawhub install`, GitHub
repositories and MCP config entries.

The MCP server also offers `check_service` and `preflight_payment` before connecting to or paying an MCP
server or x402 endpoint, `payment_status` after a timeout, `verify_tools` to check that a server's tools
are the ones it serves everyone, and signed evidence when a paid call went wrong.

## Install

From Anthropic's directory, add **alalanet guard** on claude.ai. From GitHub:

```
/plugin install alalanet-guard --marketplace alalanet/skills
```

The directory build has no hooks. The GitHub build (branch `main`) also runs the check
automatically before every install command.

## Privacy

- Only the install target (package name, command or URL) is sent to alalanet, never your code, files
  or credentials. No account or key is needed.
- Verdicts (target, decision, reasons) are signed into alalanet's public transparency log, without
  anything about who asked.
- Full policy: https://alalanet.com/privacy

License: MIT-0. Contact: info@alalanet.com
