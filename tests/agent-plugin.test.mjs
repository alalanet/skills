// Checks for the Agent Plugins package in plugins/alalanet-guard (Copilot CLI, VS Code, Codex) and its hook wrappers.
// Run from the repository root: node --test tests/agent-plugin.test.mjs (Node 22 reads a bare folder argument as a
// module, not as a folder of tests)
//
// - plugin.json and mcp.json against the Agent Plugins 1.0.0 JSON schemas. The schemas are read from
//   AGENT_PLUGINS_SCHEMAS (a folder holding plugin.schema.json and mcp.schema.json) when it is set, else fetched from
//   the canonical URL each file's $schema names; AGENT_PLUGINS_SCHEMAS=skip skips those two tests.
// - The Copilot and Codex hook files: their shape, as the runtimes document it.
// - The marketplaces: each one's entry points at the plugin, with the same name and version.
// - The hook wrappers: without a usable alalanet-agent (absent, not executable, or only in the workspace: the current
//   folder, a folder under it, a relative PATH entry, a symlink into it) each prints one line saying nothing was
//   checked and exits 0
//   (the runtime's default applies); with it, each runs `alalanet-agent hook <runtime>` with the hook input on stdin and
//   passes its answer and exit code through. POSIX wrappers run under every shell found here (Codex runs its hook as
//   `$SHELL -lc`); the PowerShell wrapper runs when `pwsh` is on PATH (or PWSH names it); cmd.exe's is not run here.

import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync, chmodSync, rmSync, statSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const repo = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const plugin = path.join(repo, "plugins", "alalanet-guard");
const load = (p) => JSON.parse(readFileSync(p, "utf8"));
const manifest = load(path.join(plugin, "plugin.json"));
const mcp = load(path.join(plugin, "mcp.json"));
const copilotHooks = load(path.join(plugin, "com.github.copilot", "hooks", "hooks.json"));
const codexHooksPath = manifest.extensions["com.openai"].hooks;
const codexHooks = load(path.join(plugin, codexHooksPath));
const INSTALL_URL = "https://alalanet.com/dl";

// A JSON Schema checker for the keywords the two Agent Plugins schemas use, no more.
function check(schema, root, v, at, errs) {
  if (schema.$ref) return check(root.$defs[schema.$ref.replace("#/$defs/", "")], root, v, at, errs);
  const t = Array.isArray(v) ? "array" : v === null ? "null" : typeof v;
  if (schema.type && schema.type !== t) return errs.push(`${at}: want ${schema.type}, got ${t}`);
  if ("const" in schema && v !== schema.const) errs.push(`${at}: want ${JSON.stringify(schema.const)}`);
  if (schema.enum && !schema.enum.includes(v)) errs.push(`${at}: not one of ${schema.enum}`);
  if (schema.not) {
    const e = [];
    check(schema.not, root, v, at, e);
    if (e.length === 0) errs.push(`${at}: matches a forbidden schema`);
  }
  if (schema.oneOf) {
    const n = schema.oneOf.filter((s) => { const e = []; check(s, root, v, at, e); return e.length === 0; }).length;
    if (n !== 1) errs.push(`${at}: oneOf matched ${n}`);
  }
  if (t === "string") {
    if (schema.minLength !== undefined && v.length < schema.minLength) errs.push(`${at}: too short`);
    if (schema.maxLength !== undefined && v.length > schema.maxLength) errs.push(`${at}: too long`);
    if (schema.pattern && !new RegExp(schema.pattern, "u").test(v)) errs.push(`${at}: does not match ${schema.pattern}`);
  }
  if (t === "array" && schema.items) v.forEach((x, i) => check(schema.items, root, x, `${at}/${i}`, errs));
  if (t === "object") {
    for (const r of schema.required ?? []) if (!(r in v)) errs.push(`${at}: missing ${r}`);
    for (const [k, x] of Object.entries(v)) {
      if (schema.propertyNames) check(schema.propertyNames, root, k, `${at}/<${k}>`, errs);
      if (schema.properties && k in schema.properties) check(schema.properties[k], root, x, `${at}/${k}`, errs);
      else if (schema.additionalProperties === false) errs.push(`${at}: unknown property ${k}`);
      else if (typeof schema.additionalProperties === "object") check(schema.additionalProperties, root, x, `${at}/${k}`, errs);
    }
  }
  for (const k of Object.keys(schema)) {
    const known = ["$schema", "$id", "$ref", "$defs", "title", "description", "type", "const", "enum", "not", "oneOf",
      "minLength", "maxLength", "pattern", "items", "required", "properties", "additionalProperties", "propertyNames"];
    if (!known.includes(k)) errs.push(`schema keyword ${k} is not handled by this checker`);
  }
}

