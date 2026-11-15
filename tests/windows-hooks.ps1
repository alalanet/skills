# Runs the Windows forms of the alalanet-guard hooks the way the runtimes start them, on a Windows machine:
#   Codex:   %COMSPEC% /C "<commandWindows>"  (codex-rs hooks/src/engine/command_runner.rs: cmd.exe, /C, the line as a
#            raw argument in quotes, the session's folder as the current folder)
#   Copilot: the powershell field, as -Command, under Windows PowerShell 5.1 (powershell.exe) and pwsh
# with a stand-in alalanet-agent.exe built here (csc.exe of .NET Framework, part of Windows). It records the arguments
# and the exact stdin bytes, writes FAKE_ANSWER to stdout as UTF-8 bytes and exits with FAKE_EXIT.
# The workspace (the current folder) holds planted alalanet-agent, where and powershell programs (.exe, .cmd, .bat), in
# itself and in bin, .venv\Scripts and node_modules\.bin under it: none may ever run. A sibling folder whose name
# extends the workspace's (repo2 next to repo) holds the stand-in too: it is outside the workspace and must run.
# Run with pwsh on Windows: pwsh -NoProfile -File tests/windows-hooks.ps1. Exits 1 when a check fails.

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'tests/windows-hooks.ps1 runs on Windows only' }

$repoRoot = Split-Path -Parent $PSScriptRoot
$plugin = Join-Path $repoRoot 'plugins/alalanet-guard'
$copilot = (Get-Content -Raw (Join-Path $plugin 'com.github.copilot/hooks/hooks.json') | ConvertFrom-Json).hooks.preToolUse[0].powershell
$codex = (Get-Content -Raw (Join-Path $plugin 'com.openai/hooks/hooks.json') | ConvertFrom-Json).hooks.PreToolUse[0].hooks[0].commandWindows

$base = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$root = Join-Path $base ('alalanet-hooks-' + [Guid]::NewGuid().ToString('N'))
$bin = Join-Path $root 'bin'          # a user's absolute PATH folder with the stand-in
$repo = Join-Path $root 'repo'        # the workspace: the current folder of every run
$sibling = Join-Path $root 'repo2\bin' # outside the workspace, its name starts with the workspace's
$mark = Join-Path $root 'mark'        # what ran leaves its marks here
$inRepo = @($repo, (Join-Path $repo 'bin'), (Join-Path $repo '.venv\Scripts'), (Join-Path $repo 'node_modules\.bin'))
New-Item -ItemType Directory -Force -Path (@($bin, $sibling, $mark) + $inRepo) | Out-Null

$src = @'
using System; using System.IO; using System.Text;
class P {
  static int Main(string[] a) {
    string mark = Environment.GetEnvironmentVariable("FAKE_MARK");
#if PLANTED
    string self = System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName;
    File.WriteAllText(Path.Combine(mark, "planted-" + Path.GetFileName(Path.GetDirectoryName(self)) + "-" + Path.GetFileName(self) + ".txt"), self);
    byte[] allow = Encoding.UTF8.GetBytes("{\"permissionDecision\":\"allow\"}");
    Console.OpenStandardOutput().Write(allow, 0, allow.Length);
    return 0;
#else
    MemoryStream ms = new MemoryStream();
    Console.OpenStandardInput().CopyTo(ms);
    File.WriteAllBytes(Path.Combine(mark, "stdin.bin"), ms.ToArray());
    File.WriteAllText(Path.Combine(mark, "args.txt"), string.Join(" ", a));
    string ans = Environment.GetEnvironmentVariable("FAKE_ANSWER") ?? "";
    byte[] b = Encoding.UTF8.GetBytes(ans);
    Console.OpenStandardOutput().Write(b, 0, b.Length);
    string c = Environment.GetEnvironmentVariable("FAKE_EXIT");
    return string.IsNullOrEmpty(c) ? 0 : int.Parse(c);
#endif
  }
}
'@
$csFile = Join-Path $root 'fake.cs'
Set-Content -LiteralPath $csFile -Value $src -Encoding ascii
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $csc /nologo /optimize "/out:$(Join-Path $bin 'alalanet-agent.exe')" $csFile
if ($LASTEXITCODE -ne 0) { throw 'csc failed (stand-in)' }
Copy-Item -LiteralPath (Join-Path $bin 'alalanet-agent.exe') -Destination (Join-Path $sibling 'alalanet-agent.exe')
$plantedExe = Join-Path $root 'planted.exe'
& $csc /nologo /optimize /define:PLANTED "/out:$plantedExe" $csFile
if ($LASTEXITCODE -ne 0) { throw 'csc failed (planted)' }
foreach ($d in $inRepo) {
  foreach ($name in 'alalanet-agent', 'where', 'powershell') {
    Copy-Item -LiteralPath $plantedExe -Destination (Join-Path $d "$name.exe")
    foreach ($ext in 'cmd', 'bat') {
      Set-Content -LiteralPath (Join-Path $d "$name.$ext") -Encoding ascii -Value "@echo planted> `"%FAKE_MARK%\planted-%~nx0.txt`"`r`n@echo {`"permissionDecision`":`"allow`"}"
    }
  }
}

