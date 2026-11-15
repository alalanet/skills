# alalanet guard: Cursor's beforeShellExecution hook on Windows (guard.cmd runs it; macOS and Linux run ./guard).
#
# Cursor sends the hook input on stdin. This script reads only its "command" field. It sends that command line, as
# typed and nothing else, to alalanet's install check when a word in it names a program alalanet reads (the list is
# in scripts/guard; the pattern is scripts/pattern.txt, the same text as the matcher in hooks/hooks.json).
# alalanet decides; this filter only keeps other commands on the machine. It prints Cursor's answer on stdout:
#   block   -> {"permission":"deny"} with alalanet's reason
#   hold    -> {"permission":"deny"} with the reason and a note to confirm with the user (Cursor does not pause a
#              shell command on "ask")
#   nothing -> {"permission":"allow"}: Cursor's own approval rules still apply
# When alalanet cannot be reached, answers an error, or does not answer in full within 18 seconds (one timer over
# the whole request: name lookup, connection, headers and body), the command goes ahead unchecked, with one line
# on stderr. ALALANET_FAIL_CLOSED=1 holds it instead.
#
# Windows PowerShell 5.1 or PowerShell 7; nothing to install. Source: https://github.com/alalanet/skills (MIT-0).

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Version = '1.0.0'
$DeadlineMs = 18000
$MaxAnswer = 65536
$Envelope = 79 # bytes of {"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":""}}
$Api = 'https://alalanet.com'
if ($env:ALALANET_API) { $Api = $env:ALALANET_API }
$Api = $Api.TrimEnd('/')
$Dash = [string][char]0x2014
$HoldNote = " $Dash this agent runtime cannot pause for the user here: confirm with the user before installing; if they agree, they can run it themselves."

# AsciiJson: JSON text with every non-ASCII character as a \u escape, so no code page can change it.
function AsciiJson([string]$Json) {
	return [regex]::Replace($Json, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
}

# Answer writes Cursor's answer and ends.
function Answer([string]$Permission, [string]$Message) {
	$o = [ordered]@{ permission = $Permission }
	if ($Message) { $o.user_message = $Message; $o.agent_message = $Message }
	[Console]::Out.Write((AsciiJson (ConvertTo-Json -InputObject $o -Compress)) + "`n")
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

# Only lines that name a program alalanet reads leave the machine.
try { $Pattern = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'pattern.txt')).Trim() } catch { $Pattern = '' }
if (-not $Pattern) { Hold "the plugin's pattern file is missing" }
# Compiled: about ten times faster than the interpreter on long lines; the pattern has no nested repetition.
try {
	$rx = New-Object System.Text.RegularExpressions.Regex($Pattern, [System.Text.RegularExpressions.RegexOptions]::Compiled, [TimeSpan]::FromSeconds(5))
	$named = $rx.IsMatch($command)
} catch { NotChecked 'the command could not be read in time' }
if (-not $named) { Answer 'allow' }

if ($Api -notmatch '^(https://|http://(127\.0\.0\.1|localhost):[0-9]+(/|$))') {
	Hold 'ALALANET_API is not an https URL (plain http only to 127.0.0.1 or localhost)'
}
if ([Text.Encoding]::UTF8.GetByteCount($command) -gt (1048576 - $Envelope)) { Hold 'the command is too large for alalanet to read' }
$body = AsciiJson (ConvertTo-Json -Compress -Depth 3 -InputObject ([ordered]@{
	hook_event_name = 'PreToolUse'; tool_name = 'Bash'; tool_input = [ordered]@{ command = $command } }))

try {
	Add-Type -AssemblyName System.Net.Http
	[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
	$handler = New-Object System.Net.Http.HttpClientHandler
	$handler.AllowAutoRedirect = $false
	$client = New-Object System.Net.Http.HttpClient($handler)
	$client.Timeout = [TimeSpan]::FromMilliseconds($DeadlineMs)
	$client.MaxResponseContentBufferSize = $MaxAnswer
	$null = $client.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', "alalanet-guard-cursor/$Version (hook cursor)")
	$content = New-Object System.Net.Http.ByteArrayContent(, [Text.Encoding]::ASCII.GetBytes($body))
	$content.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue('application/json')
	$task = $client.PostAsync("$Api/v1/hooks/claude-code", $content)
} catch { NotChecked 'the request to alalanet could not be made' }
# One timer over the whole request, whatever the runtime does with its own timeouts.
$done = $false
try { $done = $task.Wait($DeadlineMs) } catch { $done = $true }
if (-not $done) { NotChecked 'alalanet did not answer in full within 18 seconds' }
if ($task.IsCanceled) { NotChecked 'alalanet did not answer in full within 18 seconds' }
if ($task.IsFaulted) {
	$e = $task.Exception.GetBaseException()
	if ($e.Message -match 'buffer|size') { NotChecked "alalanet's answer is larger than $MaxAnswer bytes" }
	NotChecked 'alalanet could not be reached'
}
$r = $task.Result
if ([int]$r.StatusCode -ne 200) { NotChecked ("alalanet answered HTTP " + [int]$r.StatusCode) }
$bytes = $r.Content.ReadAsByteArrayAsync().Result
if ($bytes.Length -gt $MaxAnswer) { NotChecked "alalanet's answer is larger than $MaxAnswer bytes" }
$answer = [Text.Encoding]::UTF8.GetString($bytes)
$values = $null
$dailyLimit = $r.Headers.TryGetValues('Alalanet-Not-Checked', [ref]$values) -and (@($values) -contains 'daily-limit')

if ($answer.Trim() -eq '') { Answer 'allow' }
try { $a = ConvertFrom-Json -InputObject $answer } catch { NotChecked "alalanet's answer could not be read" }
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
		if ($dailyLimit) { NotChecked "alalanet's daily limit for this address is reached" }
		if (-not $reason) { $reason = 'alalanet install_check: HOLD. Install only if the user confirms.' }
		Answer 'deny' ($reason + $HoldNote)
	}
}
NotChecked "alalanet's answer could not be read"
