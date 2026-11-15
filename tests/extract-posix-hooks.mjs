// Writes the POSIX hook commands of plugins/alalanet-guard to <dir> as scripts, for shellcheck:
//   copilot.sh (the Copilot bash field), codex.sh (the Codex command, sh -c '...'), codex-inner.sh (the script it runs).
// Usage: node tests/extract-posix-hooks.mjs <dir>
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import path from "node:path";

const dir = process.argv[2];
if (!dir) throw new Error("usage: node tests/extract-posix-hooks.mjs <dir>");
mkdirSync(dir, { recursive: true });
const plugin = path.join(path.dirname(new URL(import.meta.url).pathname), "..", "plugins", "alalanet-guard");
const load = (p) => JSON.parse(readFileSync(path.join(plugin, p), "utf8"));
const copilot = load("com.github.copilot/hooks/hooks.json").hooks.preToolUse[0].bash;
const codex = load("com.openai/hooks/hooks.json").hooks.PreToolUse[0].hooks[0].command;
const inner = codex.match(/^sh -c '([^']*)'$/);
if (!inner) throw new Error("the Codex command is not one single-quoted sh -c script");
writeFileSync(path.join(dir, "copilot.sh"), `#!/bin/bash\n${copilot}\n`);
writeFileSync(path.join(dir, "codex.sh"), `#!/bin/sh\n${codex}\n`);
writeFileSync(path.join(dir, "codex-inner.sh"), `#!/bin/sh\n${inner[1]}\n`);
