#Requires -Version 5.1
<#
.SYNOPSIS
    Open Design — Uninstaller for Windows
.PARAMETER KeepData
    Preserve the open_design_data Docker volume.
.PARAMETER NonInteractive
    Skip confirmation prompts.
#>
[CmdletBinding()]
param(
    [switch]$KeepData,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$DeployDir   = Split-Path -Parent $ScriptDir
$EnvFile     = Join-Path $DeployDir '.env'
$ComposeFile = Join-Path $DeployDir 'docker-compose.yml'

function Write-Info    { param($msg) Write-Host "[open-design] $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[open-design] $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[open-design] $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  -- Open Design Uninstaller --" -ForegroundColor Red
Write-Host ""

if (-not $NonInteractive) {
    if ($KeepData) {
        Write-Warn "This will stop Open Design. Data volume will be preserved."
    } else {
        Write-Warn "This will stop Open Design and DELETE all data (projects, artifacts, config)."
    }
    $confirm = Read-Host "Continue? [y/N]"
    if ($confirm -notmatch '^[Yy]') { Write-Info "Cancelled."; exit 0 }
}

# Stop and remove containers
try {
    $running = docker compose -f $ComposeFile ps -q 2>&1
    if ($running) {
        Write-Info "Stopping containers..."
        if ($KeepData) {
            docker compose -f $ComposeFile down
        } else {
            docker compose -f $ComposeFile down -v
        }
        Write-Success "Containers stopped."
    } else {
        Write-Info "No running containers found."
    }
} catch {
    Write-Warn "Could not stop containers: $_"
}

# Remove .env
if (Test-Path $EnvFile) {
    Write-Info "Removing $EnvFile..."
    Remove-Item $EnvFile -Force
}

Write-Host ""
Write-Success "Open Design has been uninstalled."
if ($KeepData) {
    Write-Info "Data volume 'open_design_data' was preserved."
    Write-Info "Remove it manually: docker volume rm open_design_data"
}
Write-Host ""