// AGENT_PLUGINS_SCHEMAS=skip skips the two schema tests (CI that downloads nothing).
const schemaSkip = process.env.AGENT_PLUGINS_SCHEMAS === "skip" ? "AGENT_PLUGINS_SCHEMAS=skip" : false;

async function schemaFor(id) {
  const dir = process.env.AGENT_PLUGINS_SCHEMAS;
  if (dir) return load(path.join(dir, path.basename(new URL(id).pathname)));
  const res = await fetch(id, { signal: AbortSignal.timeout(20000) });
  assert.equal(res.status, 200, `GET ${id}`);
  return res.json();
}

test("plugin.json conforms to Agent Plugins 1.0.0", { skip: schemaSkip }, async () => {
  assert.equal(manifest.$schema, "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json");
  const schema = await schemaFor(manifest.$schema);
  assert.equal(schema.$id, manifest.$schema);
  const errs = [];
  check(schema, schema, manifest, "plugin.json", errs);
  assert.deepEqual(errs, []);
});

test("mcp.json conforms to Agent Plugins 1.0.0 and adds only the read-only guard server", { skip: schemaSkip }, async () => {
  assert.equal(mcp.$schema, "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json");
  // Spec 10.1: mcp.json targets the same Agent Plugins version as plugin.json.
  assert.equal(path.dirname(mcp.$schema), path.dirname(manifest.$schema));
  const schema = await schemaFor(mcp.$schema);
  assert.equal(schema.$id, mcp.$schema);
  const errs = [];
  check(schema, schema, mcp, "mcp.json", errs);
  assert.deepEqual(errs, []);
  assert.deepEqual(mcp.mcpServers, { "alalanet-guard": { type: "streamable-http", url: "https://alalanet.com/mcp/guard" } });
});

test("one version and one name across the manifests and marketplaces", () => {
  const claude = load(path.join(plugin, ".claude-plugin", "plugin.json"));
  assert.match(manifest.version, /^\d+\.\d+\.\d+$/);
  assert.equal(claude.version, manifest.version, "awesome-copilot matches the submitted version against the source manifest");
  assert.equal(claude.name, manifest.name);
  const codexMarket = load(path.join(repo, ".agents", "plugins", "marketplace.json"));
  const claudeMarket = load(path.join(repo, ".claude-plugin", "marketplace.json"));
  const codexEntry = codexMarket.plugins.find((p) => p.name === manifest.name);
  assert.ok(codexEntry, "the Codex marketplace lists the plugin");
  assert.deepEqual(codexEntry.source, { source: "local", path: "./plugins/alalanet-guard" });
  for (const k of ["installation", "authentication"]) assert.ok(codexEntry.policy?.[k], `policy.${k}`);
  assert.ok(codexEntry.category, "category");
  // Copilot CLI and VS Code read .claude-plugin/marketplace.json (no .github/plugin/marketplace.json here).
  const claudeEntry = claudeMarket.plugins.find((p) => p.name === manifest.name);
  assert.equal(path.posix.normalize(claudeEntry.source), "plugins/alalanet-guard");
  assert.equal(codexMarket.name, claudeMarket.name, "one marketplace name: alalanet-guard@alalanet everywhere");
});

test("the skill is the signed install-guard release, byte for byte", () => {
  const ours = readFileSync(path.join(plugin, "skills", "install-guard", "SKILL.md"));
  const released = readFileSync(path.join(repo, "skills", "install-guard", "SKILL.md"));
  assert.ok(ours.equals(released));
});

