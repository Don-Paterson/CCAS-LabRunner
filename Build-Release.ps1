<#
.SYNOPSIS
    Builds the standalone CCAS Lab Runner zip.

.DESCRIPTION
    Copies the runner (engine, config, labs, payload, launcher, README) into
    ..\dist\CCAS-LabRunner, normalises payload files to LF, and writes
    ..\dist\CCAS-LabRunner-V3-<version>.zip plus a .sha256 file.

    Refuses to build if payload\ is missing the courseware scripts, because
    the zip is meant to run without the A-GUI Desktop folder.

    Works in Windows PowerShell 5.1 and PowerShell 7.
#>
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist')
)
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$version = (Get-Content (Join-Path $src 'VERSION') | Select-Object -First 1).Trim()

$required = @('A-SMS_ftw.sh', 'A-SMS_config.sh', 'bash_api_verified-Groups.sh', 'bash_api_verified-Policy.sh')
$missing = $required | Where-Object { -not (Test-Path (Join-Path $src "payload\$_")) }
if ($missing) { throw "payload\ is missing: $($missing -join ', '). Copy the Configuration Scripts into payload\ first." }

$stage = Join-Path $OutDir 'CCAS-LabRunner'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$include = @('Start-LabRunner.cmd', 'LabRunner.ps1', 'config.psd1', 'VERSION', 'README.md', 'labs', 'payload')
foreach ($item in $include) {
    Copy-Item -Path (Join-Path $src $item) -Destination $stage -Recurse -Force
}

# Payload files go to Gaia - LF line endings
$utf8 = New-Object System.Text.UTF8Encoding($false)
Get-ChildItem (Join-Path $stage 'payload') -File | Where-Object { $_.Extension -in '.sh', '.xml' } | ForEach-Object {
    $text = [System.IO.File]::ReadAllText($_.FullName) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($_.FullName, $text, $utf8)
}
# The launcher must keep CRLF for cmd.exe
$cmdFile = Join-Path $stage 'Start-LabRunner.cmd'
$cmdText = ([System.IO.File]::ReadAllText($cmdFile) -replace "`r`n", "`n") -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($cmdFile, $cmdText, (New-Object System.Text.ASCIIEncoding))

$zip = Join-Path $OutDir "CCAS-LabRunner-V3-$version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $stage -DestinationPath $zip
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash
Set-Content -Path "$zip.sha256" -Value "$hash  $(Split-Path $zip -Leaf)" -Encoding ASCII

Write-Host "Built $zip" -ForegroundColor Green
Write-Host "SHA256 $hash" -ForegroundColor DarkGray
