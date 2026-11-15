# alalanet guard for Cursor

Your agent installs packages, MCP servers and skills all day. That is where it gets attacked:
malicious packages, typosquats of official MCP servers, package names a model invented that an
attacker registered, compromised versions after a maintainer change.

This plugin checks every install command before Cursor runs it, with [alalanet](https://alalanet.com)'s
free `install_check`:

| Decision | What the hook does | Examples of reasons |
|---|---|---|
| block | denies the command, with the reason | `known_malicious:MAL-…` (OSV) |
| hold | denies the command, with the reasons and a note to confirm with you first | `name_like_official`, `not_on_npm`, `runs_install_script`, `maintainers_changed`, `new_package`, `known_vulnerabilities` |
| allow | lets Cursor's own approval rules decide, as without the plugin | no known problem (the code itself is not read: pin versions) |

Cursor does not pause a shell command on a hook's `ask`, so a hold is a deny whose message tells the
agent to confirm with you. If you agree, run the command yourself.

Covered commands: `npm`/`pnpm`/`yarn`/`bun` install, add, `dlx`, `exec`, `x`; `npx`, `pnpx`, `bunx`, `uvx`;
`pip`/`pip3 install`, `python -m pip install`; `uv add`, `uv pip install`, `uv tool install|run`, `uv run --with`;
`pipx install|run|inject|runpip`; `deno` with `npm:`, `jsr:` or `https://` modules; `claude`/`codex`/`gemini mcp add`;
`skills add`, `clawhub install`, `openclaw skills install`; and IDE extension installs (`--install-extension`).

The plugin also connects Cursor to alalanet's read-only remote MCP server `https://alalanet.com/mcp/guard`:
`install_check`, `check_repo_config` before opening a repository, `check_service` and `connect_check` before
connecting to a remote MCP server, `verify_tools` after connecting, `check_artifact` and `get_attestation` to
verify a file or a verdict. The `install-guard` skill tells the agent to use them.

## Install

1. Open **Customize** in the sidebar, find **alalanet guard** (or open it in the
   [Cursor Marketplace](https://cursor.com/marketplace)), select **Install** and choose the user scope, so every
   project is covered.
2. The plugin's hook (`beforeShellExecution`), skill (`install-guard`) and MCP server appear in **Customize**.
3. Approve the MCP server `plugin-alalanet-guard-alalanet` when Cursor asks. Its tools only read: they check
   and answer, and change nothing. An MCP blocklist your team set still applies to it.
4. Check it works: ask the agent to run `npm i mcp-server-fetch` (a known malicious package, MAL-2026-5476).
   The command is denied with alalanet's reason. The **Hooks** output channel shows each run.

No account, key, Node.js or Python is needed. macOS and Linux use `sh` and `curl` (macOS ships both; on a
Linux without `curl` the hook says so on stderr and lets installs go ahead, or holds them with
`ALALANET_FAIL_CLOSED=1`); Windows uses its built-in PowerShell.

## How it works

`hooks/hooks.json` declares one `beforeShellExecution` hook with a `matcher`: a regular expression for the
install commands above. Cursor tests each shell command against it and runs the hook only for commands
that match. The hook runs `./scripts/guard`: on macOS and Linux that is the `sh` script `scripts/guard`; on
Windows, PowerShell finds `scripts/guard.cmd` (through `PATHEXT`), which runs `scripts/guard-windows.ps1`.

The script reads the `command` field of Cursor's hook input and nothing else, tests it against the same
pattern again, and sends it to `https://alalanet.com/v1/hooks/claude-code` as

```json
{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"<the command line>"}}
```

with `User-Agent: alalanet-guard-cursor/<version> (hook cursor)`. It prints Cursor's answer
(`{"permission":"deny","user_message":…,"agent_message":…}` on block and hold, `{"permission":"allow"}` otherwise).

## When alalanet cannot check

- alalanet does not answer within 20 seconds, cannot be reached, answers an error, or the daily limit for your
  address (1,000 checks) is spent: the command goes ahead unchecked, and the script writes one line on stderr
  (the **Hooks** output channel). This is the same as without the plugin.
- Set `ALALANET_FAIL_CLOSED=1` in the environment Cursor runs in to hold such commands instead (denied with
  `NOT CHECKED` and the reason). Recommended for sensitive work.
- A hook input the script cannot read, a command over 1 MiB, or an `ALALANET_API` that is not `https` holds the
  command with the reason.
- If the hook itself fails (for example `powershell.exe` is blocked by policy), Cursor logs the failure and runs
  the command: the plugin's hook is not `failClosed`.

Known limits: a script written to disk and then run, input typed into an already running process, and
MCP servers that Cursor itself starts from `mcp.json` are not shell commands, so this hook does not see them.

## Privacy

- Cursor's hook input carries more (your e-mail, workspace paths, conversation and generation ids, the
  transcript path, the model). The script reads only `command` and sends nothing else.
- Only commands that match the install pattern are sent; your other commands never leave the machine. The
  pattern matches the text of the whole command line, so a line that mentions an install (`git commit -m "npm i x"`)
  is sent too; alalanet then finds nothing to check and stays silent.
- alalanet extracts the package names or repository URLs from the command and checks them. It does not store
  or log the command line.
- No code, files or credentials are sent, and no account or key is needed.
- Verdicts (target, decision, reasons) are signed into alalanet's public transparency log, without anything
  about who asked.
- Full policy: https://alalanet.com/privacy

## Verify the skill

`skills/install-guard/SKILL.md` is the signed release of alalanet's `install-guard` skill, byte for byte:

```sh
shasum -a 256 skills/install-guard/SKILL.md
curl -s https://alalanet.com/v1/artifacts/<sha256>    # advice: signed_by_alalanet
```

## Support

Issues: https://github.com/alalanet/skills/issues. Security reports: info@alalanet.com.
Terms: https://alalanet.com/terms. License: MIT-0.
