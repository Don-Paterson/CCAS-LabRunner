<#
.SYNOPSIS
    CCAS Lab Runner V3 - menu-driven automation of the CCAS labs from A-GUI.

.DESCRIPTION
    Runs each lab's CLI steps against the lab hosts (A-SMS, A-GW, B-GW, C-GW)
    over SSH with plink/pscp. Lab steps live in labs\*.psd1, settings in
    config.psd1, and the files pushed to the hosts in payload\ (zip build) or
    the A-GUI Desktop 'Check Point Tools\Configuration Scripts' folder.

    Works in Windows PowerShell 5.1 and PowerShell 7.

    Every step is checked: PASS, WARN (e.g. object already exists) or FAIL.
    A lab is only marked [done] when no step failed.

.PARAMETER Lab
    Run a single lab (e.g. 3A) without the menu.

.PARAMETER Auto
    Do not ask before each step. In Auto mode a failed step stops the lab.

.EXAMPLE
    Start-LabRunner.cmd
    Start-LabRunner.cmd -Lab 3A -Auto

.NOTES
    Author: Don Paterson (built with Claude)
    Lab source: DOC-Lab Commands-CCAS-R81.20-V1.0
#>
[CmdletBinding()]
param(
    [string]$Lab,
    [switch]$Auto
)

$ErrorActionPreference = 'Continue'
$Script:Root = $PSScriptRoot

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
$Script:Version = '0.0.0'
$verFile = Join-Path $Script:Root 'VERSION'
if (Test-Path $verFile) { $Script:Version = (Get-Content $verFile | Select-Object -First 1).Trim() }

$Script:Cfg = Import-PowerShellDataFile (Join-Path $Script:Root 'config.psd1')
$Script:Pass  = $Script:Cfg.Password
$Script:User  = $Script:Cfg.User
$Script:Hosts = $Script:Cfg.Hosts
$Script:Tokens = @{}
foreach ($k in $Script:Cfg.Tokens.Keys) { $Script:Tokens[$k] = [string]$Script:Cfg.Tokens[$k] }
$Script:Tokens['PASS'] = $Script:Pass

$Script:PayloadDir  = Join-Path $Script:Root 'payload'
$Script:FallbackDir = [Environment]::ExpandEnvironmentVariables($Script:Cfg.FallbackScriptsDir)

$Script:Paced = -not $Auto
$Script:Quit  = $false
$Script:KeysChecked = @{}        # IP -> $true once SSH has been confirmed this run
$Script:RebootSeen  = @{}        # IP -> $true when a step saw the host drop SSH to reboot
$Script:ApiKeyStatus = 'not checked'

$Script:StateDir  = Join-Path $env:USERPROFILE '.ccas-labrunner-v3'
$Script:StateFile = Join-Path $Script:StateDir 'state.json'
$Script:LogDir    = Join-Path $Script:StateDir 'logs'
foreach ($d in @($Script:StateDir, $Script:LogDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
$Script:LogFile = Join-Path $Script:LogDir ('run-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
function Get-Val { param($Value, $Default) if ($null -eq $Value) { $Default } else { $Value } }

function Protect-Text {
    # Hide API keys in anything shown or logged.
    param([string]$Text)
    if (-not $Text) { return $Text }
    $t = $Text -replace '(APIKEY=\S{6})\S*', '$1****'
    $t = $t -replace '("api-key"\s*:\s*"[^"]{6})[^"]*', '$1****'
    return $t
}

function Write-Log {
    param([string]$Text, [ConsoleColor]$Color = 'Gray')
    $safe = Protect-Text $Text
    Write-Host $safe -ForegroundColor $Color
    Add-Content -Path $Script:LogFile -Value ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $safe)
}

function Expand-Tokens {
    param([string]$Text)
    foreach ($k in $Script:Tokens.Keys) { $Text = $Text.Replace('{{' + $k + '}}', $Script:Tokens[$k]) }
    return $Text
}

function Get-State {
    $state = @{ completed = @(); apikey = $null }
    if (Test-Path $Script:StateFile) {
        try {
            $obj = Get-Content $Script:StateFile -Raw | ConvertFrom-Json
            if ($obj.completed) { $state.completed = @($obj.completed) }
            if ($obj.apikey)    { $state.apikey = [string]$obj.apikey }
        } catch { }
    }
    return $state
}

function Save-State {
    param($State)
    $State | ConvertTo-Json -Depth 5 | Set-Content -Path $Script:StateFile -Encoding UTF8
}

function Get-Labs {
    $labs = [ordered]@{}
    foreach ($id in $Script:Cfg.LabOrder) {
        $f = Join-Path $Script:Root "labs\$id.psd1"
        if (Test-Path $f) { $labs[$id] = Import-PowerShellDataFile $f }
        else { Write-Log "Lab file missing: $f" Red }
    }
    return $labs
}

# ---------------------------------------------------------------------------
# plink / pscp
# ---------------------------------------------------------------------------
function Find-Plink {
    $cmd = Get-Command plink.exe -ErrorAction SilentlyContinue
    $candidates = @()
    if ($cmd) { $candidates += $cmd.Source }
    $candidates += (Join-Path $env:ProgramFiles 'PuTTY\plink.exe')
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} 'PuTTY\plink.exe') }
    $found = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $found) { throw 'plink.exe not found in PATH or the standard PuTTY folders. Install PuTTY first.' }
    $Script:Plink = $found
    $Script:Pscp  = Join-Path (Split-Path $found) 'pscp.exe'
    if (-not (Test-Path $Script:Pscp)) {
        $alt = Get-Command pscp.exe -ErrorAction SilentlyContinue
        if ($alt) { $Script:Pscp = $alt.Source } else { throw 'pscp.exe not found beside plink.exe or in PATH.' }
    }
}

