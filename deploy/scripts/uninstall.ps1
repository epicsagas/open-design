#Requires -Version 5.1
<#
.SYNOPSIS
    Open Design — Uninstaller for Windows
.DESCRIPTION
    Reads OPEN_DESIGN_INSTALL_MODE from .env and uninstalls accordingly.
    Data is PRESERVED by default. Use -DeleteData to remove it.
.PARAMETER DeleteData
    Delete data (projects, artifacts, config). Data is preserved by default.
.PARAMETER KeepData
    Accepted for backward compatibility. Data is now preserved by default.
.PARAMETER NonInteractive
    Skip confirmation prompts.
#>
[CmdletBinding()]
param(
    [switch]$DeleteData,
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
function Write-Err     { param($msg) Write-Host "[open-design] $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "  -- Open Design Uninstaller --" -ForegroundColor Red
Write-Host ""

if (-not $NonInteractive) {
    if ($DeleteData) {
        Write-Warn "WARNING: -DeleteData specified. All data (projects, artifacts, config) will be deleted."
    } else {
        Write-Warn "This will stop Open Design and remove its service configuration."
        Write-Info "Data will be preserved. Use -DeleteData to also remove data."
    }
    $confirm = Read-Host "Continue? [y/N]"
    if ($confirm -notmatch '^[Yy]') { Write-Info "Cancelled."; exit 0 }
}

# --- Read .env ---
$installMode = ''
$sourceDir = ''

if (Test-Path $EnvFile) {
    $lines = Get-Content $EnvFile
    foreach ($line in $lines) {
        if ($line -match '^OPEN_DESIGN_INSTALL_MODE=(.+)$') { $installMode = $Matches[1] }
        if ($line -match '^OPEN_DESIGN_SOURCE_DIR=(.+)$') { $sourceDir = $Matches[1] }
    }
}

if (-not $installMode) {
    if ((Test-Path $ComposeFile) -and (Get-Command docker -ErrorAction SilentlyContinue)) {
        $installMode = 'docker'
    } else {
        $installMode = 'node'
    }
}

Write-Info "Install mode: $installMode"

# =========================================================================
# DOCKER MODE
# =========================================================================
if ($installMode -eq 'docker') {

    try {
        $running = docker compose -f $ComposeFile ps -q 2>&1
        if ($running) {
            Write-Info "Stopping containers..."
            docker compose -f $ComposeFile down
            Write-Success "Containers stopped."
        } else {
            Write-Info "No running containers found."
        }
    } catch {
        Write-Warn "Could not stop containers: $_"
    }

    if ($DeleteData) {
        Write-Info "Removing Docker volume..."
        docker volume rm open_design_data 2>$null | Out-Null
    }

# =========================================================================
# NODE MODE
# =========================================================================
} elseif ($installMode -eq 'node') {

    if (-not $sourceDir) {
        $sourceDir = Join-Path $env:USERPROFILE '.open-design\source'
    }

    $taskName = 'OpenDesignDaemon'
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Info "Stopping and removing scheduled task..."
        Stop-ScheduledTask -TaskName $taskName 2>$null
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Success "Scheduled task removed."
    } else {
        Write-Info "No scheduled task found."
    }

    if (Test-Path $sourceDir) {
        Write-Info "Removing source: $sourceDir..."
        Remove-Item -Recurse -Force $sourceDir
    }

    if ($DeleteData) {
        $dataDir = Join-Path $env:USERPROFILE '.open-design\data'
        if (Test-Path $dataDir) {
            Write-Info "Removing data: $dataDir..."
            Remove-Item -Recurse -Force $dataDir
        }
    }

    # Clean up .open-design if empty
    $odDir = Join-Path $env:USERPROFILE '.open-design'
    if ((Test-Path $odDir) -and -not (Get-ChildItem $odDir -ErrorAction SilentlyContinue)) {
        Remove-Item -Force $odDir
    }

} else {
    Write-Err "Unknown install mode: $installMode"
    exit 1
}

# --- Remove .env (common) ---
if (Test-Path $EnvFile) {
    Write-Info "Removing $EnvFile..."
    Remove-Item $EnvFile -Force
}

Write-Host ""
Write-Success "Open Design has been uninstalled."
if (-not $DeleteData) {
    Write-Info "Data was preserved."
    if ($installMode -eq 'docker') {
        Write-Info "Remove Docker volume manually: docker volume rm open_design_data"
    } else {
        $dataPath = Join-Path $env:USERPROFILE '.open-design\data'
        Write-Info "Remove data manually: Remove-Item -Recurse '$dataPath'"
    }
}
Write-Host ""
