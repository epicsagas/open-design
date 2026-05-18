# One-Click Install Guide

**Parent:** [`spec.md`](spec.md) · **Siblings:** [`self-hosting.md`](self-hosting.md) · [`network-security.md`](network-security.md) · [`setup-wizard.md`](setup-wizard.md)

Deploy Open Design on Linux, macOS, or Windows with a single command. Two installation modes are available:

- **Docker** — pulls a pre-built image and runs via Docker Compose (no build step).
- **Node.js** — clones the repo, builds the daemon, and runs it directly (no Docker required).

When Docker is detected, the installer asks which mode to use. When Docker is absent, it automatically uses Node.js mode.

## Quick reference

```bash
# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/nexu-io/open-design/main/deploy/scripts/install.sh | sh

# Windows (PowerShell)
iex ((New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/nexu-io/open-design/main/deploy/scripts/install.ps1'))
```

Or clone the repo and run locally:

```bash
# Linux / macOS
bash deploy/scripts/install.sh

# Windows
.\deploy\scripts\install.ps1
```

To skip the mode prompt and force a specific mode:

```bash
# Force Docker mode
bash deploy/scripts/install.sh --mode=docker

# Force Node.js mode
bash deploy/scripts/install.sh --mode=node
```

## Prerequisites

### Docker mode

