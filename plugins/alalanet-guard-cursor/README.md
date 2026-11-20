# alalanet guard for Cursor

Your agent installs packages, MCP servers and skills all day. That is where it gets attacked:
malicious packages, typosquats of official MCP servers, package names a model invented that an
attacker registered, compromised versions after a maintainer change.

Before Cursor runs a shell command that names a package manager or installer (the list below), this plugin
asks [alalanet](https://alalanet.com)'s free `install_check` about it:

| Decision | What the hook does | Examples of reasons |
|---|---|---|
| block | denies the command, with the reason | `known_malicious:MAL-…` (OSV) |
| hold | denies the command, with the reasons and a note to confirm with you first | `name_like_official`, `not_on_npm`, `runs_install_script`, `maintainers_changed`, `new_package`, `known_vulnerabilities` |
| allow | lets Cursor's own approval rules decide, as without the plugin | no known problem (the code itself is not read: pin versions) |

Cursor does not pause a shell command on a hook's `ask`, so a hold is a deny whose message tells the
agent to confirm with you. If you agree, run the command yourself.

**Which lines are sent.** A command line is sent when a word in it names one of these programs: `npm`, `pnpm`,
`yarn`, `bun`, `npx`, `bunx`, `pnpx`, `pip`, `pip3`, `pipx`, `uv`, `uvx`, `deno`, `skills`, `clawhub`, `openclaw`;
`claude`, `codex` or `gemini` followed by `mcp`; or the IDE options `--install-extension` and `--add-mcp`. Exactly:
- letters match in any case, and quotes and backslashes between or around them are skipped, as is a
  backslash-newline (so `"npx"`, `n\px`, `np''x` and `n\` + newline + `pm` count). Cursor's own matcher and the
  Windows script also skip a bare newline inside a word; the sh script reads a bare newline as a space;
- a word starts at the start of the line or after a space, a quote, a backtick, `/`, `\` or one of `;&|()<>{},=`, so
  a path counts (`C:\Program Files\nodejs\npx.cmd`, `/usr/local/bin/npm`);
- it ends at the end of the line or before a space, a quote, a backtick or one of `;&|()<>{},=:@`, optionally after
  `.cmd`, `.exe`, `.bat` or `.ps1` in any case (so `npm-run-all`, `npmx` and `npm.js` do not count);
- `claude`, `codex` or `gemini` and `mcp` may be separated by spaces, quotes or backslashes;
- a line that holds `$'` followed by a backslash (ANSI-C quoting, which can spell any word) is sent whatever it names.

alalanet then reads the line as a shell would and decides:
installs, `create`/`init`, `dlx`/`exec`/`x`, `python -m pip`, `uv run --with`, `deno` with `npm:`/`jsr:`/`https:`,
`claude mcp add`/`add-json`, `code --add-mcp` and `--install-extension`, and registry changes (`npm ci --registry …`,
`npm config set registry …`, `npm_config_registry=… npm ci`). Lines that name none of these programs are not sent
and not checked: for example a line that only sets an environment variable (`export npm_config_registry=…`), or
one that builds a program's name from pieces (`n=np; ${n}x -y x`).

The plugin also connects Cursor to alalanet's read-only remote MCP server `https://alalanet.com/mcp/guard`:
`install_check`, `check_repo_config` before opening a repository, `check_service` and `connect_check` before
connecting to a remote MCP server, `verify_tools` after connecting, `check_artifact` and `get_attestation` to
verify a file or a verdict. The `install-guard` skill tells the agent to use them.

## Install

1. Open **Customize** in the sidebar, find **alalanet guard** (or open it in the
   [Cursor Marketplace](https://cursor.com/marketplace)), select **Install** and choose the user scope, so every
   project is covered.
2. The plugin's hook (`beforeShellExecution`), skill (`install-guard`) and MCP server appear in **Customize**.
3. Approve the MCP server `plugin-alalanet-guard-alalanet` when Cursor asks. Its tools are read-only for you:
   they check and answer. A remote MCP server or x402 endpoint you ask about that no catalogue lists may get a
   public page in alalanet's directory (see Privacy). An MCP blocklist your team set still applies to it.
4. Check it works: in an empty folder, ask the agent to run `npm i --dry-run mcp-server-fetch` (a known malicious
   package, MAL-2026-5476; `--dry-run` installs nothing even if the hook does not run). The command is denied with
   alalanet's reason. The **Hooks** output channel shows each run.

No account, key, Node.js or Python is needed. macOS and Linux use `sh` and `curl` (macOS ships both; on a
Linux without `curl` the hook says so on stderr and lets installs go ahead, or holds them with
`ALALANET_FAIL_CLOSED=1`); Windows uses its built-in PowerShell.

## How it works

`hooks/hooks.json` declares one `beforeShellExecution` hook with a `matcher`: a regular expression for the
program words above (`scripts/pattern.txt` holds the same text). No two of its quantifiers can match the same
characters one after the other, so the test is linear in the command's length: on 27 adversarial 1 MB inputs
(runs of quotes, backslashes and newlines after a program word, among others) node took at most 25 ms each here.
Cursor tests each shell command against it and runs the hook only for commands that match. The hook runs `./scripts/guard`: on macOS and Linux that is the `sh` script `scripts/guard`; on Windows,
PowerShell finds `scripts/guard.cmd` (through `PATHEXT`), which runs `scripts/guard-windows.ps1`.

The script reads the `command` field of Cursor's hook input and nothing else, tests it against the same
pattern again, and sends the whole line, as typed, to `https://alalanet.com/v1/hooks/claude-code` as

```json
{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"<the command line>"}}
```

with `User-Agent: alalanet-guard-cursor/<version> (hook cursor)` and, if you set `ALALANET_DEVICE_KEY`, the header
`X-Alalanet-Device-Key`. It prints Cursor's answer
(`{"permission":"deny","user_message":…,"agent_message":…}` on block and hold, `{"permission":"allow"}` otherwise).

## 1,000 checks a day: a free device key

Without a key the hook shares your address's 100 free checks a day with every other way you call alalanet. With a
free device key it has 1,000 a day of its own (and your address gets no more hook checks than that, however many
keys it holds). Get one once, with no sign-up (the key is random and bound to nothing), and put it in the environment
Cursor runs in:

```sh
curl -s -X POST https://alalanet.com/v1/device-keys   # prints {"device_key":"ald_…", …}
export ALALANET_DEVICE_KEY=ald_…                      # e.g. in ~/.zshenv; on Windows: setx ALALANET_DEVICE_KEY ald_…
```

A value that does not read as a key (`ald_` and lowercase letters, digits, `_`) is not sent.

## When alalanet cannot check

- alalanet does not answer in full within 20 seconds (18 on Windows), cannot be reached, answers an error or an
  answer over 64 KiB, or the daily limit is spent (without a device key, your address's 100 checks a day, shared with
  every other way you call alalanet; with one, 1,000 a day): the command goes ahead
  unchecked, and the script writes one line on stderr (the **Hooks** output channel). This is the same as
  without the plugin.
- Set `ALALANET_FAIL_CLOSED=1` in the environment Cursor runs in to hold such commands instead (denied with
  `NOT CHECKED` and the reason). Recommended for sensitive work.
- A hook input the script cannot read, a command whose request to alalanet would exceed 1 MiB, or an `ALALANET_API` that is not `https` (plain
  `http` is allowed only to `127.0.0.1` or `localhost`, for testing) holds the command with the reason.
- If the hook itself fails (for example `powershell.exe` is blocked by policy), Cursor logs the failure and runs
  the command: the plugin's hook is not `failClosed`.

Known limits: a script written to disk and then run, input typed into an already running process, and
MCP servers that Cursor itself starts from `mcp.json` are not shell commands, so this hook does not see them.

## Privacy

- Cursor's hook input carries more (your e-mail, workspace paths, conversation and generation ids, the
  transcript path, the model). The script reads only `command` and sends nothing else.
- Only lines that name one of the programs above are sent; your other commands never leave the machine. The
  test is on the text of the whole line, so a line that only mentions one (`git commit -m "npm i x"`,
  `grep -r npx docs`) is sent too; alalanet then finds nothing to check and stays silent.
- The matching line is sent whole, as typed. If it carries a token (`-e GITHUB_TOKEN=…`, a URL with a password
  such as `--index-url https://user:token@host/simple`) or file text (a heredoc that writes a file and mentions
  `npm`), that goes too. alalanet does not store or log the line: it extracts the package names and repository
  URLs and checks them.
- Nothing else is sent: no other files, no environment, no credentials of yours beyond what the line itself
  holds. No account or key is needed.
- A remote MCP server named on a `… mcp add` line, or an MCP server or x402 endpoint the agent checks with the MCP
  tools, that no catalogue lists may get a public page at `alalanet.com/s/<id>` if it answers as one, unless its
  URL looks like it carries a key or token (as `/privacy` says).
- Verdicts (target, decision, reasons) are signed into alalanet's public transparency log, without anything
  about who asked.
- Full policy: https://alalanet.com/privacy

## Relation to the Claude Code plugin

This is the Cursor edition of the `alalanet-guard` plugin for Claude Code (`plugins/alalanet-guard` in the same
repository). Both have the same name and ask the same check. In Claude Code, Claude Code's own rules pick the install
commands and it calls alalanet itself; in Cursor, these scripts pick the lines (wider, as above) and call it.
In Cursor, install this one. Cursor's *Third-Party Imports* setting can also load Claude Code plugins;
whether it then shows the Claude plugin's MCP server as well has not been checked.

## Windows

`./scripts/guard` resolves to `scripts/guard.cmd` through `PATHEXT`, which runs `guard-windows.ps1` with
`powershell.exe -ExecutionPolicy Bypass`. The script reads its input as UTF-8 bytes, sends ASCII-only JSON
(`\u` escapes), and puts one 18-second timer over the whole request (name lookup, connection, headers and body).
Not proven, because it has not been run on Windows or in Cursor on Windows:
- which PowerShell Cursor uses to start the hook, and that it resolves `./scripts/guard` to `guard.cmd`;
- that the command reaches the script byte for byte: if Cursor pipes it through Windows PowerShell 5.1, characters
  outside ASCII may arrive as `?` (package names are ASCII, so the check is not affected);
- Windows PowerShell 5.1 itself (the script was run in PowerShell 7 only);
- machines in Constrained Language Mode (AppLocker, WDAC) or with an execution policy set by Group Policy: the
  script cannot run there, and Cursor then runs the command unchecked.

## Verify the skill

`skills/install-guard/SKILL.md` is the signed release of alalanet's `install-guard` skill, byte for byte:

```sh
shasum -a 256 skills/install-guard/SKILL.md
curl -s https://alalanet.com/v1/artifacts/<sha256>    # advice: signed_by_alalanet
```

## Support

Issues: https://github.com/alalanet/skills/issues. Security reports: info@alalanet.com.
Terms: https://alalanet.com/terms. License: MIT-0.
