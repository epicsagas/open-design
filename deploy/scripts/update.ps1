#Requires -Version 5.1
<#
.SYNOPSIS
    Open Design — Updater for Windows
.PARAMETER Image
    Pull a specific image reference instead of the one in .env.
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

Write-Host ""
Write-Info "Updating Open Design..."

# Read current port from .env
$Port = 7456
if (Test-Path $EnvFile) {
    $portLine = Get-Content $EnvFile | Where-Object { $_ -match '^OPEN_DESIGN_PORT=(\d+)' }
    if ($portLine -and $Matches[1]) { $Port = [int]$Matches[1] }
}

# Override image if specified
if ($Image) { $env:OPEN_DESIGN_IMAGE = $Image }

# Pull latest image
Write-Info "Pulling latest image..."
docker compose -f $ComposeFile pull
if ($LASTEXITCODE -ne 0) { Write-Warn "Image pull failed."; exit 1 }

# Restart
Write-Info "Restarting service..."
docker compose -f $ComposeFile up -d --no-build
if ($LASTEXITCODE -ne 0) { Write-Warn "Restart failed."; exit 1 }

# Health check
Write-Info "Waiting for health check (up to ${HealthTimeout}s)..."
$healthUrl = "http://127.0.0.1:$Port/api/health"
$healthOk  = $false
$elapsed   = 0

while ($elapsed -lt $HealthTimeout) {
    try {
        $resp = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
        if ($resp.StatusCode -eq 200) { $healthOk = $true; break }
    } catch {}
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

Write-Host ""
Write-Success "Open Design updated successfully."
Write-Info "URL: http://127.0.0.1:$Port"
Write-Host ""
