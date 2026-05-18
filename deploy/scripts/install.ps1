#Requires -Version 5.1
<#
.SYNOPSIS
    Open Design — One-Click Installer for Windows
.DESCRIPTION
    Docker Compose wrapper. Checks prerequisites, generates .env, starts the service.
.PARAMETER NonInteractive
    Use defaults for all prompts (no user input).
.PARAMETER Port
    Host port to expose (default: 7456).
.PARAMETER Image
    Docker image reference (default: docker.io/vanjayak/open-design:latest).
.PARAMETER SkipDockerInstall
    Do not attempt to install Docker Desktop automatically.
.EXAMPLE
    .\install.ps1
    .\install.ps1 -NonInteractive -Port 8080
    iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/nexu-io/open-design/main/deploy/scripts/install.ps1'))
#>
[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [int]$Port = 7456,
    [string]$Image = 'docker.io/vanjayak/open-design:latest',
    [switch]$SkipDockerInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$DeployDir  = Split-Path -Parent $ScriptDir
$EnvFile    = Join-Path $DeployDir '.env'
$ComposeFile = Join-Path $DeployDir 'docker-compose.yml'
$HealthTimeout = 60

function Write-Info    { param($msg) Write-Host "[open-design] $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[open-design] $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[open-design] $msg" -ForegroundColor Yellow }
function Write-Err     { param($msg) Write-Host "[open-design] $msg" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  +======================================+" -ForegroundColor Cyan
Write-Host "  |     O P E N   D E S I G N           |" -ForegroundColor Cyan
Write-Host "  |     One-Click Installer (Windows)    |" -ForegroundColor Cyan
Write-Host "  +======================================+" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# 1. Docker prerequisite check
# ---------------------------------------------------------------------------
function Test-DockerAvailable {
    try { $null = Get-Command docker -ErrorAction Stop; return $true }
    catch { return $false }
}

function Test-DockerRunning {
    try { $null = docker info 2>&1; return $LASTEXITCODE -eq 0 }
    catch { return $false }
}

function Test-ComposeAvailable {
    try {
        $null = docker compose version 2>&1
        return $LASTEXITCODE -eq 0
    } catch { return $false }
}

if (-not (Test-DockerAvailable)) {
    Write-Warn "Docker is not installed."
    if ($SkipDockerInstall) {
        Write-Err "Docker is required. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
        exit 1
    }
    if (-not $NonInteractive) {
        $answer = Read-Host "Install Docker Desktop via winget? [y/N]"
        if ($answer -match '^[Yy]') {
            Write-Info "Running: winget install Docker.DockerDesktop"
            winget install --id Docker.DockerDesktop -e
            Write-Info "Docker Desktop installed. Please start it and re-run this script."
            exit 0
        }
    }
    Write-Err "Docker Desktop is required. Download from: https://www.docker.com/products/docker-desktop/"
    exit 1
}

if (-not (Test-ComposeAvailable)) {
    Write-Err "Docker Compose is not available. Update Docker Desktop to a recent version."
    exit 1
}

if (-not (Test-DockerRunning)) {
    Write-Warn "Docker daemon is not running. Start Docker Desktop and try again."
    exit 1
}

$dockerVer  = (docker --version 2>&1) -replace "`r",""
$composeVer = (docker compose version 2>&1) -replace "`r",""
Write-Info "Docker:  $dockerVer"
Write-Info "Compose: $composeVer"

# ---------------------------------------------------------------------------
# 2. Port conflict detection
# ---------------------------------------------------------------------------
$portInUse = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($portInUse) {
    Write-Warn "Port $Port is already in use."
    if (-not $NonInteractive) {
        $newPort = Read-Host "Enter a different port [7456]"
        if ($newPort -match '^\d+$') { $Port = [int]$newPort } else { $Port = 7456 }
    } else {
        Write-Err "Port $Port is occupied. Use -Port to specify a different one."
        exit 1
    }
}

# ---------------------------------------------------------------------------
# 3. Interactive prompts
# ---------------------------------------------------------------------------
$AllowedOrigins = ''
$MemLimit = '384m'

if (-not $NonInteractive) {
    $inputImage = Read-Host "Docker image [$Image]"
    if ($inputImage) { $Image = $inputImage }

    $inputPort = Read-Host "Port [$Port]"
    if ($inputPort -match '^\d+$') { $Port = [int]$inputPort }

    $AllowedOrigins = Read-Host "Allowed origins (CORS, comma-separated, or empty) []"

    $inputMem = Read-Host "Memory limit [$MemLimit]"
    if ($inputMem) { $MemLimit = $inputMem }
}

# ---------------------------------------------------------------------------
# 4. Generate .env
# ---------------------------------------------------------------------------
if (Test-Path $EnvFile) {
    $backup = "$EnvFile.$((Get-Date).ToString('yyyyMMddHHmmss')).bak"
    Write-Info "Existing .env found. Backing up to $backup"
    Copy-Item $EnvFile $backup
}

$envContent = @"
# Generated by install.ps1 on $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
OPEN_DESIGN_IMAGE=$Image
OPEN_DESIGN_PORT=$Port
OPEN_DESIGN_ALLOWED_ORIGINS=$AllowedOrigins
OPEN_DESIGN_MEM_LIMIT=$MemLimit
NODE_OPTIONS=--max-old-space-size=192
"@
Set-Content -Path $EnvFile -Value $envContent -Encoding UTF8
Write-Info "Written $EnvFile"

# ---------------------------------------------------------------------------
# 5. Pull and start
# ---------------------------------------------------------------------------
Write-Info "Pulling image: $Image"
docker compose -f $ComposeFile pull
if ($LASTEXITCODE -ne 0) { Write-Err "Image pull failed."; exit 1 }

Write-Info "Starting Open Design..."
docker compose -f $ComposeFile up -d --no-build
if ($LASTEXITCODE -ne 0) { Write-Err "Failed to start containers."; exit 1 }

# ---------------------------------------------------------------------------
# 6. Health check
# ---------------------------------------------------------------------------
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
    Write-Success "Daemon is healthy (200 OK)"
} else {
    Write-Warn "Health check did not pass within ${HealthTimeout}s."
    Write-Info "Check logs: docker compose -f $ComposeFile logs"
}

# ---------------------------------------------------------------------------
# 7. Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  -- Installation Complete --" -ForegroundColor Green
Write-Host ""
Write-Host "  URL:       http://127.0.0.1:$Port"
Write-Host "  Image:     $Image"
Write-Host "  Data vol:  open_design_data"
Write-Host "  Config:    $EnvFile"
Write-Host ""
Write-Host "  Next steps:"
Write-Host "    Update:    $ScriptDir\update.ps1"
Write-Host "    Uninstall: $ScriptDir\uninstall.ps1"
Write-Host "    Logs:      docker compose -f $ComposeFile logs -f"
Write-Host ""

# ---------------------------------------------------------------------------
# 8. Launch setup wizard
# ---------------------------------------------------------------------------
$odCmd = Get-Command od -ErrorAction SilentlyContinue
if (-not $NonInteractive -and $odCmd) {
    Write-Info "Launching setup wizard..."
    Write-Host ""
    $env:OD_PORT = "$Port"
    & od setup
} elseif (-not $NonInteractive) {
    Write-Info "Run 'od setup' to configure API keys, agents, and MCP servers."
    Write-Host "    Open http://127.0.0.1:$Port in your browser"
    Write-Host ""
} else {
    Write-Host "    Open http://127.0.0.1:$Port in your browser"
    Write-Host ""
}