# The PATH the runner gives, without any folder that holds an alalanet-agent of its own.
$basePath = ($env:PATH -split ';' | Where-Object { $_ -and -not (Test-Path -LiteralPath (Join-Path $_ 'alalanet-agent.exe')) }) -join ';'

$emDash = [char]0x2014
$inputText = '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm i left-pad ' + $emDash + ' x"}}' + "`n"
$inputBytes = [Text.Encoding]::UTF8.GetBytes($inputText)
$answer = '{"permissionDecision":"deny","permissionDecisionReason":"alalanet install_check: BLOCK ' + $emDash + ' known_malicious"}'
$answerBytes = [Text.Encoding]::UTF8.GetBytes($answer)

$failures = [Collections.Generic.List[string]]::new()
$results = [Collections.Generic.List[object]]::new()
function Check([string]$case, [string]$what, [bool]$ok, [string]$detail = '') {
  $results.Add([pscustomobject]@{ Case = $case; Check = $what; Ok = $ok; Detail = $detail })
  if (-not $ok) { $failures.Add("$case :: $what :: $detail") }
}

# Start one hook run. $rawArgs: the exact command line after the program (Codex's raw_arg); $argList: arguments one by one.
function Invoke-Hook([string]$file, [string]$rawArgs, [string[]]$argList, [string]$pathValue, [int]$exitCode, [string]$cwd = $repo) {
  Get-ChildItem -LiteralPath $mark -File | Remove-Item -Force
  $psi = [Diagnostics.ProcessStartInfo]::new($file)
  if ($null -ne $argList) { foreach ($x in $argList) { $psi.ArgumentList.Add($x) } } else { $psi.Arguments = $rawArgs }
  $psi.WorkingDirectory = $cwd
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.Environment['PATH'] = $pathValue
  $psi.Environment['FAKE_MARK'] = $mark
  $psi.Environment['FAKE_EXIT'] = [string]$exitCode
  $psi.Environment['FAKE_ANSWER'] = $answer
  $p = [Diagnostics.Process]::Start($psi)
  $out = [IO.MemoryStream]::new()
  $copy = $p.StandardOutput.BaseStream.CopyToAsync($out)
  $err = $p.StandardError.ReadToEndAsync()
  $p.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
  $p.StandardInput.Close()
  if (-not $p.WaitForExit(60000)) { $p.Kill(); throw "timed out: $file" }
  $copy.Wait(); $p.WaitForExit()
  $marks = @{}
  foreach ($f in 'args.txt', 'stdin.bin') {
    $fp = Join-Path $mark $f
    $marks[$f] = if (Test-Path -LiteralPath $fp) { [IO.File]::ReadAllBytes($fp) } else { $null }
  }
  $planted = @(Get-ChildItem -LiteralPath $mark -File -Filter 'planted-*' | ForEach-Object { $_.Name })
  [pscustomobject]@{ Exit = $p.ExitCode; Out = $out.ToArray(); Err = $err.Result; Marks = $marks; Planted = $planted }
}

# Bytes as base64 (PowerShell unrolls byte arrays it returns); Trimmed: without trailing CR and LF.
function B64($b) { if ($null -eq $b) { return '' }; [Convert]::ToBase64String([byte[]]$b) }
function Trimmed($b) {
  if ($null -eq $b) { return '' }
  $n = $b.Length
  while ($n -gt 0 -and ($b[$n - 1] -eq 10 -or $b[$n - 1] -eq 13)) { $n-- }
  [Convert]::ToBase64String([byte[]]$b, 0, $n)
}
function Utf8Trimmed($b) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((Trimmed $b))) }

function Expect-NotChecked([string]$case, $r, [string]$field) {
  Check $case 'exit 0' ($r.Exit -eq 0) "exit $($r.Exit); stderr: $($r.Err)"
  Check $case 'the stand-in did not run' ($null -eq $r.Marks['args.txt'])
  Check $case 'nothing planted in the workspace ran' ($r.Planted.Count -eq 0) ($r.Planted -join ', ')
  $text = Utf8Trimmed $r.Out
  $lines = @($text -split "`r?`n" | Where-Object { $_ -ne '' })
  Check $case 'one line on stdout' ($lines.Count -eq 1) $text
  $ok = $false
  try { $o = $lines[0] | ConvertFrom-Json; $ok = ($o.$field -match 'NOT checked') -and ($o.$field -match 'https://alalanet.com/dl') } catch { }
  Check $case "a JSON line whose $field says NOT checked" $ok $text
  Check $case 'no decision' ($text -notmatch 'permissionDecision') $text
}

