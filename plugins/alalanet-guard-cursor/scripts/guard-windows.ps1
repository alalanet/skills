# alalanet guard: Cursor's beforeShellExecution hook on Windows (guard.cmd runs it; macOS and Linux run ./guard).
#
# Cursor sends the hook input on stdin. This script reads only its "command" field, and sends that command line, and
# nothing else, to alalanet's install check when it installs or runs a package (the pattern below, the same one as
# the matcher in hooks/hooks.json). It prints Cursor's answer on stdout:
#   block   -> {"permission":"deny"} with alalanet's reason
#   hold    -> {"permission":"deny"} with the reason and a note to confirm with the user (Cursor does not pause a
#              shell command on "ask")
#   nothing -> {"permission":"allow"}: Cursor's own approval rules still apply
# When alalanet cannot be reached or does not answer within 20 seconds, the command goes ahead unchecked, with one
# line on stderr. ALALANET_FAIL_CLOSED=1 holds it instead.
#
# Windows PowerShell 5.1 or PowerShell 7; nothing to install. Source: https://github.com/alalanet/skills (MIT-0).

$ErrorActionPreference = 'Stop'
$Version = '1.0.0'
$Api = 'https://alalanet.com'
if ($env:ALALANET_API) { $Api = $env:ALALANET_API.TrimEnd('/') }
$Dash = [string][char]0x2014
$HoldNote = " $Dash this agent runtime cannot pause for the user here: confirm with the user before installing; if they agree, they can run it themselves."

# The install commands, in the same syntax as the matcher in hooks/hooks.json (.NET reads JavaScript's here).
$B = '(^|[\s;&|(`''"/])'
$E = '([\s;&|)`''"]|$)'
$W = '(\s+[^\s;&|]+)*'
$Pattern = $B + '((npm|pnpm|yarn|bun)(\.cmd|\.exe)?' + $W + '\s+(install|i|add|dlx|exec|x)' + $E +
	'|(npx|pnpx|bunx|uvx)(\.cmd|\.exe)?\s+[^\s;&|]' +
	'|(pip|pip3)(\.exe)?' + $W + '\s+install' + $E +
	'|pipx(\.exe)?' + $W + '\s+(install|run|inject|runpip)' + $E +
	'|uv(\.exe)?' + $W + '\s+(add|install)' + $E +
	'|uv(\.exe)?\s+tool\s+run' + $E +
	'|uv(\.exe)?\s+run' + $W + '\s+--with([\s=]|$)' +
	'|(python[0-9.]*|py)(\.exe)?\s+-m\s+(pip|pip3|uv|pipx)' + $W + '\s+(install|add|run|inject|runpip)' + $E +
	'|deno(\.exe)?' + $W + '\s+[''"]?(npm:|jsr:|https://)' +
	'|(claude|codex|gemini)(\.cmd|\.exe)?\s+mcp\s+add' + $E +
	'|(skills|clawhub)(\.cmd|\.exe)?\s+(add|install|a|i)' + $E +
	'|--install-extension([\s=]|$))'

# Answer writes Cursor's answer as ASCII JSON (non-ASCII as \u escapes, whatever the console code page) and ends.
function Answer([string]$Permission, [string]$Message) {
	$o = [ordered]@{ permission = $Permission }
	if ($Message) { $o.user_message = $Message; $o.agent_message = $Message }
	$j = ConvertTo-Json -InputObject $o -Compress
	$j = [regex]::Replace($j, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
	[Console]::Out.Write($j + "`n")
	exit 0
}

function Hold([string]$Why) {
	Answer 'deny' ("alalanet install_check: NOT CHECKED $Dash $Why. Install only if the user confirms." + $HoldNote)
}

# NotChecked: alalanet did not check the install. It goes ahead (stderr says so), or is held with ALALANET_FAIL_CLOSED=1.
function NotChecked([string]$Why) {
	if ($env:ALALANET_FAIL_CLOSED -eq '1') { Hold $Why }
	[Console]::Error.WriteLine("alalanet guard: the install was not checked ($Why); it goes ahead. ALALANET_FAIL_CLOSED=1 holds such installs.")
	Answer 'allow'
}

# The input as UTF-8 bytes, whatever the console code page; Cursor on Windows may put a byte-order mark first.
try {
	$ms = New-Object System.IO.MemoryStream
	[Console]::OpenStandardInput().CopyTo($ms)
	$text = [Text.Encoding]::UTF8.GetString($ms.ToArray()).TrimStart([char]0xFEFF)
	$hook = ConvertFrom-Json -InputObject $text
} catch { Hold 'the hook could not read its input' }

$command = $null
if ($hook -and $hook.PSObject.Properties['command']) { $command = $hook.command }
elseif ($hook -and $hook.PSObject.Properties['tool_input'] -and $hook.tool_input.PSObject.Properties['command']) { $command = $hook.tool_input.command }
elseif ($text -notmatch '"command"') { Answer 'allow' } # not a shell command
if ($command -isnot [string]) { Hold 'the hook could not read the command' }

# Only install commands leave the machine.
if (-not [regex]::IsMatch($command, $Pattern)) { Answer 'allow' }

if (-not ($Api -match '^https://' -or $Api -match '^http://(127\.0\.0\.1|localhost):')) { Hold 'ALALANET_API is not an https URL' }
$body = ConvertTo-Json -Compress -Depth 3 -InputObject ([ordered]@{
	hook_event_name = 'PreToolUse'; tool_name = 'Bash'; tool_input = [ordered]@{ command = $command } })
$bytes = [Text.Encoding]::UTF8.GetBytes($body)
if ($bytes.Length -gt 1048576) { Hold 'the command is too large for alalanet to read' }

try {
	[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
	$r = Invoke-WebRequest -Uri "$Api/v1/hooks/claude-code" -Method Post -Body $bytes -ContentType 'application/json' `
		-UserAgent "alalanet-guard-cursor/$Version (hook cursor)" -TimeoutSec 20 -UseBasicParsing -MaximumRedirection 0
} catch {
	$code = $null
	if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
	if ($code) { NotChecked "alalanet answered HTTP $code" }
	NotChecked 'alalanet could not be reached'
}
if ($r.StatusCode -ne 200) { NotChecked ("alalanet answered HTTP " + $r.StatusCode) }

$content = [string]$r.Content
if ($content.Trim() -eq '') { Answer 'allow' }
try { $a = ConvertFrom-Json -InputObject $content } catch { NotChecked "alalanet's answer could not be read" }
$out = $null
if ($a -and $a.PSObject.Properties['hookSpecificOutput']) { $out = $a.hookSpecificOutput }
if (-not $out -or -not $out.PSObject.Properties['permissionDecision']) { NotChecked "alalanet's answer could not be read" }
$reason = [string]$out.permissionDecisionReason
switch ([string]$out.permissionDecision) {
	'deny' {
		if (-not $reason) { $reason = 'alalanet install_check: BLOCK. Do not install; tell the user.' }
		Answer 'deny' $reason
	}
	'ask' {
		if ([string]$r.Headers['Alalanet-Not-Checked'] -eq 'daily-limit') { NotChecked "alalanet's daily limit for this address is reached" }
		if (-not $reason) { $reason = 'alalanet install_check: HOLD. Install only if the user confirms.' }
		Answer 'deny' ($reason + $HoldNote)
	}
}
NotChecked "alalanet's answer could not be read"
