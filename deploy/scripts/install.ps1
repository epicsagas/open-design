#Requires -Version 5.1
<#
.SYNOPSIS
    Open Design — One-Click Installer for Windows
.DESCRIPTION
    Supports Docker Compose and Node.js installation modes.
    When Docker is detected, asks which mode to use.
    When Docker is absent, automatically uses Node.js mode.
.PARAMETER NonInteractive
    Use defaults for all prompts (no user input).
.PARAMETER Mode
    Installation mode: 'docker', 'node', or 'cloud'. If omitted, prompts when Docker is available.
.PARAMETER Port
    Host port to expose (default: 7456).
.PARAMETER Image
    Docker image reference (Docker mode only, default: docker.io/vanjayak/open-design:latest).
.PARAMETER SkipDockerInstall
    Do not attempt to install Docker Desktop automatically.
.EXAMPLE
    .\install.ps1
    .\install.ps1 -NonInteractive -Port 8080
    .\install.ps1 -Mode node
#>
[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [ValidateSet('docker','node','cloud','')]
    [string]$Mode = '',
    [int]$Port = 7456,
    [string]$Image = 'docker.io/vanjayak/open-design:latest',
    [switch]$SkipDockerInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$DeployDir     = Split-Path -Parent $ScriptDir
$EnvFile       = Join-Path $DeployDir '.env'
$ComposeFile   = Join-Path $DeployDir 'docker-compose.yml'
$HealthTimeout = 60
$NodeSourceDir = Join-Path $env:USERPROFILE '.open-design\source'
$RepoUrl       = 'https://github.com/nexu-io/open-design.git'
$NodeMinMajor  = 20
$DefaultMemLimit = '384m'

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

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  +=====================================+" -ForegroundColor Cyan
Write-Host "  |        O P E N   D E S I G N        |" -ForegroundColor Cyan
Write-Host "  |         One-Click Installer         |" -ForegroundColor Cyan
Write-Host "  +=====================================+" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# 1. Detect Docker
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

$dockerAvailable = (Test-DockerAvailable) -and (Test-DockerRunning)

# ---------------------------------------------------------------------------
# 2. Determine installation mode
# ---------------------------------------------------------------------------
if ($Mode) {
    $installMode = $Mode
    Write-Info "Mode: $installMode (specified via -Mode)"
} else {
    if ($dockerAvailable) {
        Write-Info "Docker detected."
        if (-not $NonInteractive) {
            $answer = Read-Host "Install with Docker? [Y/n]"
            if ($answer -match '^[Nn]') {
                $installMode = 'node'
            } else {
                $installMode = 'docker'
            }
        } else {
            $installMode = 'docker'
        }
    } else {
        Write-Info "Docker not detected. Using Node.js mode."
        $installMode = 'node'
    }
}

# ---------------------------------------------------------------------------
# 3. Port conflict detection
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

# =========================================================================
# CLOUD MODE
# =========================================================================
if ($installMode -eq 'cloud') {

    Write-Host ""
    Write-Info "Cloud deployment platforms:"
    Write-Host "  1) Fly.io          — Global edge, persistent volumes"
    Write-Host "  2) Railway         — Git-based, zero config"
    Write-Host "  3) Render          — Blueprint from render.yaml"
    Write-Host "  4) Google Cloud Run— Serverless containers"
    Write-Host "  5) AWS App Runner  — Managed container service"
    Write-Host "  6) Koyeb           — Global edge deployment"
    Write-Host ""

    if ($NonInteractive) {
        Write-Err "Cloud mode requires interactive platform selection."
        Write-Info "Use platform CLIs directly with config files in deploy\:"
        Write-Info "  fly deploy -c deploy\fly.toml"
        Write-Info "  railway up"
        Write-Info "  gcloud run deploy --image docker.io/vanjayak/open-design:latest"
        exit 1
    }

    $choice = Read-Host "Choose platform (1-6) [1]"
    if (-not $choice) { $choice = '1' }

    switch ($choice) {
        { $_ -in '1', 'fly' } {
            $fly = Get-Command fly -ErrorAction SilentlyContinue
            if (-not $fly) {
                Write-Warn "fly CLI not found."
                $ans = Read-Host "Install fly CLI via PowerShell? [y/N]"
                if ($ans -match '^[Yy]') {
                    Invoke-RestMethod https://fly.io/install.ps1 | Invoke-Expression
                }
                $fly = Get-Command fly -ErrorAction SilentlyContinue
            }
            if (-not $fly) { Write-Err "fly CLI required. Install: https://fly.io/docs/hands-on/install-flyctl/"; exit 1 }
            Write-Info "Launching on Fly.io..."
            $flyArgs = @('launch', '--config', "$DeployDir\fly.toml", '--image', 'docker.io/vanjayak/open-design:latest', '--now')
            & fly $flyArgs
            if ($LASTEXITCODE -ne 0) { Write-Err "fly launch failed. Try: fly deploy -c $DeployDir\fly.toml"; exit 1 }
            Write-Success "Deployed to Fly.io."
            Write-Info "Set secrets: fly secrets set OD_API_TOKEN=your-token"
        }
        { $_ -in '2', 'railway' } {
            $rw = Get-Command railway -ErrorAction SilentlyContinue
            if (-not $rw) {
                Write-Warn "Railway CLI not found."
                $ans = Read-Host "Install Railway CLI via npm? [y/N]"
                if ($ans -match '^[Yy]') { npm install -g @railway/cli 2>$null }
                $rw = Get-Command railway -ErrorAction SilentlyContinue
            }
            if (-not $rw) { Write-Err "Railway CLI required. Install: npm install -g @railway/cli"; exit 1 }
            Write-Info "Deploying to Railway..."
            & railway up
            Write-Success "Deployed to Railway."
            Write-Info "Set env vars: railway variables set OD_API_TOKEN=your-token"
        }
        { $_ -in '3', 'render' } {
            Write-Info "Render uses deploy\render.yaml for configuration."
            Write-Host ""
            Write-Host "  1. Go to https://dashboard.render.com/new"
            Write-Host "  2. Connect your GitHub repo"
            Write-Host "  3. Render detects deploy\render.yaml automatically"
            Write-Host ""
            Write-Info "Config: $DeployDir\render.yaml"
        }
        { $_ -in '4', 'cloudrun', 'gcp' } {
            $gcloud = Get-Command gcloud -ErrorAction SilentlyContinue
            if (-not $gcloud) { Write-Err "gcloud CLI required. Install: https://cloud.google.com/sdk/docs/install"; exit 1 }
            $region = Read-Host "Region [us-central1]"
            if (-not $region) { $region = 'us-central1' }
            Write-Info "Deploying to Google Cloud Run ($region)..."
            & gcloud run deploy open-design --image="docker.io/vanjayak/open-design:latest" --region=$region --port=7456 --memory=512Mi --cpu=1 --min-instances=0 --max-instances=3 --allow-unauthenticated --set-env-vars="NODE_ENV=production,OD_BIND_HOST=0.0.0.0,OD_PORT=7456"
            if ($LASTEXITCODE -ne 0) { Write-Err "gcloud run deploy failed."; exit 1 }
            Write-Success "Deployed to Cloud Run."
            Write-Info "Config reference: $DeployDir\cloud-run.yaml"
        }
        { $_ -in '5', 'apprunner', 'aws' } {
            $aws = Get-Command aws -ErrorAction SilentlyContinue
            if (-not $aws) { Write-Err "AWS CLI required. Install: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"; exit 1 }
            $region = Read-Host "Region [us-east-1]"
            if (-not $region) { $region = 'us-east-1' }
            Write-Info "Deploying to AWS App Runner ($region)..."
            & aws apprunner create-service --service-name open-design --source-configuration "ImageRepository={ImageIdentifier=docker.io/vanjayak/open-design:latest,ImageRepositoryType=ECR_PUBLIC},AutoDeploymentsEnabled=false" --instance-configuration "Cpu=1 vCPU,Memory=512 MB" --port-configuration "Port=7456,Protocol=HTTP" --health-check-configuration "Protocol=HTTP,Path=/api/health,Interval=30,Timeout=5,HealthyThreshold=2,UnhealthyThreshold=3" --region $region
            if ($LASTEXITCODE -ne 0) { Write-Err "AWS App Runner deploy failed."; Write-Info "Config: $DeployDir\app-runner.yaml"; exit 1 }
            Write-Success "Deployed to AWS App Runner."
        }
        { $_ -in '6', 'koyeb' } {
            $koyeb = Get-Command koyeb -ErrorAction SilentlyContinue
            if (-not $koyeb) {
                Write-Info "Koyeb CLI not found. Install: https://www.koyeb.com/docs/develop/cli"
                Write-Host ""
                Write-Host "  Dashboard deploy:"
                Write-Host "  1. Go to https://app.koyeb.com/apps/create"
                Write-Host "  2. Select 'Docker Image'"
                Write-Host "  3. Enter: docker.io/vanjayak/open-design:latest"
                Write-Host "  4. Expose port 7456 (HTTP)"
                Write-Host "  5. Add env vars: NODE_ENV, OD_BIND_HOST, OD_PORT"
                Write-Host "  6. Deploy"
                Write-Info "Reference: $DeployDir\koyeb.yaml"
            } else {
                Write-Info "Deploying to Koyeb..."
                & koyeb apps create open-design 2>$null; $null = $?
                & koyeb services create open-design --app open-design --docker docker.io/vanjayak/open-design:latest --ports 7456:http --env "NODE_ENV=production" --env "OD_BIND_HOST=0.0.0.0" --env "OD_PORT=7456"
                Write-Success "Deployed to Koyeb."
            }
        }
        default { Write-Err "Invalid choice: $choice"; exit 1 }
    }

    Write-Host ""
    Write-Host "  -- Cloud Deployment Initiated --" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Config files in deploy\:"
    Write-Host "    fly.toml         Fly.io"
    Write-Host "    railway.toml     Railway"
    Write-Host "    render.yaml      Render"
    Write-Host "    cloud-run.yaml   Google Cloud Run"
    Write-Host "    app-runner.yaml  AWS App Runner"
    Write-Host "    koyeb.yaml       Koyeb"
    Write-Host ""
    exit 0
}

# =========================================================================
# DOCKER MODE
# =========================================================================
if ($installMode -eq 'docker') {

    # --- Docker prerequisites ---
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

    # --- Interactive prompts ---
    $AllowedOrigins = ''
    $MemLimit = $DefaultMemLimit

    if (-not $NonInteractive) {
        $inputImage = Read-Host "Docker image [$Image]"
        if ($inputImage) { $Image = $inputImage }

        $inputPort = Read-Host "Port [$Port]"
        if ($inputPort -match '^\d+$') { $Port = [int]$inputPort }

        $AllowedOrigins = Read-Host "Allowed origins (CORS, comma-separated, or empty) []"

        $inputMem = Read-Host "Memory limit [$MemLimit]"
        if ($inputMem) { $MemLimit = $inputMem }
    }

    # --- Generate .env ---
    if (Test-Path $EnvFile) {
        $backup = "$EnvFile.$((Get-Date).ToString('yyyyMMddHHmmss')).bak"
        Write-Info "Existing .env found. Backing up to $backup"
        Copy-Item $EnvFile $backup
    }

    $envContent = @"
# Generated by install.ps1 on $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
OPEN_DESIGN_INSTALL_MODE=docker
OPEN_DESIGN_IMAGE=$Image
OPEN_DESIGN_PORT=$Port
OPEN_DESIGN_ALLOWED_ORIGINS=$AllowedOrigins
OPEN_DESIGN_MEM_LIMIT=$MemLimit
NODE_OPTIONS=--max-old-space-size=192
"@
    Set-Content -Path $EnvFile -Value $envContent -Encoding UTF8
    Write-Info "Written $EnvFile"

    # --- Pull and start ---
    Write-Info "Pulling image: $Image"
    docker compose -f $ComposeFile pull
    if ($LASTEXITCODE -ne 0) { Write-Err "Image pull failed."; exit 1 }

    Write-Info "Starting Open Design..."
    docker compose -f $ComposeFile up -d --no-build
    if ($LASTEXITCODE -ne 0) { Write-Err "Failed to start containers."; exit 1 }

    # --- Health check ---
    Write-Info "Waiting for health check (up to ${HealthTimeout}s)..."
    $healthUrl = "http://127.0.0.1:$Port/api/health"
    $healthOk  = $false
    $elapsed   = 0

    while ($elapsed -lt $HealthTimeout) {
        if (Test-HttpHealth $healthUrl) { $healthOk = $true; break }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }

    if ($healthOk) {
        Write-Success "Daemon is healthy (200 OK)"
    } else {
        Write-Warn "Health check did not pass within ${HealthTimeout}s."
        Write-Info "Check logs: docker compose -f $ComposeFile logs"
    }

    # --- Summary ---
    Write-Host ""
    Write-Host "  -- Installation Complete (Docker) --" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Mode:       docker"
    Write-Host "  URL:        http://127.0.0.1:$Port"
    Write-Host "  Image:      $Image"
    Write-Host "  Data vol:   open_design_data"
    Write-Host "  Config:     $EnvFile"
    Write-Host ""
    Write-Host "  Next steps:"
    Write-Host "    Update:    $ScriptDir\update.ps1"
    Write-Host "    Uninstall: $ScriptDir\uninstall.ps1"
    Write-Host "    Logs:      docker compose -f $ComposeFile logs -f"
    Write-Host ""

# =========================================================================
# NODE MODE
# =========================================================================
} elseif ($installMode -eq 'node') {

    # --- Node.js prerequisites ---
    function Test-NodeVersion {
        try {
            $null = Get-Command node -ErrorAction Stop
            $ver = (node -e 'process.stdout.write(process.versions.node)' 2>$null) -split '\.'
            return ([int]$ver[0] -ge $NodeMinMajor)
        } catch { return $false }
    }

    function Test-Pnpm {
        try { $null = Get-Command pnpm -ErrorAction Stop; return $true }
        catch { return $false }
    }

    function Test-Git {
        try { $null = Get-Command git -ErrorAction Stop; return $true }
        catch { return $false }
    }

    if (-not (Test-NodeVersion)) {
        Write-Warn "Node.js >= $NodeMinMajor is not installed."
        Write-Info "Download from: https://nodejs.org/"
        Write-Info "Or install via winget: winget install OpenJS.NodeJS.LTS"
        if (-not $NonInteractive) {
            $answer = Read-Host "Install Node.js via winget? [y/N]"
            if ($answer -match '^[Yy]') {
                Write-Info "Running: winget install OpenJS.NodeJS.LTS"
                winget install --id OpenJS.NodeJS.LTS -e
                Write-Info "Node.js installed. Re-run this script in a new terminal."
                exit 0
            }
        }
        Write-Err "Node.js >= $NodeMinMajor is required. Install it and re-run."
        exit 1
    }

    $nodeVer = node --version 2>$null
    Write-Info "Node.js: $nodeVer"

    if (-not (Test-Pnpm)) {
        Write-Warn "pnpm is not installed."
        if (Get-Command corepack -ErrorAction SilentlyContinue) {
            Write-Info "Enabling pnpm via corepack..."
            corepack enable 2>$null
            corepack prepare pnpm@latest --activate 2>$null
        }
        if (-not (Test-Pnpm)) {
            Write-Info "Installing pnpm via npm..."
            npm install -g pnpm 2>$null
        }
        if (-not (Test-Pnpm)) {
            Write-Err "Could not install pnpm. Install it manually: npm install -g pnpm"
            exit 1
        }
    }

    $pnpmVer = pnpm --version 2>$null
    Write-Info "pnpm: $pnpmVer"

    if (-not (Test-Git)) {
        Write-Warn "git is not installed."
        Write-Info "Install via winget: winget install Git.Git"
        Write-Info "Or download from: https://git-scm.com/"
        if (-not $NonInteractive) {
            $answer = Read-Host "Install git via winget? [y/N]"
            if ($answer -match '^[Yy]') {
                winget install --id Git.Git -e
                Write-Info "git installed. Re-run this script in a new terminal."
                exit 0
            }
        }
        Write-Err "git is required for Node.js mode. Install it and re-run."
        exit 1
    }

    # --- Clone or update source ---
    if (Test-Path (Join-Path $NodeSourceDir '.git')) {
        Write-Info "Updating existing source at $NodeSourceDir..."
        Push-Location $NodeSourceDir
        try { git pull --ff-only 2>$null }
        catch {
            Write-Warn "git pull failed. Attempting fresh clone..."
            Pop-Location
            Remove-Item -Recurse -Force $NodeSourceDir
            Write-Info "Cloning $RepoUrl..."
            git clone $RepoUrl $NodeSourceDir
        }
        if (-not (Test-Path variable:script:alreadyPopped)) { Pop-Location }
    } else {
        Write-Info "Cloning $RepoUrl..."
        $parentDir = Split-Path -Parent $NodeSourceDir
        if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
        git clone $RepoUrl $NodeSourceDir
    }

    # --- Build ---
    Write-Info "Installing dependencies..."
    Push-Location $NodeSourceDir
    try { pnpm install --frozen-lockfile 2>$null } catch { pnpm install }
    Pop-Location

    Write-Info "Building daemon..."
    Push-Location $NodeSourceDir
    pnpm --filter @open-design/daemon build
    Pop-Location

    $cliPath = Join-Path $NodeSourceDir 'apps\daemon\dist\cli.js'
    if (-not (Test-Path $cliPath)) {
        Write-Err "Build failed: $cliPath not found."
        exit 1
    }
    Write-Success "Build complete."

    # --- Generate .env ---
    if (Test-Path $EnvFile) {
        $backup = "$EnvFile.$((Get-Date).ToString('yyyyMMddHHmmss')).bak"
        Write-Info "Existing .env found. Backing up to $backup"
        Copy-Item $EnvFile $backup
    }

    $envContent = @"
# Generated by install.ps1 on $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
OPEN_DESIGN_INSTALL_MODE=node
OPEN_DESIGN_PORT=$Port
OPEN_DESIGN_SOURCE_DIR=$NodeSourceDir
"@
    Set-Content -Path $EnvFile -Value $envContent -Encoding UTF8
    Write-Info "Written $EnvFile"

    # --- Service registration (Scheduled Task) ---
    $taskName = 'OpenDesignDaemon'
    $nodeBin  = (Get-Command node).Source

    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Info "Updating existing scheduled task..."
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }

    $action = New-ScheduledTaskAction -Execute $nodeBin -Argument "`"$cliPath`" --port $Port --no-open" -WorkingDirectory $NodeSourceDir
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Write-Success "Scheduled task registered: $taskName"
    Write-Info "Manage with: Get-ScheduledTask -TaskName $taskName"

    # --- Health check ---
    Write-Info "Waiting for health check (up to ${HealthTimeout}s)..."
    $healthUrl = "http://127.0.0.1:$Port/api/health"
    $healthOk  = $false
    $elapsed   = 0

    while ($elapsed -lt $HealthTimeout) {
        if (Test-HttpHealth $healthUrl) { $healthOk = $true; break }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }

    if ($healthOk) {
        Write-Success "Daemon is healthy (200 OK)"
    } else {
        Write-Warn "Health check did not pass within ${HealthTimeout}s."
        Write-Info "Check logs in $env:USERPROFILE\.open-design\"
    }

    # --- Summary ---
    Write-Host ""
    Write-Host "  -- Installation Complete (Node.js) --" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Mode:       node"
    Write-Host "  URL:        http://127.0.0.1:$Port"
    Write-Host "  Source:     $NodeSourceDir"
    Write-Host "  Data:       $env:USERPROFILE\.open-design\data"
    Write-Host "  Config:     $EnvFile"
    Write-Host "  Service:    Scheduled Task ($taskName)"
    Write-Host ""
    Write-Host "  Next steps:"
    Write-Host "    Update:    $ScriptDir\update.ps1"
    Write-Host "    Uninstall: $ScriptDir\uninstall.ps1"
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Launch setup wizard
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