function Invoke-Plink {
    # Runs plink and returns @{ Output = string; ExitCode = int }.
    param([string[]]$PlinkArgs, [string]$StdIn)
    if ($PSBoundParameters.ContainsKey('StdIn')) {
        $out = $StdIn | & $Script:Plink @PlinkArgs 2>&1 | ForEach-Object { "$_" }
    } else {
        $out = & $Script:Plink @PlinkArgs 2>&1 | ForEach-Object { "$_" }
    }
    return @{ Output = ($out -join "`n"); ExitCode = $LASTEXITCODE }
}

$Script:SshErrorPattern = 'FATAL ERROR|Network error|Connection refused|Connection timed out|Access denied|host key|POTENTIAL SECURITY BREACH|Cannot confirm a host key'

function Remove-CachedHostKey {
    param([string]$Ip)
    $reg = 'HKCU:\Software\SimonTatham\PuTTY\SshHostKeys'
    if (-not (Test-Path $reg)) { return }
    $props = (Get-Item $reg).Property | Where-Object { $_ -like "*:$Ip" }
    foreach ($p in $props) {
        Remove-ItemProperty -Path $reg -Name $p -ErrorAction SilentlyContinue
        Write-Log "  Removed old cached SSH host key $p" DarkGray
    }
}

function Test-SshHost {
    # Makes sure plink can log in to the host non-interactively.
    # A host key that changed (FTW, Blink, pod reset) is replaced automatically.
    param([string]$Ip, [switch]$Quiet)
    if ($Script:KeysChecked.ContainsKey($Ip)) { return $true }
    $target = "$($Script:User)@$Ip"
    $probe = Invoke-Plink -PlinkArgs @('-ssh', '-batch', '-pw', $Script:Pass, $target, 'exit')
    if ($probe.Output -notmatch $Script:SshErrorPattern) { $Script:KeysChecked[$Ip] = $true; return $true }

    if ($probe.Output -match 'host key|POTENTIAL SECURITY BREACH|Cannot confirm') {
        if (-not $Quiet) { Write-Log "  SSH host key for $Ip is new or has changed - accepting the current key." DarkGray }
        Remove-CachedHostKey -Ip $Ip
        Invoke-Plink -PlinkArgs @('-ssh', '-pw', $Script:Pass, $target, 'exit') -StdIn 'y' | Out-Null
        $probe = Invoke-Plink -PlinkArgs @('-ssh', '-batch', '-pw', $Script:Pass, $target, 'exit')
        if ($probe.Output -notmatch $Script:SshErrorPattern) { $Script:KeysChecked[$Ip] = $true; return $true }
    }
    if (-not $Quiet) {
        Write-Log "  Cannot log in to $Ip over SSH:" Red
        $probe.Output -split "`n" | Select-Object -First 5 | ForEach-Object { Write-Log "    $_" Red }
    }
    return $false
}

