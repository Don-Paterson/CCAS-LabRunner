# CCAS Lab Runner V3 - GitHub bootstrap for A-GUI.
#   irm https://raw.githubusercontent.com/Don-Paterson/CCAS-LabRunner/main/run-labrunner.ps1 | iex
# Downloads the repo to C:\CCAS-LabRunner and starts it. The GitHub copy has no
# payload, so the runner uses the Desktop 'Check Point Tools\Configuration Scripts' folder.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$dest = 'C:\CCAS-LabRunner'
$zip  = Join-Path $env:TEMP 'CCAS-LabRunner-main.zip'
$tmp  = Join-Path $env:TEMP 'CCAS-LabRunner-extract'
Invoke-WebRequest -Uri 'https://github.com/Don-Paterson/CCAS-LabRunner/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $tmp -Force
$srcDir = Get-ChildItem $tmp -Directory | Select-Object -First 1
if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
# Keep any payload files already placed in C:\CCAS-LabRunner\payload
Copy-Item -Path (Join-Path $srcDir.FullName '*') -Destination $dest -Recurse -Force
Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "CCAS Lab Runner installed in $dest" -ForegroundColor Green
& (Join-Path $dest 'Start-LabRunner.cmd')
