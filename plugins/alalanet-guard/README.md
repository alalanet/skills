# alalanet guard

Your agent installs packages, MCP servers, skills and editor extensions all day. That is where it gets
attacked: malicious packages, typosquats of official MCP servers, package names a model invented that an
attacker registered, compromised versions after a maintainer change.

This plugin gives Claude the **install-guard** skill and the alalanet guard remote MCP server
(`https://alalanet.com/mcp/guard`, seven read-only tools). Before an install, Claude calls alalanet's free
`install_check` with what it is about to install, and acts on the decision:

| Decision | What Claude does | Examples of reasons |
|---|---|---|
| block | does not install, tells you why | `known_malicious:MAL-…` (OSV) |
| hold | asks you first | `name_like_official`, `not_on_npm`, `runs_install_script`, `maintainers_changed`, `new_package`, `known_vulnerabilities` |
| allow | goes ahead | no known problem (the code itself is not read: pin versions) |

It covers packages and commands such as `npm i`, `npx`, `pnpm`/`yarn`/`bun add`, `bunx`, `pip`/`uv` install,
`uvx`, `pipx`, `claude mcp add … -- …`, `codex mcp add`, `skills add`, `clawhub install`,
`openclaw skills install`, IDE extension installs (`code`, `cursor`, `windsurf`, `codium --install-extension`),
GitHub repositories and skills, and MCP config entries. A line alalanet cannot read (a custom registry, a
git or URL source, several packages at once) is a hold, never a silent allow.

## The MCP server's tools

| Tool | When Claude uses it |
|---|---|
| `install_check` | before installing a package, repository, skill, extension or MCP server |
| `check_repo_config` | before opening a repository someone sent you: reads the configuration agents and editors load from it (MCP servers, hooks, editor tasks, permissions, instruction files) and runs nothing |
| `check_service` | before connecting to a remote MCP server: is it alive, did its tools change, do its tool descriptions look like hidden instructions |
| `connect_check` | before adding a remote MCP server to a client, or when it fails to connect: one live read and a verdict for each of ten clients (Claude Code, claude.ai, ChatGPT, Cursor, VS Code and others) |
| `verify_tools` | after connecting: are the tools you were served the ones the server serves everyone |
| `check_artifact` | who signed the skill file or release with this sha256 |
| `get_attestation` | the signed record of any result, with its proof in alalanet's public transparency log |

All seven only read. Free, no account.

## Install

From Anthropic's directory, add **alalanet guard** on claude.ai. From GitHub:

```
/plugin install alalanet-guard --marketplace alalanet/skills
```

(older Claude Code: `/plugin marketplace add alalanet/skills`, then `/plugin install alalanet-guard@alalanet`.)

The directory build has no hooks: Claude runs the check because the skill tells it to. The GitHub build
(branch `main`) also runs it automatically, as a hook, before every install command.

## Privacy

- The skill sends only the install target (package name, command or URL) to alalanet, never your code,
  files or credentials. No account or key is needed.
- The other tools send what you pass them: a server URL, the tool list a server gave you, a file's
  sha256, a repository name. For a local or private checkout `check_repo_config` takes the agent
  configuration files themselves (path and content); the public record then holds only the decision,
  the files' sha256 and bare reason codes.
- Verdicts (target, decision, reasons) are signed into alalanet's public transparency log, without
  anything about who asked.
- Full policy: https://alalanet.com/privacy

License: MIT-0. Contact: info@alalanet.com