function Invoke-Ssh {
    # Sends a multi-line command script to a host with plink -m.
    # Returns @{ Output; ExitCode; Connected }.
    param([string]$HostName, [string]$Commands, [int]$TimeoutNote = 0, [switch]$Silent)
    $ip = $Script:Hosts[$HostName]
    if (-not (Test-SshHost -Ip $ip)) { return @{ Output = 'SSH connection failed'; ExitCode = 255; Connected = $false } }
    $tmp = [System.IO.Path]::GetTempFileName()
    # LF line endings - Gaia shells dislike CRLF
    [System.IO.File]::WriteAllText($tmp, ($Commands -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    if ($TimeoutNote -gt 0 -and -not $Silent) { Write-Log "  (This step can take about $TimeoutNote minutes)" Yellow }
    if (-not $Silent) { Write-Log "  >>> $HostName ($ip)" Cyan }
    $r = Invoke-Plink -PlinkArgs @('-ssh', '-batch', '-pw', $Script:Pass, "$($Script:User)@$ip", '-m', $tmp)
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    if (-not $Silent) { $r.Output -split "`n" | ForEach-Object { Write-Log "    $_" } }
    return @{ Output = $r.Output; ExitCode = $r.ExitCode; Connected = $true }
}

function Resolve-PayloadFile {
    param([string]$Name)
    foreach ($dir in @($Script:PayloadDir, $Script:FallbackDir)) {
        $p = Join-Path $dir $Name
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Copy-ToHost {
    param([string]$LocalFile, [string]$HostName, [string]$RemotePath)
    $ip = $Script:Hosts[$HostName]
    if (-not (Test-SshHost -Ip $ip)) { return $false }
    Write-Log "  pscp: '$LocalFile' -> ${HostName}:$RemotePath" Cyan
    $out = & $Script:Pscp -pw $Script:Pass -batch $LocalFile "$($Script:User)@${ip}:$RemotePath" 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $out | ForEach-Object { Write-Log "    $_" }
    return ($code -eq 0)
}

function Test-Ping {
    param([string]$Ip)
    try {
        $p = New-Object System.Net.NetworkInformation.Ping
        return ($p.Send($Ip, 2000).Status -eq 'Success')
    } catch { return $false }
}

function Test-Port {
    # TCP connect test - works even when a gateway policy drops ping.
    param([string]$Ip, [int]$Port = 22, [int]$TimeoutMs = 2000)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($Ip, $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs) -and $client.Connected) { return $true }
        return $false
    } catch { return $false } finally { $client.Close() }
}

function Wait-HostReboot {
    # Waits for the host to go down (SSH port closed), then until SSH logins
    # work again. If a step already saw the host drop the connection for a
    # reboot, the 'go down' wait is skipped.
    param([string]$HostName, [int]$InitialSleep = 60, [int]$TimeoutMin = 30)
    $ip = $Script:Hosts[$HostName]
    Write-Log "  Waiting for $HostName ($ip) to reboot (timeout ${TimeoutMin} min)..." Yellow
    $deadline = (Get-Date).AddMinutes($TimeoutMin)
    if ($Script:RebootSeen.ContainsKey($ip)) {
        $Script:RebootSeen.Remove($ip)
    } else {
        $wentDown = $false
        while ((Get-Date) -lt $deadline) {
            if (-not (Test-Port -Ip $ip)) { $wentDown = $true; break }
            Start-Sleep -Seconds 10
        }
        if (-not $wentDown) { Write-Log "  $HostName did not go down within ${TimeoutMin} minutes." Red; return $false }
        Write-Log "  $HostName is down; waiting for it to come back..." Yellow
    }
    Start-Sleep -Seconds $InitialSleep
    $Script:KeysChecked.Remove($ip)
    while ((Get-Date) -lt $deadline) {
        if ((Test-Port -Ip $ip) -and (Test-SshHost -Ip $ip -Quiet)) {
            Write-Log "  $HostName answers SSH again; allowing 60 s for services to settle." Yellow
            Start-Sleep -Seconds 60
            return $true
        }
        Start-Sleep -Seconds 15
    }
    Write-Log "  $HostName did not come back within ${TimeoutMin} minutes." Red
    return $false
}

function Get-LoginShell {
    # 'clish' or 'bash' for the admin login shell on a host ($null if unreachable).
    param([string]$HostName)
    $r = Invoke-Ssh -HostName $HostName -Commands 'show hostname' -Silent
    if (-not $r.Connected) { return $null }
    if ($r.Output -match 'command not found') { return 'bash' }
    return 'clish'
}

function Invoke-ClishLines {
    # Runs clish commands one per SSH call. A clish login shell may only run
    # the first line of a multi-line command, and the shell can change part
    # way through (set user admin shell /bin/bash), so the login shell is
    # checked before every line; under bash the line is wrapped in clish -c.
    param([string]$HostName, [string]$Commands)
    $all = @()
    foreach ($line in ($Commands -split "`r?`n")) {
        $cmd = $line.Trim()
        if (-not $cmd -or $cmd.StartsWith('#')) { continue }
        $shell = Get-LoginShell -HostName $HostName
        if (-not $shell) { return @{ Output = (($all + 'SSH connection failed') -join "`n"); ExitCode = 255; Connected = $false } }
        if ($shell -eq 'bash') { $send = 'clish -c "' + $cmd.Replace('"', '\"') + '"' } else { $send = $cmd }
        Write-Log "  clish ($shell login shell): $cmd" DarkGray
        $r = Invoke-Ssh -HostName $HostName -Commands $send
        $all += $r.Output
    }
    return @{ Output = ($all -join "`n"); ExitCode = 0; Connected = $true }
}

# ---------------------------------------------------------------------------
# Result checking
# ---------------------------------------------------------------------------
# CLINFR = a clish line that failed; 1A-2 runs load configuration with
# 'on-failure continue' on purpose, so these are warnings, not failures.
$Script:WarnPattern = 'not_unique|already exists|More than one object|CLINFR\d+'
$Script:FailPattern = 'LOGIN FAILED|"code"\s*:\s*"(err_|generic_err)|FATAL ERROR|Network error|Access denied|unmatched double quote|^\s*Failed:|command not found'
$Script:DisconnectPattern = 'unexpectedly closed|Connection reset|connection abort|Remote side closed|Network error'

function Get-StepResult {
    # PASS / WARN / FAIL from command output. Lines that only say an object
    # already exists (typical on a re-run) count as WARN, not FAIL.
    param([string]$Output, [int]$ExitCode = 0)
    $fail = 0; $warn = 0
    foreach ($line in ($Output -split "`n")) {
        if ($line -match $Script:WarnPattern) { $warn++ }
        elseif ($line -match $Script:FailPattern) { $fail++ }
    }
    if ($fail -gt 0) { return 'FAIL' }
    if ($warn -gt 0) { return 'WARN' }
    return 'PASS'
}

# ---------------------------------------------------------------------------
# API key
# ---------------------------------------------------------------------------
function New-MgmtSessionPrefix {
    param([string]$Extra = '')
    $key = (Get-State).apikey
    if (-not $key) { return 'echo "LOGIN FAILED - no cached API key, run Lab 2A first"; exit 1' }
    return @"
SID=`$(mgmt_cli login api-key "$key" session-timeout 3600 $Extra --format json | jq -r '.sid')
if [ -z "`$SID" ] || [ "`$SID" = "null" ]; then echo "LOGIN FAILED"; exit 1; fi
echo "Session: `$SID"
"@
}

function Test-ApiKey {
    $key = (Get-State).apikey
    if (-not $key) { $Script:ApiKeyStatus = 'none - run Lab 2A'; return }
    $ip = $Script:Hosts['A-SMS']
    if (-not (Test-Ping $ip)) { $Script:ApiKeyStatus = 'cached (A-SMS not reachable)'; return }
    $cmds = @"
SID=`$(mgmt_cli login api-key "$key" --format json 2>/dev/null | jq -r '.sid' 2>/dev/null)
if [ -n "`$SID" ] && [ "`$SID" != "null" ]; then echo KEY_OK; mgmt_cli --session-id "`$SID" logout >/dev/null 2>&1; else echo KEY_BAD; fi
"@
    $r = Invoke-Ssh -HostName 'A-SMS' -Commands $cmds -Silent
    if ($r.Output -match 'KEY_OK') { $Script:ApiKeyStatus = 'valid' }
    elseif ($r.Output -match 'KEY_BAD') { $Script:ApiKeyStatus = 'INVALID - re-run Lab 2A' }
    else { $Script:ApiKeyStatus = 'cached (could not test - is the A-SMS admin shell bash yet?)' }
}

# ---------------------------------------------------------------------------
# Lab engine
# ---------------------------------------------------------------------------
function Confirm-Step {
    param([string]$Desc)
    if (-not $Script:Paced) { return 'run' }
    Write-Host ''
    Write-Host "NEXT STEP: $Desc" -ForegroundColor White
    $ans = Read-Host '  [Enter]=run  s=skip  a=abort lab'
    switch ($ans.ToLower()) { 's' { 'skip' } 'a' { 'abort' } default { 'run' } }
}

function Confirm-AfterFailure {
    if (-not $Script:Paced) { return 'abort' }
    $ans = Read-Host '  Step FAILED.  r=retry  c=continue anyway  [Enter/a]=abort lab'
    switch ($ans.ToLower()) { 'r' { 'retry' } 'c' { 'continue' } default { 'abort' } }
}

function Invoke-Step {
    # Runs one step and returns PASS / WARN / FAIL / SKIP.
    param($Step)
    switch ($Step.Type) {
        'manual' {
            Write-Log '  MANUAL TASK:' Magenta
            (Expand-Tokens $Step.Text) -split "`n" | ForEach-Object { Write-Log "    $_" Magenta }
            if ($Script:Paced) { Read-Host '  Press Enter when done' | Out-Null }
            return 'PASS'
        }
        'waitreboot' {
            $ok = Wait-HostReboot -HostName $Step.Host -InitialSleep (Get-Val $Step.InitialSleep 60) -TimeoutMin (Get-Val $Step.TimeoutMin 30)
            if ($ok) { return 'PASS' } else { return 'FAIL' }
        }
        'copy' {
            $local = Resolve-PayloadFile $Step.Local
            if (-not $local) {
                if ($Step.Optional) { Write-Log "  $($Step.Local) not found in payload or fallback folder - skipped (optional)." DarkYellow; return 'SKIP' }
                Write-Log "  $($Step.Local) not found in '$($Script:PayloadDir)' or '$($Script:FallbackDir)'." Red
                return 'FAIL'
            }
            if (Copy-ToHost -LocalFile $local -HostName $Step.Host -RemotePath $Step.Remote) { return 'PASS' } else { return 'FAIL' }
        }
        default {   # bash / clish
            $cmds = Expand-Tokens $Step.Commands
            if ($Step.UseApiSession) {
                $prefix = New-MgmtSessionPrefix -Extra (Get-Val $Step.SessionExtra '')
                $cmds = $cmds.Replace('__SESSION__', $prefix)
            }
            if ($Step.Type -eq 'clish') {
                $r = Invoke-ClishLines -HostName $Step.Host -Commands $cmds
            } else {
                $r = Invoke-Ssh -HostName $Step.Host -Commands $cmds -TimeoutNote (Get-Val $Step.TimeoutNote 0)
            }
            if (-not $r.Connected) { return 'FAIL' }
            if ($Step.ExpectDisconnect -and $r.Output -match $Script:DisconnectPattern) {
                # The host closed the session because it is rebooting - expected here.
                Write-Log "  $($Step.Host) closed the connection - expected, it is rebooting." Yellow
                $r.Output = (($r.Output -split "`n") | Where-Object { $_ -notmatch $Script:DisconnectPattern }) -join "`n"
                $Script:RebootSeen[$Script:Hosts[$Step.Host]] = $true
                if ($Step.WaitIfDisconnected) {
                    if (-not (Wait-HostReboot -HostName $Step.Host -InitialSleep 90 -TimeoutMin 30)) { return 'FAIL' }
                }
            }
            if ($Step.Capture) {
                if ($r.Output -match $Step.Capture.Pattern) {
                    $state = Get-State
                    $state[$Step.Capture.StateKey] = $Matches[1]
                    Save-State $state
                    Write-Log "  Captured $($Step.Capture.StateKey) and saved it to state.json." Green
                    if ($Step.Capture.StateKey -eq 'apikey') { $Script:ApiKeyStatus = 'valid (new)' }
                } else {
                    Write-Log "  Expected value ($($Step.Capture.StateKey)) was not found in the output." Red
                    return 'FAIL'
                }
            }
            return (Get-StepResult -Output $r.Output -ExitCode $r.ExitCode)
        }
    }
}

function Invoke-Lab {
    param([string]$LabId, $LabDef)
    Write-Host ''
    Write-Log ('=' * 70) White
    Write-Log $LabDef.Title White
    Write-Log ('=' * 70) White

    $results = @()
    $aborted = $false
    $steps = @($LabDef.Steps)
    for ($i = 0; $i -lt $steps.Count; $i++) {
        $step = $steps[$i]
        $label = '[{0}/{1}] {2}' -f ($i + 1), $steps.Count, $step.Desc
        $choice = Confirm-Step -Desc $label
        if ($choice -eq 'abort') { Write-Log "  LAB ABORTED at step $($i + 1)." Red; $aborted = $true; break }
        if ($choice -eq 'skip')  { Write-Log "  SKIPPED: $($step.Desc)" DarkYellow; $results += [pscustomobject]@{ Step = $i + 1; Result = 'SKIP'; Desc = $step.Desc }; continue }
        if (-not $Script:Paced)  { Write-Log "STEP $label" White }

        do {
            $res = Invoke-Step -Step $step
            $again = $false
            $color = switch ($res) { 'PASS' { 'Green' } 'WARN' { 'Yellow' } 'SKIP' { 'DarkYellow' } default { 'Red' } }
            Write-Log "  Result: $res" $color
            if ($res -eq 'FAIL') {
                $next = Confirm-AfterFailure
                if ($next -eq 'retry') { $again = $true }
                elseif ($next -eq 'abort') { $aborted = $true }
            }
        } while ($again)

        $results += [pscustomobject]@{ Step = $i + 1; Result = $res; Desc = $step.Desc }
        if ($aborted) { Write-Log "  LAB STOPPED at step $($i + 1)." Red; break }
    }

    Write-Log ''
    Write-Log "Summary - $($LabDef.Title)" White
    foreach ($r in $results) {
        $color = switch ($r.Result) { 'PASS' { 'Green' } 'WARN' { 'Yellow' } 'SKIP' { 'DarkYellow' } default { 'Red' } }
        Write-Log ('  {0,2}. {1,-4}  {2}' -f $r.Step, $r.Result, $r.Desc) $color
    }
    $failed = @($results | Where-Object { $_.Result -eq 'FAIL' }).Count
    $state = Get-State
    if (-not $aborted -and $failed -eq 0) {
        if ($state.completed -notcontains $LabId) { $state.completed = @($state.completed) + $LabId; Save-State $state }
        Write-Log "LAB $LabId COMPLETE." Green
        return $true
    }
    Write-Log "LAB $LabId NOT COMPLETE ($failed failed step(s)$(if ($aborted) { ', stopped early' }))." Red
    return $false
}

# ---------------------------------------------------------------------------
# Menu actions
# ---------------------------------------------------------------------------
function Invoke-Preflight {
    Write-Host ''
    Write-Log 'PREFLIGHT CHECK' White
    Write-Log "  plink: $($Script:Plink)" Gray
    Write-Log "  pscp:  $($Script:Pscp)" Gray
    foreach ($name in $Script:Hosts.Keys | Sort-Object) {
        $ip = $Script:Hosts[$name]
        $ping = Test-Ping $ip
        $ssh = $false
        if ($ping) { $ssh = Test-SshHost -Ip $ip -Quiet }
        $color = if ($ssh) { 'Green' } elseif ($ping) { 'Yellow' } else { 'DarkGray' }
        Write-Log ('  {0,-6} {1,-14} ping {2,-4} ssh {3}' -f $name, $ip, $(if ($ping) { 'ok' } else { 'no' }), $(if ($ssh) { 'ok' } else { 'no' })) $color
    }
    Write-Log '  (B-GW and C-GW are normally unreachable until Lab 5A; hosts may be powered off early in the course.)' DarkGray
    $files = @('A-SMS_ftw.sh', 'A-SMS_config.sh', 'bash_api_verified-Groups.sh', 'bash_api_verified-Policy.sh', 'answers.xml')
    foreach ($f in $files) {
        $p = Resolve-PayloadFile $f
        if ($p) { Write-Log "  file   $f  ->  $p" Green }
        elseif ($f -eq 'answers.xml') { Write-Log "  file   $f  not found (optional - the ATC image normally has it on A-GW)" DarkGray }
        else { Write-Log "  file   $f  NOT FOUND" Red }
    }
    Test-ApiKey
    Write-Log "  API key: $($Script:ApiKeyStatus)" Gray
    if ($Script:Paced) { Read-Host '  Press Enter to return to the menu' | Out-Null }
}

function Show-ApiKey {
    $key = (Get-State).apikey
    if ($key) {
        Write-Host ''
        Write-Host "  api_admin API key: $key" -ForegroundColor Green
        Write-Host '  (Not written to the log. Use it in Postman / SmartConsole tests.)' -ForegroundColor DarkGray
    } else { Write-Host '  No API key cached - run Lab 2A.' -ForegroundColor Yellow }
    Read-Host '  Press Enter to return to the menu' | Out-Null
}

function Reset-HostKeys {
    foreach ($ip in $Script:Hosts.Values) { Remove-CachedHostKey -Ip $ip }
    $Script:KeysChecked = @{}
    Write-Log '  Cached SSH host keys for the lab hosts removed; they are re-accepted on next use.' Yellow
    Read-Host '  Press Enter to return to the menu' | Out-Null
}

function Show-Menu {
    param($Labs)
    $state = Get-State
    Clear-Host
    Write-Host ''
    Write-Host "  CCAS Lab Runner v$($Script:Version)" -ForegroundColor White
    $mode = if ($Script:Paced) { 'PACED (confirm each step)' } else { 'AUTO (stops on a failed step)' }
    Write-Host "  Mode: $mode    API key: $($Script:ApiKeyStatus)" -ForegroundColor DarkGray
    Write-Host "  Log:  $($Script:LogFile)" -ForegroundColor DarkGray
    Write-Host ''
    $ids = @($Labs.Keys)
    for ($n = 0; $n -lt $ids.Count; $n++) {
        $done = if ($state.completed -contains $ids[$n]) { '[done]' } else { '      ' }
        Write-Host ('   {0}. {1} {2}' -f ($n + 1), $done, $Labs[$ids[$n]].Title)
    }
    Write-Host ''
    Write-Host '   p. Preflight check (hosts, files, API key)'
    Write-Host '   k. Show the cached API key'
    Write-Host '   h. Reset cached SSH host keys'
    Write-Host '   m. Toggle Paced/Auto mode'
    Write-Host '   r. Reset completion state'
    Write-Host '   q. Quit'
    Write-Host ''

    $sel = Read-Host '  Select'
    if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $ids.Count) {
        $idx = [int]$sel - 1
        $id = $ids[$idx]
        $missing = @()
        if ($idx -gt 0) { $missing = @($ids[0..($idx - 1)] | Where-Object { $state.completed -notcontains $_ }) }
        if ($missing.Count -gt 0) {
            Write-Host ('  Note: earlier lab(s) not marked complete: {0}' -f ($missing -join ', ')) -ForegroundColor Yellow
            $go = Read-Host '  Run anyway? (y/N)'
            if ($go.ToLower() -ne 'y') { return }
        }
        Invoke-Lab -LabId $id -LabDef $Labs[$id] | Out-Null
        Read-Host '  Press Enter to return to the menu' | Out-Null
        return
    }
    switch ($sel.ToLower()) {
        'p' { Invoke-Preflight }
        'k' { Show-ApiKey }
        'h' { Reset-HostKeys }
        'm' { $Script:Paced = -not $Script:Paced }
        'r' { $s = Get-State; $s.completed = @(); Save-State $s }
        'q' { $Script:Quit = $true }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
try { Find-Plink } catch { Write-Host $_ -ForegroundColor Red; return }
$labs = Get-Labs
Write-Log "CCAS Lab Runner v$($Script:Version) started (PowerShell $($PSVersionTable.PSVersion))." DarkGray
Write-Log "Payload: $($Script:PayloadDir)   Fallback: $($Script:FallbackDir)" DarkGray

if ($Lab) {
    $id = $Lab.ToUpper()
    if (-not $labs.Contains($id)) { Write-Log "Unknown lab '$Lab'. Labs: $(@($labs.Keys) -join ', ')" Red; return }
    $ok = Invoke-Lab -LabId $id -LabDef $labs[$id]
    if (-not $ok) { $global:LASTEXITCODE = 1 }
    return
}

Write-Host '  Checking the cached API key...' -ForegroundColor DarkGray
Test-ApiKey
while (-not $Script:Quit) { Show-Menu -Labs $labs }