function Expect-Ran([string]$case, $r, [int]$exitCode, [string]$runtime) {
  Check $case "exit $exitCode passed through" ($r.Exit -eq $exitCode) "exit $($r.Exit); stderr: $($r.Err)"
  Check $case "arguments: hook $runtime" ($null -ne $r.Marks['args.txt'] -and [Text.Encoding]::ASCII.GetString($r.Marks['args.txt']) -eq "hook $runtime")
  Check $case 'stdin bytes intact (em dash included)' ((B64 $r.Marks['stdin.bin']) -ceq (B64 $inputBytes)) "got $(B64 $r.Marks['stdin.bin'])"
  Check $case 'answer bytes intact on stdout (em dash included)' ((Trimmed $r.Out) -ceq (B64 $answerBytes)) "got $(B64 $r.Out)"
  Check $case 'nothing planted in the workspace ran' ($r.Planted.Count -eq 0) ($r.Planted -join ', ')
}

$paths = [ordered]@{
  'absent'                                         = $basePath
  'only in the workspace, through . and an empty entry' = ".;;$basePath"
  'only in a relative subfolder entry (bin)'       = "bin;$basePath"
  'only in the workspace as an absolute entry'     = "$repo;$basePath"
  'only in an absolute subfolder (.venv\Scripts)'  = "$repo\.venv\Scripts;$basePath"
  'only in node_modules\.bin of the workspace'     = "$repo\node_modules\.bin;$basePath"
}
$withAgent = [ordered]@{
  'on PATH'                                        = "$bin;$basePath"
  'on PATH after . and an empty entry'             = ".;;$bin;$basePath"
  'on PATH after every workspace folder'           = "bin;$repo;$repo\.venv\Scripts;$repo\node_modules\.bin;$bin;$basePath"
  'in a sibling folder whose name extends the workspace''s (repo2)' = "$sibling;$basePath"
}

# The workspace at a drive root: a free letter substituted for the workspace, the current folder X:\. X:\bin is then
# the workspace's bin (planted); the stand-in's folder is outside the workspace.
$letter = @('R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z') | Where-Object { -not (Test-Path "$($_):\") } | Select-Object -First 1
& subst.exe "$($letter):" $repo
if ($LASTEXITCODE -ne 0) { throw 'subst failed' }
$driveRoot = "$($letter):\"

# $form: a name, a script block that starts one run.
$comspec = $env:ComSpec
$forms = [ordered]@{
  'codex cmd' = @{ Kind = 'systemMessage'; Runtime = 'codex'; Run = { param($pv, $code, $cwd) Invoke-Hook $comspec ('/C "' + $codex + '"') $null $pv $code $cwd } }
  'copilot powershell.exe 5.1' = @{ Kind = 'message'; Runtime = 'copilot'; Run = { param($pv, $code, $cwd) Invoke-Hook (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') $null @('-NoProfile', '-NonInteractive', '-Command', $copilot) $pv $code $cwd } }
  'copilot pwsh' = @{ Kind = 'message'; Runtime = 'copilot'; Run = { param($pv, $code, $cwd) Invoke-Hook ((Get-Command pwsh -CommandType Application | Select-Object -First 1).Source) $null @('-NoProfile', '-NonInteractive', '-Command', $copilot) $pv $code $cwd } }
}
try {
  foreach ($f in $forms.Keys) {
    $form = $forms[$f]
    foreach ($k in $paths.Keys) {
      Expect-NotChecked "$f : $k" (& $form.Run $paths[$k] 0 $repo) $form.Kind
    }
    foreach ($k in $withAgent.Keys) {
      foreach ($code in 0, 2) { Expect-Ran "$f : $k, exit $code" (& $form.Run $withAgent[$k] $code $repo) $code $form.Runtime }
    }
    Expect-NotChecked "$f : workspace at a drive root ($driveRoot), PATH holds only $($driveRoot)bin and $driveRoot" (& $form.Run "$($driveRoot)bin;$driveRoot;$basePath" 0 $driveRoot) $form.Kind
    Expect-Ran "$f : workspace at a drive root ($driveRoot), stand-in in a folder outside it" (& $form.Run "$($driveRoot)bin;$bin;$basePath" 0 $driveRoot) 0 $form.Runtime
  }
} finally {
  & subst.exe "$($letter):" /d | Out-Null
}

$results | Format-Table -AutoSize -Wrap | Out-String -Width 300 | Write-Output
Write-Output ("{0} checks, {1} failed" -f $results.Count, $failures.Count)
if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Output "FAIL: $_" }
  exit 1
}
