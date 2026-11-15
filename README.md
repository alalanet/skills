# alalanet skills

Agent Skills and the `alalanet-guard` plugins for Claude Code, Cursor, GitHub Copilot (CLI and VS Code) and Codex by [alalanet.com](https://alalanet.com), a free trust layer for AI agents: check before your agent installs, connects or pays.

| Skill | What it does |
|---|---|
| [`install-guard`](skills/install-guard/SKILL.md) | Before installing any npm/PyPI package, GitHub repo, skill or MCP server, check it with alalanet `install_check`: blocks known malicious packages, holds typosquats of official MCP servers, names that do not exist, install scripts and maintainer changes. Free, no sign-up. |
| [`alalanet-check-before-you-pay`](skills/alalanet-check-before-you-pay/SKILL.md) | Before paying an x402 endpoint or connecting to a remote MCP server, check that it is alive, that its price and payment address match its listing, and find working alternatives. Free, no sign-up. |

## Claude Code plugin: check every install automatically

```
/plugin install alalanet-guard --marketplace alalanet/skills
```

(older Claude Code: `/plugin marketplace add alalanet/skills`, then `/plugin install alalanet-guard@alalanet`.)

The plugin adds HTTP hooks that run before the install commands an agent is about to execute
(`npm i`, `npx`, `bunx`, `pnpm`/`yarn`/`bun add`, `pip`/`uv` install, `uvx`, `pipx`, `claude mcp add`,
`codex mcp add`, `skills add`, `clawhub install`, `openclaw skills install`, and IDE extension installs: `code`, `cursor`, `windsurf`, `codium --install-extension`). **block** denies the command, **hold** asks you,
and **allow** stays silent. It also adds the alalanet remote MCP server (`https://alalanet.com/mcp`: the eight
checks before installing, connecting and paying).

Claude Code itself matches the commands: only matching install commands are sent to alalanet, never
your other commands, code or files. alalanet reads only the package names or repository URL in them.
If alalanet does not answer within 20 seconds, the hook does nothing.
Source: [plugins/alalanet-guard](plugins/alalanet-guard).

## GitHub Copilot CLI, VS Code and Codex

`plugins/alalanet-guard` is also an [Agent Plugins](https://agent-plugins.org) 1.0.0 package. In these runtimes the
check runs in `alalanet-agent`, alalanet's open-source client: install it first and put it on `PATH`
(https://alalanet.com/dl, or `go install github.com/alalanet/alalanet-agent/cmd/alalanet-agent@latest`).

| Runtime | Install |
|---|---|
| Copilot CLI | `copilot plugin marketplace add alalanet/skills`, then `copilot plugin install alalanet-guard@alalanet` |
| VS Code | [Install in VS Code](https://vscode.dev/redirect?url=vscode%3A%2F%2Fchat-plugin%2Finstall%3Fsource%3Dalalanet%252Fskills%26plugin%3Dalalanet-guard), or add the marketplace `alalanet/skills` in the Agent Customizations editor |
| Codex | `codex plugin marketplace add alalanet/skills`, then `codex plugin add alalanet-guard@alalanet`; trust the hook once in `/hooks` |

Before each shell command the hook runs `alalanet-agent hook copilot` (or `hook codex`), which sends the command line
to alalanet only when it installs or runs a package, and never your other commands, files or session. Block denies
the command, hold asks you (Codex: denies with a note to confirm with you). The hook runs only an `alalanet-agent`
from an absolute `PATH` folder, never one from the repository the agent works in. Without a usable one it checks
nothing and says so in one line, and the command goes ahead as without the plugin. The plugin also adds
the read-only MCP server `https://alalanet.com/mcp/guard`. Details: [plugins/alalanet-guard](plugins/alalanet-guard#github-copilot-cli-vs-code-and-codex).

## Cursor plugin

The same check in Cursor: a `beforeShellExecution` hook (a small `sh` script on macOS and Linux, PowerShell on
Windows; nothing to install) that sends a command line to alalanet only when it names a package manager or
installer (npm, npx, pip, uv, claude mcp, … the list is in the plugin's README), denies on block and on hold with
the reason, and lets the command go ahead unchecked if alalanet does not answer within 20 seconds
(`ALALANET_FAIL_CLOSED=1` holds it instead). It also connects Cursor to alalanet's read-only MCP server
`https://alalanet.com/mcp/guard`. Source and details: [plugins/alalanet-guard-cursor](plugins/alalanet-guard-cursor);
Cursor reads it through [.cursor-plugin/marketplace.json](.cursor-plugin/marketplace.json).

## Install the skills

```sh
npx skills add alalanet/skills
```

Or copy a skill's folder (`skills/install-guard/` or `skills/alalanet-check-before-you-pay/`) into your
agent's skills folder. Both skills are also served at
<https://alalanet.com/.well-known/agent-skills/index.json> (Agent Skills discovery).

## Verify before you install

Every version of a skill is a release signed by the alalanet server key and appended to a public
transparency log. Check the file you got:

```sh
sha256sum skills/install-guard/SKILL.md    # or skills/alalanet-check-before-you-pay/SKILL.md
curl -s https://alalanet.com/v1/artifacts/<sha256>    # advice: signed_by_alalanet
```

Anything else (`unknown_hash`, a different publisher, `caution_conflicting`) means the file is not ours. The repository always holds the latest signed versions; the live copies are listed in the discovery index above.

## Tests

`node --test tests/agent-plugin.test.mjs` (Node.js 20 or later, no dependencies) checks the Agent Plugins package: `plugin.json` and
`mcp.json` against the Agent Plugins 1.0.0 schemas (fetched from agent-plugins.org, or read from the folder
`AGENT_PLUGINS_SCHEMAS` names), the Copilot and Codex hook files, the marketplaces, and the hook commands under
every POSIX shell it finds (and PowerShell when `pwsh` is installed): with `alalanet-agent` on `PATH`, without it,
not executable, and only in the current folder or a relative `PATH` entry (never run). The Windows `commandWindows`
form is checked for its PATH-only markers; it is not run.

## License

MIT-0.
