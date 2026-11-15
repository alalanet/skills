# alalanet guard

Your agent installs packages, MCP servers and skills all day. That is where it gets attacked:
malicious packages, typosquats of official MCP servers, package names a model invented that an
attacker registered, compromised versions after a maintainer change.

This plugin checks every install before it runs, with [alalanet](https://alalanet.com)'s free `install_check`:

| Decision | What the hook does | Examples of reasons |
|---|---|---|
| block | denies the command | `known_malicious:MAL-…` (OSV) |
| hold | asks you first (Codex cannot pause a command: it denies, with a note to confirm with you) | `name_like_official`, `not_on_npm`, `runs_install_script`, `maintainers_changed`, `new_package`, `known_vulnerabilities` |
| allow | stays silent | no known problem (the code itself is not read: pin versions) |

Covered commands: `npm i`, `npx`, `pnpm`/`yarn`/`bun add`, `bunx`, `pip`/`uv` install, `uvx`, `pipx`,
`claude mcp add … -- …`, `codex mcp add`, `skills add`, `clawhub install`, `openclaw skills install`, and IDE
extension installs (`code`, `cursor`, `windsurf`, `codium --install-extension`).

One folder serves several runtimes; each reads only its own files:

| Runtime | Install | The check runs in | MCP server added |
|---|---|---|---|
| Claude Code | `/plugin install alalanet-guard --marketplace alalanet/skills` | Claude Code itself (HTTP hook, nothing to install) | `https://alalanet.com/mcp` |
| GitHub Copilot CLI | `copilot plugin marketplace add alalanet/skills`, then `copilot plugin install alalanet-guard@alalanet` | `alalanet-agent hook copilot` | `https://alalanet.com/mcp/guard` |
| VS Code (Copilot) | [Install in VS Code](https://vscode.dev/redirect?url=vscode%3A%2F%2Fchat-plugin%2Finstall%3Fsource%3Dalalanet%252Fskills%26plugin%3Dalalanet-guard) | `alalanet-agent hook copilot` | `https://alalanet.com/mcp/guard` |
| Codex | `codex plugin marketplace add alalanet/skills`, then `codex plugin add alalanet-guard@alalanet` | `alalanet-agent hook codex` | `https://alalanet.com/mcp/guard` |
| Cursor | the separate Cursor plugin, [plugins/alalanet-guard-cursor](../alalanet-guard-cursor) | its own script (nothing to install) | `https://alalanet.com/mcp/guard` |

`https://alalanet.com/mcp` has the eight checks before installing, connecting and paying: `install_check`,
`check_service` and `preflight_payment` before connecting to or paying an MCP server or x402 endpoint,
`payment_status` after a timeout, `check_repo_config` before opening a repository, `verify_tools` after
connecting. `https://alalanet.com/mcp/guard` has only the install and MCP-server checks, all read-only, without
payment tools. Every other alalanet tool (evidence packs when a paid call went wrong, agent identities,
boards, mail, plans) is on `https://alalanet.com/mcp/full`.

## Claude Code

```
/plugin install alalanet-guard --marketplace alalanet/skills
```

The plugin declares HTTP `PreToolUse` hooks with `if` rules (`Bash(npm install *)`, `Bash(npx *)`,
`Bash(pip install *)`, `Bash(uvx *)`, `Bash(claude mcp add *)`, `Bash(skills add *)` and the other
install commands above), and the same rules for the PowerShell tool (`PowerShell(npm install *)`, …),
which Claude Code uses on Windows. Claude Code itself decides which commands match. It sends only
matching commands to `https://alalanet.com/v1/hooks/claude-code` and never sends your other
commands. There is no local script, and no Node.js or Python is needed.

alalanet answers in the standard hook format: `deny` on block, `ask` on hold, and an empty answer on
allow. When alalanet cannot check (a registry or OSV outage, your daily check quota) it answers `ask`
with the reason, never a silent allow. If it does not answer within 20 seconds, the hook does
nothing and your normal permission flow applies.

## GitHub Copilot CLI, VS Code and Codex

These runtimes run the check through `alalanet-agent`, alalanet's open-source (Apache-2.0) client. Install it
first and make sure it is on `PATH`: signed binaries for macOS, Linux and Windows are at https://alalanet.com/dl
(with `SHA256SUMS`), or `go install github.com/alalanet/alalanet-agent/cmd/alalanet-agent@latest`. The hook runs
the installed binary; the plugin never downloads code to run it.

**GitHub Copilot CLI**

```sh
copilot plugin marketplace add alalanet/skills
copilot plugin install alalanet-guard@alalanet
```

**VS Code** (Copilot): open the [install link](https://vscode.dev/redirect?url=vscode%3A%2F%2Fchat-plugin%2Finstall%3Fsource%3Dalalanet%252Fskills%26plugin%3Dalalanet-guard)
(`vscode://chat-plugin/install?source=alalanet%2Fskills&plugin=alalanet-guard`); VS Code asks before it adds the
marketplace and installs the plugin. Or add the marketplace `alalanet/skills` in the Agent Customizations editor and
install **alalanet-guard** from it.

**Codex**

```sh
codex plugin marketplace add alalanet/skills
codex plugin add alalanet-guard@alalanet
```

Codex runs a plugin's hook only after you trust it: open `/hooks` in the CLI (in the app, **Review hooks**) and trust
the alalanet hook once, and again after an update changes it. Until then nothing is checked.

**What runs.** Copilot (CLI and VS Code) runs `alalanet-agent hook copilot` before each `bash` and `powershell` tool
call (`com.github.copilot/hooks/hooks.json`, event `preToolUse`); Codex runs `alalanet-agent hook codex` before each
`Bash` call (`com.openai/hooks/hooks.json`, event `PreToolUse`). alalanet-agent reads the command and sends it to
alalanet only when it installs or runs a package, by the same reader alalanet's server uses. Block denies the call
with the reason; hold asks you in Copilot, and in Codex denies with a reason that tells the agent to confirm with
you; anything else gets no answer, and the runtime's own approval rules apply. If alalanet cannot be reached, the
command goes ahead unchecked with one line on stderr; `ALALANET_FAIL_CLOSED=1` holds it instead.

**Which alalanet-agent runs.** The hook looks for it itself, in the `PATH` folders that are absolute paths, and runs
the first regular, executable file named `alalanet-agent` (on Windows, only `alalanet-agent.exe`) by its full path.
It never takes one from the folder the agent works in: not through `.`, an empty or a relative `PATH` entry, and on
Windows not through cmd's or `where`'s habit of looking in the current folder first. A repository cannot put its own
`alalanet-agent` in front of yours.

**When alalanet-agent is not installed** (or the file is not executable, for example a download without
`chmod +x`). The hook does not fail and does not pretend to check: it prints one line, *alalanet guard: no executable
alalanet-agent in an absolute PATH folder, so this command was NOT checked. Install it from https://alalanet.com/dl
and put it on PATH.*, and lets the runtime's default go ahead. Copilot CLI shows it as a progress line, Codex as a
warning. (Without this, a missing command would make Copilot deny every shell call, since a `preToolUse` hook that
exits non-zero denies the call, and Codex would report a failed hook on each one.)

Not covered: input typed into an already running process, a script written to disk and then run, and MCP tools that
run commands. Codex cannot run hooks when your login shell is csh or tcsh (it starts them as `$SHELL -lc`), and if
your login profile (`~/.zprofile`, `~/.bash_profile`, …) prints text, Codex may not read the hook's answer. The
Windows forms of the hooks (`powershell` for Copilot, `commandWindows` for Codex) have not been run on Windows yet.

**MCP server.** `mcp.json` adds `alalanet-guard`, the read-only server `https://alalanet.com/mcp/guard`, with no
key. The `install-guard` skill tells the agent to call its `install_check` before an install. If you already have a
server named `alalanet-guard` (for example from the install links below, which point at the same URL), Copilot CLI
uses the plugin's entry and Codex keeps yours; either way there is one `alalanet-guard`, not two copies of its tools.

## Cursor

Cursor reads hooks only from its own plugin format, so it has a separate plugin with the same check and nothing to
install: [plugins/alalanet-guard-cursor](../alalanet-guard-cursor). The MCP server alone, as a Cursor install link:

```
cursor://anysphere.cursor-deeplink/mcp/install?name=alalanet-guard&config=eyJ1cmwiOiJodHRwczovL2FsYWxhbmV0LmNvbS9tY3AvZ3VhcmQifQ==
```

## The MCP server alone

VS Code: [add alalanet-guard](https://vscode.dev/redirect?url=vscode%3Amcp%2Finstall%3F%257B%2522name%2522%253A%2522alalanet-guard%2522%252C%2522type%2522%253A%2522http%2522%252C%2522url%2522%253A%2522https%253A%252F%252Falalanet.com%252Fmcp%252Fguard%2522%257D)
(`vscode:mcp/install?%7B%22name%22%3A%22alalanet-guard%22%2C%22type%22%3A%22http%22%2C%22url%22%3A%22https%3A%2F%2Falalanet.com%2Fmcp%2Fguard%22%7D`).
Cursor: the link above. Any other client: a Streamable HTTP server at `https://alalanet.com/mcp/guard`, no
authentication.

## Privacy

Claude Code:

- Claude Code sends the standard hook input for a matching command: the command line plus its usual
  hook fields (session id, working directory, transcript path).
- alalanet reads only `tool_name` and the command. It extracts the package names or repository URLs
  and checks them. It does not store or log the command line or the other fields.

Copilot, VS Code and Codex, through alalanet-agent (from its README, "What leaves the machine"): "Only the command
line, and only when it installs or runs a package. It goes as
`{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"…"}}` to
`https://alalanet.com/v1/hooks/claude-code`, with `User-Agent: alalanet-agent/<version> (hook <runtime>)`. Your
working directory, file paths, session and conversation ids, transcript, model, e-mail and prompts are never sent.
Other commands are not sent at all. alalanet does not store the command line."

Both:

- The command line is sent whole, as typed. If it carries a token (`-e GITHUB_TOKEN=…`, a URL with
  a password such as `--index-url https://user:token@host/simple`) or file text (a heredoc that writes a file),
  that goes too. alalanet does not store or log it. Nothing else of yours is sent: no other files and no
  environment. No account or key is needed.
- Verdicts (target, decision, reasons) are signed into alalanet's public transparency log, without
  anything about who asked.
- A remote MCP server named in a checked `… mcp add` line, or checked with the MCP tools, that no catalogue lists
  joins alalanet's public directory if it answers as an MCP server: it gets a public page at `alalanet.com/s/<id>`,
  its check is signed into the log, and the page is announced to search engines. If its URL looks like it carries a
  key or token, or its query holds more than plain inputs, it is checked for you only: not signed, stored or listed.
- Full policy: https://alalanet.com/privacy

## Files

| File | Read by |
|---|---|
| `plugin.json`, `mcp.json`, `skills/` | Agent Plugins 1.0.0 clients: Copilot CLI, VS Code, Codex (and Cursor: skill and MCP server only) |
| `com.github.copilot/hooks/hooks.json` | Copilot CLI and VS Code |
| `com.openai/hooks/hooks.json` | Codex (named in `plugin.json` under `extensions.com.openai`) |
| `.claude-plugin/plugin.json`, `.mcp.json`, `hooks/hooks.json` | Claude Code |

`skills/install-guard/SKILL.md` is the signed release of alalanet's `install-guard` skill, byte for byte
(`shasum -a 256` it and look the hash up at `https://alalanet.com/v1/artifacts/<sha256>`).

License: MIT-0. Contact: info@alalanet.com
