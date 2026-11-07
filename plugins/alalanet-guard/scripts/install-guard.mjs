#!/usr/bin/env node
// alalanet guard: a Claude Code PreToolUse hook for Bash.
// When the agent is about to run an install (npm/pnpm/yarn/bun, npx, pip/uv/uvx/pipx,
// claude|codex mcp add, skills add, clawhub install), ask alalanet's install_check first:
//   block -> deny the command, hold -> ask the human, allow -> stay silent.
// Only the install target (package names, a repo URL) is sent, never code or file contents.
// If alalanet cannot be reached in time, the hook stays silent and the normal permission flow applies.

const API = process.env.ALALANET_API || "https://alalanet.com";
const TIMEOUT_MS = 8000;
const MAX_TARGETS = 5;

function readStdin() {
  return new Promise((resolve) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (c) => (data += c));
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", () => resolve(""));
  });
}

// Split a shell line into simple commands (&&, ||, ;, |) and words. Good enough for install lines.
function commands(line) {
  return line
    .split(/&&|\|\||;|\|/)
    .map((c) => c.trim().split(/\s+/).filter(Boolean))
    .filter((w) => w.length > 0);
}

const isFlag = (w) => w.startsWith("-");

// install targets of one simple command, as strings alalanet's install_check understands
export function targets(words) {
  let w = words.slice();
  while (w.length && /^(sudo|env|time|nice)$|=/.test(w[0])) w.shift(); // sudo, VAR=x prefixes
  if (!w.length) return [];
  const [cmd, ...rest] = w;
  const pkgs = (from) => rest.slice(from).filter((x) => !isFlag(x) && !x.startsWith(".") && !x.startsWith("/"));
  const idx = (...subs) => rest.findIndex((x) => subs.includes(x));
  switch (cmd) {
    case "npx": case "bunx": case "pnpx": {
      const p = rest.find((x) => !isFlag(x));
      return p ? [`npx ${p}`] : [];
    }
    case "npm": case "pnpm": case "yarn": case "bun": {
      const i = idx("i", "install", "add", "dlx", "x", "exec");
      if (i < 0) return [];
      return pkgs(i + 1).map((p) => `npm:${p}`);
    }
    case "pip": case "pip3": case "uv": {
      const i = idx("install", "add");
      if (i < 0) return [];
      return pkgs(i + 1).filter((p) => !p.includes("requirements")).map((p) => `pypi:${p}`);
    }
    case "uvx": case "pipx": {
      const r = rest[0] === "run" || rest[0] === "install" ? rest.slice(1) : rest;
      const p = r.find((x) => !isFlag(x));
      return p ? [`pypi:${p}`] : [];
    }
    case "claude": case "codex": {
      if (rest[0] !== "mcp" || rest[1] !== "add") return [];
      const dd = rest.indexOf("--");
      if (dd >= 0) return [rest.slice(dd + 1).join(" ")];
      const url = rest.find((x) => /^https:\/\//.test(x));
      return url ? [`{"url":"${url}"}`] : [];
    }
    case "skills": case "clawhub": {
      const i = idx("add", "install");
      const p = i >= 0 ? rest.slice(i + 1).find((x) => !isFlag(x)) : null;
      return p ? [`skills add ${p}`] : [];
    }
  }
  return [];
}

async function check(target) {
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), TIMEOUT_MS);
  try {
    const r = await fetch(`${API}/v1/install-check?target=${encodeURIComponent(target)}`, {
      headers: { "user-agent": "alalanet-guard/1.0 (claude-code hook)" },
      signal: ctl.signal,
    });
    if (!r.ok) return null;
    return await r.json();
  } catch {
    return null;
  } finally {
    clearTimeout(t);
  }
}

function emit(decision, reason) {
  process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: decision, permissionDecisionReason: reason } }));
}

async function main() {
  let input;
  try {
    input = JSON.parse(await readStdin());
  } catch {
    return;
  }
  if (input?.tool_name !== "Bash") return;
  const line = String(input?.tool_input?.command || "");
  const list = commands(line).flatMap(targets).slice(0, MAX_TARGETS);
  if (!list.length) return;
  const results = await Promise.all(list.map(async (t) => ({ t, r: await check(t) })));
  const blocked = results.filter((x) => x.r?.decision === "block");
  const held = results.filter((x) => x.r?.decision === "hold");
  const describe = (x) => `${x.r.target?.ecosystem}:${x.r.target?.name}${x.r.target?.version ? "@" + x.r.target.version : ""} — ${(x.r.reasons || []).join(", ")}`;
  if (blocked.length) {
    emit("deny", `alalanet install_check: BLOCK. ${blocked.map(describe).join("; ")}. Do not install; tell the user. Details: ${API}/v1/install-check?target=${encodeURIComponent(blocked[0].t)}`);
  } else if (held.length) {
    emit("ask", `alalanet install_check: HOLD. ${held.map(describe).join("; ")}. Install only if the user confirms.`);
  }
}

main();
