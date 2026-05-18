#Requires -Version 5.1
<#
.SYNOPSIS
    Open Design — Updater for Windows
.DESCRIPTION
    Reads OPEN_DESIGN_INSTALL_MODE from .env and updates accordingly.
    Docker mode: pulls latest image and restarts.
    Node mode: pulls latest source, rebuilds, and restarts.
.PARAMETER Image
    Pull a specific image reference instead of the one in .env (Docker mode only).
.PARAMETER NonInteractive
    Skip confirmation prompts.
#>
[CmdletBinding()]
param(
    [string]$Image = '',
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$DeployDir   = Split-Path -Parent $ScriptDir
$EnvFile     = Join-Path $DeployDir '.env'
$ComposeFile = Join-Path $DeployDir 'docker-compose.yml'
$HealthTimeout = 60

function Write-Info    { param($msg) Write-Host "[open-design] $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[open-design] $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[open-design] $msg" -ForegroundColor Yellow }
function Write-Err     { param($msg) Write-Host "[open-design] $msg" -ForegroundColor Red }

function Test-HttpHealth {
    param([string]$Url)
    try {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
        return $resp.StatusCode -eq 200
    } catch { return $false }
}

Write-Host ""
Write-Info "Updating Open Design..."

# --- Read .env ---
$installMode = ''
$Port = 7456
$sourceDir = ''

if (Test-Path $EnvFile) {
    $lines = Get-Content $EnvFile
    foreach ($line in $lines) {
        if ($line -match '^OPEN_DESIGN_INSTALL_MODE=(.+)$') { $installMode = $Matches[1] }
        if ($line -match '^OPEN_DESIGN_PORT=(\d+)$') { $Port = [int]$Matches[1] }
        if ($line -match '^OPEN_DESIGN_SOURCE_DIR=(.+)$') { $sourceDir = $Matches[1] }
    }
}

if (-not $installMode) {
    if ((Test-Path $ComposeFile) -and (Get-Command docker -ErrorAction SilentlyContinue)) {
        $installMode = 'docker'
    } else {
        $installMode = 'node'
    }
    Write-Info "No install mode in .env. Detected: $installMode"
}

Write-Info "Install mode: $installMode"

$healthUrl = "http://127.0.0.1:$Port/api/health"

# =========================================================================
# DOCKER MODE
# =========================================================================
if ($installMode -eq 'docker') {

    if ($Image) { $env:OPEN_DESIGN_IMAGE = $Image }

    Write-Info "Pulling latest image..."
    docker compose -f $ComposeFile pull
    if ($LASTEXITCODE -ne 0) { Write-Warn "Image pull failed."; exit 1 }

    Write-Info "Restarting service..."
    docker compose -f $ComposeFile up -d --no-build
    if ($LASTEXITCODE -ne 0) { Write-Warn "Restart failed."; exit 1 }

    # Health check
    Write-Info "Waiting for health check (up to ${HealthTimeout}s)..."
    $healthOk = $false
    $elapsed  = 0
    while ($elapsed -lt $HealthTimeout) {
        if (Test-HttpHealth $healthUrl) { $healthOk = $true; break }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }

    if ($healthOk) {
        Write-Success "Update complete. Daemon is healthy."
    } else {
        Write-Warn "Health check did not pass. Check logs: docker compose -f $ComposeFile logs"
    }

    # Prune dangling images
    Write-Info "Cleaning up old images..."
    docker image prune -f | Out-Null

# =========================================================================
# NODE MODE
# =========================================================================
} elseif ($installMode -eq 'node') {

    if (-not $sourceDir) {
        $sourceDir = Join-Path $env:USERPROFILE '.open-design\source'
    }

    if (-not (Test-Path (Join-Path $sourceDir '.git'))) {
        Write-Err "Source directory not found: $sourceDir"
        Write-Err "Re-run install.ps1 to set up Node.js mode."
        exit 1
    }

    Write-Info "Pulling latest source..."
    Push-Location $sourceDir
    try { git pull --ff-only 2>$null }
    catch {
        Write-Warn "git pull failed. Attempting forced update..."
        git fetch origin 2>$null
        git reset --hard origin/main 2>$null
    }
    Pop-Location

    Write-Info "Installing dependencies..."
    Push-Location $sourceDir
    try { pnpm install --frozen-lockfile 2>$null } catch { pnpm install }
    Pop-Location

    Write-Info "Building daemon..."
    Push-Location $sourceDir
    pnpm --filter @open-design/daemon build
    Pop-Location

    # Restart scheduled task
    $taskName = 'OpenDesignDaemon'
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Info "Restarting scheduled task..."
        Stop-ScheduledTask -TaskName $taskName 2>$null
        Start-ScheduledTask -TaskName $taskName
    } else {
        Write-Warn "Scheduled task '$taskName' not found. Restart the daemon manually."
    }

    # Health check
    Write-Info "Waiting for health check (up to ${HealthTimeout}s)..."
    $healthOk = $false
    $elapsed  = 0
    while ($elapsed -lt $HealthTimeout) {
        if (Test-HttpHealth $healthUrl) { $healthOk = $true; break }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }

    if ($healthOk) {
        Write-Success "Update complete. Daemon is healthy."
    } else {
        Write-Warn "Health check did not pass. Check logs in $env:USERPROFILE\.open-design\"
    }

} else {
    Write-Err "Unknown install mode: $installMode"
    exit 1
}

Write-Host ""
Write-Success "Open Design updated successfully."
Write-Info "URL: http://127.0.0.1:$Port"
Write-Host ""