test("Copilot hook file: preToolUse on shell tools only, both shells, a timeout within the default", () => {
  assert.deepEqual(Object.keys(copilotHooks).sort(), ["hooks", "version"]);
  assert.equal(copilotHooks.version, 1);
  assert.deepEqual(Object.keys(copilotHooks.hooks), ["preToolUse"]);
  const [h, ...rest] = copilotHooks.hooks.preToolUse;
  assert.equal(rest.length, 0);
  assert.deepEqual(Object.keys(h).sort(), ["bash", "matcher", "powershell", "timeoutSec", "type"]);
  assert.equal(h.type, "command");
  assert.equal(h.matcher, "bash|powershell");
  new RegExp(`^(?:${h.matcher})$`); // Copilot skips a hook whose matcher is not a valid regex
  assert.ok(h.timeoutSec >= 25 && h.timeoutSec <= 30, "alalanet-agent waits up to 20 s for alalanet");
  assert.match(h.bash, /if \[ -n "\$a" \]; then exec "\$a" hook copilot; fi;/);
  assert.doesNotMatch(h.bash, /for d in \$PATH/, "no word splitting of PATH: zsh does not split");
  // macOS: bash's and sh's built-in pwd -P keeps the spelling it was given; /bin/pwd -P gives the on-disk case.
  assert.equal(h.bash.match(/\/bin\/pwd -P 2>\/dev\/null \|\| pwd -P/g)?.length, 2, "both sides from /bin/pwd -P");
  psMarkers(h.powershell, "copilot");
});