| Platform | Minimum version | Install |
|----------|----------------|---------|
| Docker Engine | 24.0 | [docs.docker.com/engine/install](https://docs.docker.com/engine/install/) |
| Docker Compose plugin | 2.20 | Bundled with Docker Desktop; `apt install docker-compose-plugin` on Linux |
| Docker Desktop (macOS/Windows) | 4.25 | [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/) |

The installer checks for Docker and offers to install it automatically on Ubuntu/Debian, Fedora, and macOS (via Homebrew). Use `--skip-docker-install` / `-SkipDockerInstall` to skip this step.

### Node.js mode

| Platform | Minimum version | Install |
|----------|----------------|---------|
| Node.js | 20.0 | [nodejs.org](https://nodejs.org/) or `fnm install --lts` |
| pnpm | latest | Auto-installed via `corepack` or `npm install -g pnpm` |
| git | any | Usually pre-installed; `apt install git` on Linux |

The installer auto-detects missing prerequisites and offers to install them.

## Interactive install walkthrough

Running the installer without flags launches an interactive wizard:

### Docker mode

```
  ╔══════════════════════════════════════╗
  ║         O P E N   D E S I G N        ║
  ║          One-Click Installer         ║
  ╚══════════════════════════════════════╝

[open-design] OS: Linux ubuntu 24.04 (x86_64)
[open-design] Docker detected.
Install with Docker? [Y/n]: y

Docker image [docker.io/vanjayak/open-design:latest]:
Port [7456]:
Allowed origins (CORS, comma-separated, or empty) []:
Memory limit [384m]:

[open-design] Pulling image: docker.io/vanjayak/open-design:latest
[open-design] Starting Open Design...
[open-design] Waiting for health check (up to 60s)...
[open-design] Daemon is healthy (200 OK)
```

### Node.js mode

```
  ╔══════════════════════════════════════╗
  ║         O P E N   D E S I G N        ║
  ║          One-Click Installer         ║
  ╚══════════════════════════════════════╝

[open-design] OS: macOS 15.5 (arm64)
[open-design] Docker detected.
Install with Docker? [Y/n]: n
[open-design] Node.js: v24.1.0
[open-design] pnpm: 10.33.2
[open-design] Cloning https://github.com/nexu-io/open-design.git...
[open-design] Installing dependencies...
[open-design] Building daemon...
[open-design] Build complete.
[open-design] launchd plist installed: com.open-design.daemon
[open-design] Waiting for health check (up to 60s)...
[open-design] Daemon is healthy (200 OK)
```

## Non-interactive install

For CI, headless servers, and automated provisioning:

```bash
# Linux / macOS — Docker mode
bash deploy/scripts/install.sh --non-interactive --mode=docker [--port 7456] [--image <ref>] [--no-systemd]

# Linux / macOS — Node.js mode
bash deploy/scripts/install.sh --non-interactive --mode=node [--port 7456]

# Windows — Docker mode
.\deploy\scripts\install.ps1 -NonInteractive -Mode docker [-Port 7456] [-Image <ref>]

# Windows — Node.js mode
.\deploy\scripts\install.ps1 -NonInteractive -Mode node [-Port 7456]
```

All prompts are skipped and defaults are used. If required prerequisites are missing, the script exits with an error.

### All flags

**Linux / macOS (`install.sh`)**

| Flag | Description |
|------|-------------|
| `--mode <docker\|node>` | Installation mode (default: prompt if Docker, else node) |
| `--non-interactive` | Skip all prompts |
| `--port <n>` | Host port (default: `7456`) |
| `--image <ref>` | Docker image reference (Docker mode only) |
| `--skip-docker-install` | Never attempt to install Docker |
| `--no-systemd` | Skip systemd unit creation |

**Windows (`install.ps1`)**

| Flag | Description |
|------|-------------|
| `-Mode <docker\|node>` | Installation mode |
| `-NonInteractive` | Skip all prompts |
| `-Port <int>` | Host port (default: `7456`) |
| `-Image <string>` | Docker image reference (Docker mode only) |
| `-SkipDockerInstall` | Never attempt to install Docker Desktop |

## Service management

### Docker mode — Linux (systemd)

The installer creates a `systemd --user` unit that wraps Docker Compose. No `sudo` required.

```bash
systemctl --user status open-design
systemctl --user start open-design
systemctl --user stop open-design
systemctl --user restart open-design
journalctl --user -u open-design -f
```

To skip systemd unit creation, pass `--no-systemd` to the installer.

### Docker mode — macOS and Windows (Docker Desktop)

Docker Desktop manages the container lifecycle. Use Docker Desktop's dashboard, or:

```bash
docker compose -f deploy/docker-compose.yml start
docker compose -f deploy/docker-compose.yml stop
docker compose -f deploy/docker-compose.yml logs -f
```

### Node.js mode — Linux (systemd)

The installer creates a `systemd --user` unit that runs `node` directly.

```bash
systemctl --user status open-design
systemctl --user start open-design
systemctl --user stop open-design
systemctl --user restart open-design
journalctl --user -u open-design -f
```

### Node.js mode — macOS (launchd)

The installer creates a `~/Library/LaunchAgents/com.open-design.daemon.plist`.

```bash
launchctl load   ~/Library/LaunchAgents/com.open-design.daemon.plist
launchctl unload ~/Library/LaunchAgents/com.open-design.daemon.plist
```

Logs: `~/.open-design/daemon.log` and `~/.open-design/daemon.error.log`.

### Node.js mode — Windows (Scheduled Task)

The installer creates a Scheduled Task named `OpenDesignDaemon` that starts at logon.

```powershell
Get-ScheduledTask -TaskName OpenDesignDaemon
Start-ScheduledTask -TaskName OpenDesignDaemon
Stop-ScheduledTask  -TaskName OpenDesignDaemon
```

## Update

The updater reads the install mode from `deploy/.env` and runs the appropriate update path.

```bash
# Linux / macOS
bash deploy/scripts/update.sh

# Windows
.\deploy\scripts\update.ps1
```

**Docker mode:** pulls the latest image, restarts the container, waits for health, prunes old images.

**Node.js mode:** pulls the latest source (`git pull`), reinstalls dependencies (`pnpm install`), rebuilds the daemon (`pnpm --filter @open-design/daemon build`), restarts the service.

To update to a specific Docker image:

```bash
bash deploy/scripts/update.sh --image=docker.io/vanjayak/open-design@sha256:<digest>
```

## Uninstall

The uninstaller reads the install mode from `deploy/.env` and runs the appropriate cleanup.

```bash
# Linux / macOS — remove service, preserve data (default)
bash deploy/scripts/uninstall.sh

# Linux / macOS — remove service AND data
bash deploy/scripts/uninstall.sh --delete-data

# Windows
.\deploy\scripts\uninstall.ps1
.\deploy\scripts\uninstall.ps1 -DeleteData
```

**Docker mode:** stops and removes containers (`docker compose down`), removes the systemd unit, removes `.env`.

**Node.js mode:** stops and removes the service (systemd unit / launchd plist / scheduled task), removes `~/.open-design/source`, removes `.env`.

> **Data is preserved by default.** Pass `--delete-data` / `-DeleteData` to also remove data.
> - Docker mode: removes the `open_design_data` volume.
> - Node.js mode: removes `~/.open-design/data`.

## Configuration

All settings live in `deploy/.env`. Edit it directly or re-run the installer to regenerate it.

### Docker mode variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPEN_DESIGN_INSTALL_MODE` | `docker` | Install mode marker |
| `OPEN_DESIGN_IMAGE` | `docker.io/vanjayak/open-design:latest` | Full image reference |
| `OPEN_DESIGN_PORT` | `7456` | Host-side port (bound to `127.0.0.1`) |
| `OPEN_DESIGN_ALLOWED_ORIGINS` | _(empty)_ | CORS origins for reverse-proxy setups |
| `OPEN_DESIGN_MEM_LIMIT` | `384m` | Container memory cap |
| `NODE_OPTIONS` | `--max-old-space-size=192` | Node.js heap cap inside the container |

### Node.js mode variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPEN_DESIGN_INSTALL_MODE` | `node` | Install mode marker |
| `OPEN_DESIGN_PORT` | `7456` | Daemon port |
| `OPEN_DESIGN_SOURCE_DIR` | `~/.open-design/source` | Cloned repo location |

The daemon always binds to `127.0.0.1:<port>` — never directly exposed to the network. To allow remote access, put an authenticated reverse proxy in front. See [`network-security.md`](network-security.md).

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|-------------|-----|
| `Docker is not installed` | Docker not on PATH | Install Docker Desktop or Docker Engine |
| `Docker daemon is not running` | Docker Desktop not started | Open Docker Desktop or run `sudo systemctl start docker` |
| `Node.js >= 20 is required` | Node.js missing or too old | Install via `fnm install --lts` or [nodejs.org](https://nodejs.org/) |
| `pnpm` not found | pnpm not installed | Run `npm install -g pnpm` or `corepack enable` |
| `Port 7456 is already in use` | Another service on that port | Re-run with `--port 8080` |
| Health check times out | Slow start | Check logs (Docker: `docker compose logs`; Node: `~/.open-design/daemon.log`) |
| `Permission denied` on install.sh | Script not executable | Run `chmod +x deploy/scripts/install.sh` |
| Build fails in Node mode | Missing dependencies | Run `pnpm install` manually in `~/.open-design/source` |
| `.env` has wrong port after re-install | Old backup not restored | Edit `deploy/.env` directly or delete it and re-run |
| Container exits immediately | Image incompatibility | Check `docker compose -f deploy/docker-compose.yml logs` for errors |
| `winget` not found on Windows | Windows 10 older than 1709 | Install Docker Desktop or Node.js manually |

## References

- Docker Compose config: [`deploy/docker-compose.yml`](../deploy/docker-compose.yml)
- Environment template: [`deploy/.env.example`](../deploy/.env.example)
- Self-hosting topologies (PM2, systemd native): [`docs/self-hosting.md`](self-hosting.md)
- Network security and remote access: [`docs/network-security.md`](network-security.md)
- CLI setup wizard (agent, API key, MCP): [`docs/setup-wizard.md`](setup-wizard.md)
