# alalanet guard: Claude Code's hook for the download commands in the PowerShell tool (Windows); the Bash tool runs
# scripts/download-guard, which says what is sent and when. This script does the same: it reads only the hook input's
# tool_input.command, tests it against scripts/download-pattern.txt (the same text), and sends the line, as typed and
# nothing else, to alalanet's install check only when a download in it feeds a runner. Every other command stays on
# the machine: nothing is sent, nothing is printed. It prints Claude Code's answer (permissionDecision "deny" on block,
# "ask" on hold, nothing on allow); when alalanet cannot be reached or does not answer within 18 seconds, the command
# goes ahead unchecked, with one line on stderr.
#
# hooks/hooks.json runs it in the PowerShell Claude Code starts ("shell": "powershell"), from its text, so neither the
# execution policy nor a program in the workspace decides what runs. Windows PowerShell 5.1 or PowerShell 7.
# Source: https://github.com/alalanet/skills (MIT-0).

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Version = '1.5.1'
$DeadlineMs = 18000
$MaxAnswer = 65536
$Api = 'https://alalanet.com'
if ($env:ALALANET_API) { $Api = $env:ALALANET_API }
$Api = $Api.TrimEnd('/')
$Dash = [string][char]0x2014

# AsciiJson: JSON text with every non-ASCII character as a \u escape, so no code page can change it.
function AsciiJson([string]$Json) {
	return [regex]::Replace($Json, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
}

# Decide writes Claude Code's answer and ends.
function Decide([string]$Decision, [string]$Reason) {
	$o = [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = 'PreToolUse'; permissionDecision = $Decision; permissionDecisionReason = $Reason } }
	[Console]::Out.Write((AsciiJson (ConvertTo-Json -InputObject $o -Compress -Depth 3)) + "`n")
	exit 0
}

# NotChecked: alalanet did not check the command; it goes ahead.
function NotChecked([string]$Why) {
	[Console]::Error.WriteLine("alalanet guard: this download-and-run command was not checked ($Why); it goes ahead.")
	exit 0
}

try {
	$ms = New-Object System.IO.MemoryStream
	[Console]::OpenStandardInput().CopyTo($ms)
	$text = [Text.Encoding]::UTF8.GetString($ms.ToArray()).TrimStart([char]0xFEFF)
	$hook = ConvertFrom-Json -InputObject $text
} catch { NotChecked 'the hook could not read its input' }
$command = $null
if ($hook -and $hook.PSObject.Properties['tool_input'] -and $hook.tool_input.PSObject.Properties['command']) { $command = $hook.tool_input.command }
if ($command -isnot [string] -or $command -eq '') { exit 0 } # not a shell command

# The filter reads the line as one: a backtick-newline (PowerShell's) or backslash-newline (a POSIX shell's) removed, a
# newline as a separator (" ; ").
try { $Pattern = [IO.File]::ReadAllText((Join-Path $env:CLAUDE_PLUGIN_ROOT 'scripts/download-pattern.txt')).Trim() } catch { $Pattern = '' }
if (-not $Pattern) { NotChecked "the plugin's pattern file is missing" }
$plain = [regex]::Replace([regex]::Replace($command, '[`\\]\r?\n', ''), '\r?\n|\r', ' ; ')
# The pattern is read on lines up to 64 KiB (its bounded quantifiers keep it under about a second there); a longer
# line, or one the pattern cannot finish in 5 seconds, is held for the user here, and not sent.
$notRead = "alalanet install_check: NOT CHECKED $Dash a download command line {0} is not read on this machine and was not sent. Run it only if the user confirms."
if ($plain.Length -gt 65536) { Decide 'ask' ($notRead -f 'longer than 64 KiB') }
try {
	$opt = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
	$rx = New-Object System.Text.RegularExpressions.Regex($Pattern, $opt, [TimeSpan]::FromSeconds(5))
	$runs = $rx.IsMatch($plain)
} catch [System.Text.RegularExpressions.RegexMatchTimeoutException] { Decide 'ask' ($notRead -f 'the filter could not read in 5 seconds') } catch { NotChecked "the plugin's pattern could not be read" }
if (-not $runs) { exit 0 }