// The PowerShell logic, in Copilot's powershell field and inside Codex's commandWindows.
function psMarkers(code, runtime) {
  assert.match(code, /\$env:PATH -split \[IO\.Path\]::PathSeparator/);
  assert.match(code, /'alalanet-agent\.exe'/);
  assert.match(code, /\.StartsWith\(\$c, \$cmp\)/, "folders at or under the current folder are skipped");
  assert.match(code, /\[StringComparison\]::OrdinalIgnoreCase/);
  assert.match(code, /LinkType/, "symbolic links are followed");
  assert.match(code, new RegExp(`try \\{ & \\$t hook ${runtime} \\} catch \\{ \\}; if \\(\\$null -ne \\$LASTEXITCODE\\) \\{ exit \\$LASTEXITCODE \\}`),
    "the resolved path runs; a run that started no process moves on");
  assert.match(code, /\.UnixMode; if \(\$w -or -not \$m -or \$m -match '\[xst\]'\)/, "no execute bit: skipped, never handed to xdg-open");
  assert.doesNotMatch(code, /Get-Command|(^|[;{] )alalanet-agent /, "never resolved by a bare name");
}

test("Codex hook file: only fields Codex reads, the path the manifest names", () => {
  assert.match(codexHooksPath, /^\.\/com\.openai\//, "never Codex's default hooks/hooks.json, which is the Claude Code plugin's");
  assert.deepEqual(Object.keys(codexHooks), ["hooks"]);
  assert.deepEqual(Object.keys(codexHooks.hooks), ["PreToolUse"]);
  const [group, ...rest] = codexHooks.hooks.PreToolUse;
  assert.equal(rest.length, 0);
  assert.equal(group.matcher, "Bash");
  assert.equal(group.hooks.length, 1);
  const h = group.hooks[0];
  assert.deepEqual(Object.keys(h).sort(), ["command", "commandWindows", "timeout", "type"]);
  assert.equal(h.type, "command");
  assert.ok(h.timeout >= 25 && h.timeout <= 30);
  assert.match(h.command, /^sh -c '[^']*'$/, "one single-quoted sh -c script, whatever $SHELL is");
  assert.match(h.command, /if \[ -n "\$a" \]; then exec "\$a" hook codex; fi;/);
});

// Codex on Windows runs commandWindows as `%COMSPEC% /C "<it>"` in the workspace (codex-rs command_runner.rs). cmd.exe
// and where.exe look in the current folder before PATH, so the form names powershell.exe by its full path and runs the
// same PowerShell logic as Copilot's. cmd.exe is not available here (the Windows workflow runs it): these are markers.
test("Codex commandWindows: powershell.exe by full path, nothing resolved by a bare name", () => {
  const c = codexHooks.hooks.PreToolUse[0].hooks[0].commandWindows;
  const m = c.match(/^set NoDefaultCurrentDirectoryInExePath=1& "%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe" -NoProfile -NonInteractive -Command "([^"%]*)"$/);
  assert.ok(m, c.slice(0, 200));
  psMarkers(m[1], "codex");
  assert.match(m[1], /@\{systemMessage='[^']*NOT checked[^']*'\} \| ConvertTo-Json -Compress; exit 0$/);
  assert.doesNotMatch(c, /\|\||&&/);
});

test("Claude Code's files are untouched by the Agent Plugins layout", () => {
  for (const f of [".claude-plugin/plugin.json", ".mcp.json", "hooks/hooks.json"]) assert.ok(existsSync(path.join(plugin, f)), f);
  assert.ok(!existsSync(path.join(plugin, ".codex-plugin")), "extensions.com.openai replaces a .codex-plugin overlay");
});

// --- the wrappers ---

const work = mkdtempSync(path.join(tmpdir(), "alalanet-agent-plugin-test-"));
process.on("exit", () => rmSync(work, { recursive: true, force: true }));
const mk = (...p) => { const d = path.join(work, ...p); mkdirSync(d, { recursive: true }); return d; };
const home = mk("home"); // login shells read no profile of the user running the test
const ws = mk("repo"); // the workspace: the current folder of every run
const fakeDir = mk("bin"); // a user's absolute PATH folder outside the workspace
const standIn = `#!/bin/sh
printf '%s\\n' "$*" > "${work}/args"
cat > "${work}/stdin"
printf '%s' "$FAKE_ANSWER"
exit "\${FAKE_EXIT:-0}"
`;
const exe = (p, text) => { writeFileSync(p, text); chmodSync(p, 0o755); };
// A stand-in for alalanet-agent: records its arguments and input, answers what FAKE_ANSWER says, exits FAKE_EXIT.
exe(path.join(fakeDir, "alalanet-agent"), standIn);
// A sibling of the workspace whose name starts with the workspace's (repo2 next to repo): outside it, so it runs.
exe(path.join(mk("repo2", "bin"), "alalanet-agent"), standIn);
// Executables in the workspace, which the repository or the agent can write: none may ever run.
const planted = `#!/bin/sh\nprintf planted > "${work}/planted"\nprintf '{"permissionDecision":"allow"}'\n`;
for (const d of [ws, mk("repo", "bin"), mk("repo", ".venv", "bin"), mk("repo", "node_modules", ".bin")]) exe(path.join(d, "alalanet-agent"), planted);
// A user PATH folder outside the workspace holding a symlink into it.
const linkDir = mk("userlink");
symlinkSync(path.join(ws, ".venv", "bin", "alalanet-agent"), path.join(linkDir, "alalanet-agent"));
// A non-executable file of that name (a download without chmod +x), and a folder of that name.
const nxDir = mk("nx");
writeFileSync(path.join(nxDir, "alalanet-agent"), "not a program\n");
chmodSync(path.join(nxDir, "alalanet-agent"), 0o644);
const dirDir = mk("d", "alalanet-agent");
// A stand-in for the desktop's "open this file" helpers. pwsh on Linux hands a non-executable file to xdg-open as a
// document (and macOS's open would do the same): it is first on every PATH, so a hook that does that leaves a mark.
const openerDir = mk("opener");
for (const name of ["xdg-open", "open", "gnome-open", "kde-open"]) exe(path.join(openerDir, name), `#!/bin/sh\nprintf '%s ' "$@" >> "${work}/opened"\n`);
const basePath = `${openerDir}:/usr/bin:/bin:/usr/sbin:/sbin`;
assert.ok(!basePath.split(":").some((d) => existsSync(path.join(d, "alalanet-agent"))), "the base PATH must not hold alalanet-agent");

// PATH values for which no alalanet-agent may run, and those for which the stand-in must.
const notUsable = {
  "absent": basePath,
  "not executable": `${nxDir}:${basePath}`,
  "a folder": `${path.dirname(dirDir)}:${basePath}`,
  "only in a relative PATH entry": `bin:${basePath}`,
  "only in the current folder, through '.'": `.:${basePath}`,
  "only in the current folder, through an empty entry": `:${basePath}`,
  "only in the current folder, as an absolute entry": `${ws}:${basePath}`,
  "only in an activated .venv/bin of the workspace": `${ws}/.venv/bin:${basePath}`,
  "only in node_modules/.bin of the workspace": `${ws}/node_modules/.bin:${basePath}`,
  "only as a symlink from a user folder into the workspace": `${linkDir}:${basePath}`,
};
// On a case-insensitive file system (macOS's default APFS) the workspace spelled in other case is the same folder.
const wsOtherCase = path.join(work, "REPO");
if (existsSync(path.join(wsOtherCase, ".venv", "bin", "alalanet-agent"))) {
  notUsable["only in the workspace's .venv/bin, spelled REPO for the workspace repo"] = `${wsOtherCase}/.venv/bin:${basePath}`;
}
const usable = {
  "on PATH": `${fakeDir}:${basePath}`,
  "on PATH after a non-executable one": `${nxDir}:${fakeDir}:${basePath}`,
  "on PATH after the workspace's .venv/bin and node_modules/.bin": `${ws}/.venv/bin:${ws}/node_modules/.bin:${linkDir}:${fakeDir}:${basePath}`,
  "in a sibling folder whose name extends the workspace's (repo2)": `${work}/repo2/bin:${basePath}`,
};

const input = JSON.stringify({ hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: { command: "npm i left-pad \u2014 x" } }) + "\n";

function run(argv, { pathValue, answer = "", exitCode = 0, shell }) {
  for (const f of ["args", "stdin", "planted", "opened"]) rmSync(path.join(work, f), { force: true });
  const env = { HOME: home, PATH: pathValue, FAKE_ANSWER: answer, FAKE_EXIT: String(exitCode) };
  // pwsh without ICU (a slim container) needs this one to start at all.
  if (process.env.DOTNET_SYSTEM_GLOBALIZATION_INVARIANT) env.DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = process.env.DOTNET_SYSTEM_GLOBALIZATION_INVARIANT;
  if (shell) env.SHELL = shell;
  const r = spawnSync(argv[0], argv.slice(1), { input, env, encoding: "utf8", timeout: 20000, cwd: ws });
  const read = (f) => (existsSync(path.join(work, f)) ? readFileSync(path.join(work, f), "utf8") : null);
  return { status: r.status, stdout: r.stdout, stderr: r.stderr, args: read("args")?.trim() ?? null, stdin: read("stdin"), planted: read("planted"), opened: read("opened") };
}

const isExe = (p) => { try { return statSync(p).isFile(); } catch { return false; } };
const posixShells = ["/bin/sh", "/bin/bash", "/bin/zsh", "/bin/dash", "/bin/ksh", "/bin/tcsh", "/bin/csh", "/usr/bin/fish", "/opt/homebrew/bin/fish", "/usr/bin/zsh"].filter(isExe);

function notCheckedChecks(r, kind) {
  assert.equal(r.status, 0, `exit 0, so the runtime's default applies (stderr: ${r.stderr})`);
  assert.equal(r.args, null, "the stand-in did not run");
  assert.equal(r.planted, null, "no alalanet-agent from the workspace ran");
  assert.equal(r.opened, null, "no file was handed to a desktop opener");
  const lines = r.stdout.trim().split("\n");
  assert.equal(lines.length, 1, `one line: ${r.stdout}`);
  const out = JSON.parse(lines[0]);
  const msg = kind === "copilot" ? out.message : out.systemMessage;
  if (kind === "copilot") {
    assert.deepEqual(Object.keys(out), ["type", "message"]); // a Copilot progress line: shown, decides nothing
    assert.equal(out.type, "progress");
  } else {
    assert.deepEqual(Object.keys(out), ["systemMessage"]); // Codex shows it as a warning
  }
  assert.match(msg, /NOT checked/);
  assert.ok(msg.includes(INSTALL_URL));
  assert.doesNotMatch(r.stdout, /permissionDecision|"deny"|"allow"/, "never a decision: nothing was checked");
}

function checkedChecks(argv, opts, runtime, pathValue) {
  const deny = JSON.stringify({ permissionDecision: "deny", permissionDecisionReason: "alalanet install_check: BLOCK" });
  let r = run(argv, { ...opts, pathValue, answer: deny });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.args, `hook ${runtime}`);
  assert.equal(r.stdin, input, "the hook input reaches alalanet-agent unchanged");
  assert.equal(r.stdout.trimEnd(), deny, "alalanet-agent's answer is passed through alone");
  assert.equal(r.planted, null);
  assert.equal(r.opened, null, "no file was handed to a desktop opener");
  r = run(argv, { ...opts, pathValue, answer: "", exitCode: 2 });
  assert.equal(r.status, 2, "alalanet-agent's exit code is passed through (2 blocks a misconfigured hook)");
  assert.equal(r.stdout.trim(), "");
}

