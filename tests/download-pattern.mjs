// The download-and-run filter of alalanet-guard's Claude Code hook (scripts/download-pattern.txt), built from its parts:
// node tests/download-pattern.mjs > plugins/alalanet-guard/scripts/download-pattern.txt writes it, and
// tests/agent-plugin.test.mjs checks the file is this text. One regular expression read by grep -Ei (scripts/
// download-guard, after \s inside brackets becomes [:space:]) and by .NET (scripts/download-guard.ps1, IgnoreCase):
// \s only inside brackets; no lookaround, no backreference, no inline flag. Every quantifier that can meet a long run
// of one kind of character is bounded (at most 255, POSIX grep's limit) or meets a character class that ends it, so .NET's backtracking engine reads a
// 64 KiB line (the scripts' limit) in well under a second (tests/agent-plugin.test.mjs, the adversarial shapes).
const N = "['\"`\\\\]{0,8}"; // quotes, backticks and backslashes a POSIX shell or PowerShell removes between letters
const w = (word) => [...word].map((c) => ("[]().$|*+?{}^\\".includes(c) ? "\\" + c : c)).join(N);
const alt = (words) => "(" + words.map(w).join("|") + ")";

// the downloads, and the end of a word
const D = alt(["curl", "wget", "irm", "iwr", "invoke-restmethod", "invoke-webrequest", "downloadstring"]);
const E = "([^a-z0-9_-]|$)";
// the runners: shells and Invoke-Expression, which run their input whatever else they are given
const RS = "(" + alt(["sh", "bash", "zsh", "dash", "ksh", "fish", "pwsh", "powershell", "iex", "invoke-expression", "eval",
  "source"]) + "|\\$\\{?" + w("shell") + ")";
// interpreters, which run their input only with no script or code of their own: python3, python3 -, node -u; not
// python3 -m json.tool, python3 -c '…', node -e, perl -e, ruby -e, php -r (they read the download as data)
const RI = "(" + alt(["node", "nodejs", "perl", "ruby", "php"]) + "|" + w("python") + "[0-9.]{0,8})";
const TI = "([\\s]{1,40}-[abdfghijklnoqstuvwxyz0-9]{0,40}){0,8}[\\s'\"]{0,40}($|[|;&)}])";
const R = "(" + RS + "|" + RI + ")";
// where a command starts, after the separator: blanks, the call and dot-source operators, groups, quotes, $'…', ;
const S = "[\\s&.('\"$;]{0,16}";
// leading assignments (NONINTERACTIVE=1 bash -c "$(curl …)")
const ASSIGN = "([a-z_][a-z0-9_]{0,64}=[^\\s|;&]{0,255}[\\s]{1,40}){0,8}";
// a runner's usual folders (/bin/sh, /usr/bin/bash, /usr/local/bin/zsh)
const PFX = "((/usr(/local)?)?/s?bin/)?";
// one wrapper the runner may stand after, with its options and assignments: sudo -E, env A=1, a package runner
const TOK = "([\\s]{1,40}(-[^\\s|;&]{0,64}|[a-z_][a-z0-9_]{0,64}=[^\\s|;&]{0,255})){0,8}[\\s]{1,40}";
const WRAP = "(" + PFX + "(" + alt(["sudo", "doas", "env", "exec", "command", "nohup", "time", "nice", "xargs", "stdbuf", "timeout",
  "busybox", "uvx", "npx", "pnpx", "bunx"]).slice(1, -1) + "|" + w("uv") + "[\\s]{1,40}" + w("run") + "|" + w("pnpm") + "[\\s]{1,40}(" + w("exec") +
  "|" + w("dlx") + ")|" + w("bun") + "[\\s]{1,40}x|" + w("yarn") + "[\\s]{1,40}" + w("dlx") + "|" + w("pipx") + "[\\s]{1,40}" + w("run") + ")" + TOK + ")";
// a scriptblock the pipe feeds (% { … }, ForEach-Object -Process { … }, & { process { … } }), to the statement in it
// that runs: each statement before it skipped to its ; or {
const BLOCK = "((%|" + w("foreach-object") + "|" + w("where-object") + "|&|\\.)?([\\s]{1,40}-[a-z]{1,40}){0,4}[\\s]{0,40}\\{([^;{}|]{0,255}[;{]){0,8}[\\s]{0,40})";
const CMD = S + "(" + BLOCK + S + ")?" + ASSIGN + "(" + WRAP + S + ")?" + PFX;
// (a) a download piped into a runner in the same statement: curl … | sh, irm … | % { iex $_ }
// between the download and the pipe: the rest of the statement, a quoted part whole (curl "https://e.example/x;y" | sh);
// the quotes that end the download's word (irm"" U, 'irm' U) are its own (N), and one quote right after a ")" may close
// the string a substitution of the download stood in (echo "$(curl …)" | sh) — only there, so a quoted URL holding
// "|sh" (curl -s "https://…?a=1|sh") is no pipe
const GAP = "(\"[^\"]{0,255}\"|'[^']{0,255}'|[^;\"']){0,255}(\\)[\"'][^;\"']{0,255})?";
const a = "(^|[^a-z0-9_])" + D + N + E + GAP + "[;\\s]{0,40}\\|" + CMD + "(" + RS + E + "|" + RI + TI + ")";
// (b) a runner given a download in a substitution, a group or a here-string: sh -c "$(curl …)", bash <(curl …), iex (irm …)
const OPEN = "(\\$\\(|<\\(|`|\\(|@['\"])";
const b = "(^|[|;&({}`\\[>]|(" + alt(["then", "do", "else"]) + ")[\\s])" + CMD + R + "([^a-z0-9_;|-][^;|]{0,40})?" + OPEN +
  "([\\s;'\"&.({]{0,40}|[^;]{0,255}[^a-z0-9_;])" + D + E;
// (c) the engine's runners given a group: [scriptblock]::Create(…), .InvokeScript(…), .NewScriptBlock(…)
const c = "(" + w("[scriptblock]::create") + "|\\." + w("invokescript") + "|\\." + w("newscriptblock") + ")[\\s]{0,40}\\([^;]{0,255}[^a-z0-9_;]" + D + E;

export const downloadPattern = a + "|" + b + "|" + c;

if (import.meta.url === `file://${process.argv[1]}`) process.stdout.write(downloadPattern + "\n");