if ($Api -notmatch '^(https://|http://(127\.0\.0\.1|localhost):[0-9]+(/|$))') {
	NotChecked 'ALALANET_API is not an https URL (plain http only to 127.0.0.1 or localhost)'
}
$body = AsciiJson (ConvertTo-Json -Compress -Depth 3 -InputObject ([ordered]@{
	hook_event_name = 'PreToolUse'; tool_name = 'PowerShell'; tool_input = [ordered]@{ command = $command } }))
if ($body.Length -gt 1048576) {
	Decide 'ask' "alalanet install_check: NOT CHECKED $Dash the command is too large for alalanet to read. Run it only if the user confirms."
}

$clock = [Diagnostics.Stopwatch]::StartNew()
function Left { return [int][Math]::Max(0, $DeadlineMs - $clock.ElapsedMilliseconds) }
function Finished($t) { try { return $t.Wait((Left)) } catch { return $true } }
function Late { NotChecked 'alalanet did not answer in full within 18 seconds' }

try {
	Add-Type -AssemblyName System.Net.Http
	[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
	$handler = New-Object System.Net.Http.HttpClientHandler
	$handler.AllowAutoRedirect = $false
	$client = New-Object System.Net.Http.HttpClient($handler)
	$client.Timeout = [TimeSpan]::FromMilliseconds($DeadlineMs)
	$null = $client.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', "alalanet-guard/$Version (hook claude-code download)")
	$request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, "$Api/v1/hooks/claude-code")
	# the free device key and the plan token, as the HTTP hooks send them; each only when it reads as one
	$deviceKey = "$env:ALALANET_DEVICE_KEY".Trim()
	if ($deviceKey -cmatch '^ald_[a-z0-9_]{1,124}$') { $null = $request.Headers.TryAddWithoutValidation('X-Alalanet-Device-Key', $deviceKey) }
	$token = "$env:ALALANET_TOKEN".Trim()
	if ($token -cmatch '^[A-Za-z0-9._~+/=-]{1,4096}$') { $null = $request.Headers.TryAddWithoutValidation('Authorization', "Bearer $token") }
	$request.Content = New-Object System.Net.Http.ByteArrayContent(, [Text.Encoding]::ASCII.GetBytes($body))
	$request.Content.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue('application/json')
	$task = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
} catch { NotChecked 'the request to alalanet could not be made' }
if (-not (Finished $task)) { Late }
if ($task.IsCanceled) { Late }
if ($task.IsFaulted) { NotChecked 'alalanet could not be reached' }
$r = $task.Result
if ([int]$r.StatusCode -ne 200) { NotChecked ("alalanet answered HTTP " + [int]$r.StatusCode) }
$st = $r.Content.ReadAsStreamAsync()
if (-not (Finished $st)) { Late }
if ($st.IsFaulted -or $st.IsCanceled) { NotChecked "alalanet's answer could not be read" }
$stream = $st.Result
$buf = New-Object byte[] ($MaxAnswer + 1)
$n = 0
while ($n -lt $buf.Length) {
	$rd = $stream.ReadAsync($buf, $n, $buf.Length - $n)
	if (-not (Finished $rd)) { Late }
	if ($rd.IsFaulted -or $rd.IsCanceled) { NotChecked "alalanet's answer could not be read" }
	if ($rd.Result -eq 0) { break }
	$n += $rd.Result
}
if ($n -gt $MaxAnswer) { NotChecked "alalanet's answer is larger than $MaxAnswer bytes" }
$answer = [Text.Encoding]::UTF8.GetString($buf, 0, $n)
if ($answer.Trim() -eq '') { exit 0 } # allow: nothing to say
try { $a = ConvertFrom-Json -InputObject $answer } catch { NotChecked "alalanet's answer could not be read" }
$out = $null
if ($a -and $a.PSObject.Properties['hookSpecificOutput']) { $out = $a.hookSpecificOutput }
if (-not $out -or -not $out.PSObject.Properties['permissionDecision']) { NotChecked "alalanet's answer could not be read" }
$reason = [string]$out.permissionDecisionReason
switch ([string]$out.permissionDecision) {
	'deny' {
		if (-not $reason) { $reason = 'alalanet install_check: BLOCK. Do not run it; tell the user.' }
		Decide 'deny' $reason
	}
	'ask' {
		if (-not $reason) { $reason = 'alalanet install_check: HOLD. Run it only if the user confirms.' }
		Decide 'ask' $reason
	}
}
NotChecked "alalanet's answer could not be read"