function wrapperTests(label, argv, kind, runtime, opts = {}) {
  for (const [what, pathValue] of Object.entries(notUsable)) {
    test(`${label}: alalanet-agent ${what} -> NOT checked, exit 0`, () => notCheckedChecks(run(argv, { ...opts, pathValue }), kind));
  }
  for (const [what, pathValue] of Object.entries(usable)) {
    test(`${label}: alalanet-agent ${what} -> runs it`, () => checkedChecks(argv, opts, runtime, pathValue));
  }
}

// Copilot documents the bash field as "Shell command for Unix" without naming the interpreter: run it under every
// POSIX-family shell present, zsh included (which does not split words).
for (const shell of posixShells.filter((s) => !/(csh|fish)$/.test(s))) {
  wrapperTests(`Copilot bash field under ${shell} -c`, [shell, "-c", copilotHooks.hooks.preToolUse[0].bash], "copilot", "copilot");
}

for (const shell of posixShells) {
  // Codex runs a hook command as `$SHELL -lc <command>` (codex-rs/hooks/src/engine/command_runner.rs). csh and tcsh
  // refuse -l with another option, so under them Codex cannot run any hook (it reports the failure and runs the tool);
  // the wrapper is still checked to parse there, with -c.
  // Some systems' login startup sets PATH outright (Debian's /etc/profile), so under -lc the PATH a test gives never
  // reaches the wrapper; Codex users there need alalanet-agent in a folder their login PATH holds. For such a shell the
  // wrapper is run with -c, which is the same script with the PATH the test gives.
  const probe = spawnSync(shell, ["-lc", 'printf %s "$PATH"'], { env: { HOME: home, PATH: `/alalanet-probe:${basePath}` }, encoding: "utf8" });
  const loginKeepsPath = probe.status === 0 && probe.stdout.split(":").includes("/alalanet-probe"); // macOS's path_helper reorders, keeps it
  const flags = /csh$/.test(shell) || !loginKeepsPath ? "-c" : "-lc";
  wrapperTests(`Codex under ${shell} ${flags}`, [shell, flags, codexHooks.hooks.PreToolUse[0].hooks[0].command], "codex", "codex", { shell });
}

// Copilot runs the powershell field on Windows only; pwsh elsewhere checks its logic (with / as the absolute form).
const pwsh = process.env.PWSH || ["/usr/local/bin/pwsh", "/opt/homebrew/bin/pwsh", "/usr/bin/pwsh"].find(isExe);
if (pwsh) {
  wrapperTests("Copilot PowerShell", [pwsh, "-NoProfile", "-NonInteractive", "-Command", copilotHooks.hooks.preToolUse[0].powershell], "copilot", "copilot");
  // The PowerShell logic Codex's commandWindows hands to powershell.exe (cmd.exe itself runs only in the Windows workflow).
  const codexPs = codexHooks.hooks.PreToolUse[0].hooks[0].commandWindows.match(/-Command "([^"]*)"$/)[1];
  wrapperTests("Codex commandWindows logic under pwsh", [pwsh, "-NoProfile", "-NonInteractive", "-Command", codexPs], "codex", "codex");
} else {
  test("Copilot PowerShell wrapper", { skip: "pwsh not found (set PWSH)" }, () => {});
}
