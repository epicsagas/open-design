#!/bin/sh
# Open Design — One-Click Installer
# Supports Docker Compose and Node.js installation modes
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/nexu-io/open-design/main/deploy/scripts/install.sh | sh
#   ./install.sh [--mode docker|node] [--non-interactive] [--port 7456] [--no-systemd]
set -eu

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DEFAULT_PORT=7456
DEFAULT_IMAGE="docker.io/vanjayak/open-design:latest"
DEFAULT_MEM_LIMIT="384m"
HEALTH_TIMEOUT=60
NODE_SOURCE_DIR="${HOME}/.open-design/source"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${DEPLOY_DIR}/.env"
COMPOSE_FILE="${DEPLOY_DIR}/docker-compose.yml"
REPO_URL="https://github.com/nexu-io/open-design.git"
NODE_MIN_MAJOR=20

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
BOLD="" RED="" GREEN="" YELLOW="" RESET=""
if [ -t 1 ]; then
  BOLD="\033[1m" RED="\033[31m" GREEN="\033[32m" YELLOW="\033[33m" RESET="\033[0m"
fi

info()    { printf "${BOLD}[open-design]${RESET} %s\n" "$1"; }
warn()    { printf "${BOLD}${YELLOW}[open-design]${RESET} %s\n" "$1" >&2; }
error()   { printf "${BOLD}${RED}[open-design]${RESET} %s\n" "$1" >&2; }
success() { printf "${BOLD}${GREEN}[open-design]${RESET} %s\n" "$1"; }

prompt_text() {
  _label="$1" _default="$2"
  if [ "$NON_INTERACTIVE" = "1" ]; then
    _val="$_default"
    return
  fi
  printf "%s [%s]: " "$_label" "$_default" >&2
  read -r _val
  _val="${_val:-$_default}"
}

prompt_confirm() {
  _question="$1" _default="$2"
  if [ "$NON_INTERACTIVE" = "1" ]; then
    return 0
  fi
  _yn_default="y"
  if [ "$_default" = "0" ]; then _yn_default="n"; fi
  printf "%s [%s]: " "$_question" "$_yn_default" >&2
  read -r _yn
  case "$_yn" in
    [Yy]*) return 0 ;;
    [Nn]*) return 1 ;;
    *) [ "$_default" = "1" ] && return 0; return 1 ;;
  esac
}

http_get_code() {
  _url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -s -o /dev/null -w '%{http_code}' "$_url" 2>/dev/null || echo '000'
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O /dev/null --server-response "$_url" 2>&1 | grep 'HTTP/' | tail -1 | awk '{print $2}'
  else
    echo '000'
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
NON_INTERACTIVE=0
OPT_PORT=""
OPT_IMAGE=""
OPT_SKIP_DOCKER=0
OPT_NO_SYSTEMD=0
OPT_MODE=""

for arg in "$@"; do
  case "$arg" in
    --non-interactive) NON_INTERACTIVE=1 ;;
    --port=*) OPT_PORT="${arg#--port=}" ;;
    --image=*) OPT_IMAGE="${arg#--image=}" ;;
    --skip-docker-install) OPT_SKIP_DOCKER=1 ;;
    --no-systemd) OPT_NO_SYSTEMD=1 ;;
    --mode=*) OPT_MODE="${arg#--mode=}" ;;
    --help|-h)
      echo "Usage: install.sh [options]"
      echo ""
      echo "Options:"
      echo "  --mode <docker|node>    Installation mode (default: prompt if Docker, else node)"
      echo "  --non-interactive       Use defaults for all prompts"
      echo "  --port <n>              Host port (default: ${DEFAULT_PORT})"
      echo "  --image <ref>           Docker image reference (Docker mode only)"
      echo "  --skip-docker-install   Do not attempt to install Docker"
      echo "  --no-systemd            Skip systemd unit creation"
      echo "  --help                  Show this help"
      echo ""
      echo "Modes:"
      echo "  docker    Install via Docker Compose (requires Docker)"
      echo "  node      Install via Node.js (clone repo, build, run directly)"
      echo ""
      echo "When --mode is not specified:"
      echo "  - Docker detected: asks which mode to use"
      echo "  - No Docker: automatically uses Node.js mode"
      exit 0
      ;;
    *)
      warn "Unknown argument: $arg (ignored)"
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
printf "\n"
printf "${BOLD}  ╔═════════════════════════════════════╗${RESET}\n"
printf "${BOLD}  ║        O P E N   D E S I G N        ║${RESET}\n"
printf "${BOLD}  ║         One-Click Installer         ║${RESET}\n"
printf "${BOLD}  ╚═════════════════════════════════════╝${RESET}\n"
printf "\n"

# ---------------------------------------------------------------------------
# 1. OS detection
# ---------------------------------------------------------------------------
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux)
    if [ -f /etc/os-release ]; then
      # shellcheck disable=SC1091
      . /etc/os-release
      DISTRO="$ID"
      DISTRO_VERSION="$VERSION_ID"
    else
      DISTRO="unknown"
      DISTRO_VERSION=""
    fi
    info "OS: Linux ${DISTRO} ${DISTRO_VERSION} (${ARCH})"
    ;;
  Darwin)
    info "OS: macOS $(sw_vers -productVersion) (${ARCH})"
    DISTRO="macos"
    ;;
  *)
    error "Unsupported OS: ${OS}. This script supports Linux and macOS."
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# 2. Determine installation mode
# ---------------------------------------------------------------------------
DOCKER_AVAILABLE=0
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  DOCKER_AVAILABLE=1
fi

if [ -n "$OPT_MODE" ]; then
  INSTALL_MODE="$OPT_MODE"
  info "Mode: ${INSTALL_MODE} (specified via --mode)"
else
  if [ "$DOCKER_AVAILABLE" = "1" ]; then
    info "Docker detected."
    if prompt_confirm "Install with Docker?" 1; then
      INSTALL_MODE="docker"
    else
      INSTALL_MODE="node"
    fi
  else
    info "Docker not detected. Using Node.js mode."
    INSTALL_MODE="node"
  fi
fi

if [ "$INSTALL_MODE" != "docker" ] && [ "$INSTALL_MODE" != "node" ]; then
  error "Unknown mode: ${INSTALL_MODE}. Use 'docker' or 'node'."
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Port conflict detection
# ---------------------------------------------------------------------------
PORT="${OPT_PORT:-$DEFAULT_PORT}"

if [ "$PORT" != "$DEFAULT_PORT" ] || [ "$NON_INTERACTIVE" = "0" ]; then
  if command -v ss >/dev/null 2>&1; then
    PORT_IN_USE="$(ss -tlnp 2>/dev/null | grep ":${PORT} " || true)"
  elif command -v lsof >/dev/null 2>&1; then
    PORT_IN_USE="$(lsof -i :"$PORT" 2>/dev/null || true)"
  else
    PORT_IN_USE=""
  fi

  if [ -n "$PORT_IN_USE" ]; then
    warn "Port ${PORT} is already in use."
    if [ "$NON_INTERACTIVE" = "0" ]; then
      printf "Enter a different port [%s]: " "$DEFAULT_PORT" >&2
      read -r _port_input
      PORT="${_port_input:-$DEFAULT_PORT}"
    else
      error "Port ${PORT} is occupied. Use --port= to specify a different one."
      exit 1
    fi
  fi
fi

# =========================================================================
# DOCKER MODE
# =========================================================================
if [ "$INSTALL_MODE" = "docker" ]; then

# --- Docker prerequisites ---
check_docker_compose() {
  if docker compose version >/dev/null 2>&1; then return 0; fi
  if command -v docker-compose >/dev/null 2>&1; then return 0; fi
  return 1
}

if [ "$DOCKER_AVAILABLE" = "0" ]; then
  if [ "$OPT_SKIP_DOCKER" = "1" ]; then
    error "Docker is not installed and --skip-docker-install was set."
    exit 1
  fi

  warn "Docker is not installed."

  case "$DISTRO" in
    ubuntu|debian)
      install_cmd="sudo apt-get update && sudo apt-get install -y docker.io docker-compose-plugin"
      ;;
    fedora)
      install_cmd="sudo dnf install -y docker docker-compose-plugin"
      ;;
    centos|rhel|rocky|alma)
      install_cmd="sudo yum install -y docker docker-compose-plugin"
      ;;
    macos)
      install_cmd="brew install --cask docker"
      ;;
    *)
      install_cmd=""
      error "Cannot auto-detect Docker install method for: ${DISTRO}"
      info "Install Docker manually: https://docs.docker.com/get-docker/"
      ;;
  esac

  if [ -n "$install_cmd" ]; then
    info "Install with: ${install_cmd}"
    if [ "$DISTRO" = "macos" ]; then
      info "Or download from: https://www.docker.com/products/docker-desktop/"
    fi
  fi

  if [ "$NON_INTERACTIVE" = "0" ] && [ -n "$install_cmd" ]; then
    if prompt_confirm "Install Docker now?" 0; then
      info "Running: ${install_cmd}"
      eval "$install_cmd"
    else
      error "Docker is required for Docker mode. Use --mode node instead."
      exit 1
    fi
  else
    error "Docker is required for Docker mode. Use --mode node instead."
    exit 1
  fi
fi

if ! check_docker_compose; then
  error "Docker Compose is not available."
  info "Install the compose plugin: https://docs.docker.com/compose/install/"
  exit 1
fi

DOCKER_VERSION="$(docker --version 2>/dev/null || echo 'unknown')"
COMPOSE_VERSION="$(docker compose version 2>/dev/null || echo 'unknown')"
info "Docker: ${DOCKER_VERSION}"
info "Compose: ${COMPOSE_VERSION}"

# --- Interactive prompts ---
IMAGE="${OPT_IMAGE:-$DEFAULT_IMAGE}"
ALLOWED_ORIGINS=""
MEM_LIMIT="$DEFAULT_MEM_LIMIT"

if [ "$NON_INTERACTIVE" = "0" ]; then
  printf "\n"
  prompt_text "Docker image" "$DEFAULT_IMAGE"
  IMAGE="$_val"
  prompt_text "Port" "$PORT"
  PORT="$_val"
  prompt_text "Allowed origins (CORS, comma-separated, or empty)" ""
  ALLOWED_ORIGINS="$_val"
  prompt_text "Memory limit" "$DEFAULT_MEM_LIMIT"
  MEM_LIMIT="$_val"
fi

# --- Generate .env ---
if [ -f "$ENV_FILE" ]; then
  BACKUP="${ENV_FILE}.$(date +%Y%m%d%H%M%S).bak"
  info "Existing .env found. Backing up to ${BACKUP}"
  cp "$ENV_FILE" "$BACKUP"
fi

cat > "$ENV_FILE" << ENVFILE
# Generated by install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
OPEN_DESIGN_INSTALL_MODE=docker
OPEN_DESIGN_IMAGE=${IMAGE}
OPEN_DESIGN_PORT=${PORT}
OPEN_DESIGN_ALLOWED_ORIGINS=${ALLOWED_ORIGINS}
OPEN_DESIGN_MEM_LIMIT=${MEM_LIMIT}
NODE_OPTIONS=--max-old-space-size=192
ENVFILE

info "Written ${ENV_FILE}"

# --- Pull and start ---
info "Pulling image: ${IMAGE}"
docker compose -f "$COMPOSE_FILE" pull

info "Starting Open Design..."
docker compose -f "$COMPOSE_FILE" up -d --no-build

# --- Health check ---
info "Waiting for health check (up to ${HEALTH_TIMEOUT}s)..."
HEALTH_URL="http://127.0.0.1:${PORT}/api/health"
HEALTH_OK=0
ELAPSED=0

while [ "$ELAPSED" -lt "$HEALTH_TIMEOUT" ]; do
  HTTP_CODE="$(http_get_code "$HEALTH_URL")"
  if [ "$HTTP_CODE" = "200" ]; then
    HEALTH_OK=1
    break
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [ "$HEALTH_OK" = "1" ]; then
  success "Daemon is healthy (200 OK)"
else
  warn "Health check did not pass within ${HEALTH_TIMEOUT}s."
  info "Check status: docker compose -f ${COMPOSE_FILE} logs"
fi

# --- systemd unit (Linux only) ---
if [ "$OS" = "Linux" ] && [ "$OPT_NO_SYSTEMD" = "0" ]; then
  if command -v systemctl >/dev/null 2>&1; then
    SYSTEMD_DIR="${HOME}/.config/systemd/user"
    SYSTEMD_UNIT="${SYSTEMD_DIR}/open-design.service"
    mkdir -p "$SYSTEMD_DIR"

    DOCKER_COMPOSE_CMD="$(command -v docker)"
    cat > "$SYSTEMD_UNIT" << UNIT
[Unit]
Description=Open Design daemon (Docker Compose)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${DEPLOY_DIR}
ExecStart=${DOCKER_COMPOSE_CMD} compose -f ${COMPOSE_FILE} up -d --no-build
ExecStop=${DOCKER_COMPOSE_CMD} compose -f ${COMPOSE_FILE} down
TimeoutStartSec=120

[Install]
WantedBy=default.target
UNIT

    systemctl --user daemon-reload
    systemctl --user enable open-design 2>/dev/null || true
    success "systemd unit installed: open-design.service"
    info "Manage with: systemctl --user start|stop|status open-design"
  else
    warn "systemd not found. Skipping service installation."
  fi
fi

# --- Summary ---
printf "\n"
printf "${BOLD}${GREEN}  -- Installation Complete (Docker) --${RESET}\n"
printf "\n"
printf "  Mode:         docker\n"
printf "  URL:          http://127.0.0.1:%s\n" "$PORT"
printf "  Image:        %s\n" "$IMAGE"
printf "  Data volume:  open_design_data\n"
printf "  Config:       %s\n" "$ENV_FILE"
if [ "$OS" = "Linux" ] && [ -f "${HOME}/.config/systemd/user/open-design.service" ]; then
  printf "  Service:      systemd (open-design.service)\n"
fi
printf "\n"
printf "  Next steps:\n"
printf "    Update:    %s/update.sh\n" "$SCRIPT_DIR"
printf "    Uninstall: %s/uninstall.sh\n" "$SCRIPT_DIR"
printf "    Logs:      docker compose -f %s logs -f\n" "$COMPOSE_FILE"
printf "\n"

# =========================================================================
# NODE MODE
# =========================================================================
else

# --- Node.js prerequisites ---
check_node() {
  if ! command -v node >/dev/null 2>&1; then return 1; fi
  _ver="$(node -e 'process.stdout.write(process.versions.node.split(".")[0])' 2>/dev/null || echo '0')"
  if [ "$_ver" -lt "$NODE_MIN_MAJOR" ]; then return 1; fi
  return 0
}

check_pnpm() {
  command -v pnpm >/dev/null 2>&1
}

check_git() {
  command -v git >/dev/null 2>&1
}

if ! check_node; then
  warn "Node.js >= ${NODE_MIN_MAJOR} is not installed."
  case "$DISTRO" in
    ubuntu|debian)
      node_install="sudo apt-get update && sudo apt-get install -y nodejs"
      info "Install with: ${node_install}"
      info "Or use fnm: curl -fsSL https://fnm.vercel.app/install | sh && fnm install --lts"
      ;;
    fedora)
      node_install="sudo dnf install -y nodejs"
      info "Install with: ${node_install}"
      ;;
    centos|rhel|rocky|alma)
      node_install="sudo yum install -y nodejs"
      info "Install with: ${node_install}"
      ;;
    macos)
      node_install="brew install node"
      info "Install with: ${node_install}"
      info "Or use fnm: brew install fnm && fnm install --lts"
      ;;
    *)
      info "Install Node.js: https://nodejs.org/"
      node_install=""
      ;;
  esac

  if [ "$NON_INTERACTIVE" = "0" ] && [ -n "$node_install" ]; then
    if prompt_confirm "Install Node.js now?" 0; then
      info "Running: ${node_install}"
      eval "$node_install"
    fi
  fi

  if ! check_node; then
    error "Node.js >= ${NODE_MIN_MAJOR} is required. Install it and re-run."
    exit 1
  fi
fi

NODE_VERSION="$(node --version 2>/dev/null)"
info "Node.js: ${NODE_VERSION}"

if ! check_pnpm; then
  warn "pnpm is not installed."
  if command -v corepack >/dev/null 2>&1; then
    info "Enabling pnpm via corepack..."
    corepack enable && corepack prepare pnpm@latest --activate 2>/dev/null || true
  fi
  if ! check_pnpm; then
    info "Installing pnpm via npm..."
    npm install -g pnpm 2>/dev/null || true
  fi
  if ! check_pnpm; then
    error "Could not install pnpm. Install it manually: npm install -g pnpm"
    exit 1
  fi
fi

PNPM_VERSION="$(pnpm --version 2>/dev/null)"
info "pnpm: ${PNPM_VERSION}"

if ! check_git; then
  warn "git is not installed."
  case "$DISTRO" in
    ubuntu|debian) git_install="sudo apt-get install -y git" ;;
    fedora) git_install="sudo dnf install -y git" ;;
    centos|rhel|rocky|alma) git_install="sudo yum install -y git" ;;
    macos) git_install="xcode-select --install" ;;
    *) git_install="" ;;
  esac

  if [ -n "$git_install" ]; then
    info "Install with: ${git_install}"
    if [ "$NON_INTERACTIVE" = "0" ]; then
      if prompt_confirm "Install git now?" 0; then
        eval "$git_install"
      fi
    fi
  fi

  if ! check_git; then
    error "git is required for Node.js mode. Install it and re-run."
    exit 1
  fi
fi

# --- Clone or update source ---
if [ -d "${NODE_SOURCE_DIR}/.git" ]; then
  info "Updating existing source at ${NODE_SOURCE_DIR}..."
  git -C "$NODE_SOURCE_DIR" pull --ff-only || {
    warn "git pull failed. Attempting fresh clone..."
    rm -rf "$NODE_SOURCE_DIR"
    info "Cloning ${REPO_URL}..."
    git clone "$REPO_URL" "$NODE_SOURCE_DIR"
  }
else
  info "Cloning ${REPO_URL}..."
  mkdir -p "$(dirname "$NODE_SOURCE_DIR")"
  git clone "$REPO_URL" "$NODE_SOURCE_DIR"
fi

# --- Build ---
info "Installing dependencies..."
cd "$NODE_SOURCE_DIR"
pnpm install --frozen-lockfile 2>/dev/null || pnpm install

info "Building daemon..."
pnpm --filter @open-design/daemon build

CLI_PATH="${NODE_SOURCE_DIR}/apps/daemon/dist/cli.js"

if [ ! -f "$CLI_PATH" ]; then
  error "Build failed: ${CLI_PATH} not found."
  exit 1
fi
success "Build complete."

# --- Generate .env ---
if [ -f "$ENV_FILE" ]; then
  BACKUP="${ENV_FILE}.$(date +%Y%m%d%H%M%S).bak"
  info "Existing .env found. Backing up to ${BACKUP}"
  cp "$ENV_FILE" "$BACKUP"
fi

cat > "$ENV_FILE" << ENVFILE
# Generated by install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
OPEN_DESIGN_INSTALL_MODE=node
OPEN_DESIGN_PORT=${PORT}
OPEN_DESIGN_SOURCE_DIR=${NODE_SOURCE_DIR}
ENVFILE

info "Written ${ENV_FILE}"

# --- Service registration ---
NODE_BIN="$(command -v node)"
SERVICE_NAME="open-design"

if [ "$OS" = "Linux" ] && [ "$OPT_NO_SYSTEMD" = "0" ]; then
  if command -v systemctl >/dev/null 2>&1; then
    SYSTEMD_DIR="${HOME}/.config/systemd/user"
    SYSTEMD_UNIT="${SYSTEMD_DIR}/${SERVICE_NAME}.service"
    mkdir -p "$SYSTEMD_DIR"

    cat > "$SYSTEMD_UNIT" << UNIT
[Unit]
Description=Open Design daemon (Node.js)
After=network.target

[Service]
Type=simple
WorkingDirectory=${NODE_SOURCE_DIR}
ExecStart=${NODE_BIN} ${CLI_PATH} --port ${PORT} --no-open
Restart=on-failure
RestartSec=5
Environment=OD_PORT=${PORT}
Environment=OD_DATA_DIR=${HOME}/.open-design/data

[Install]
WantedBy=default.target
UNIT

    systemctl --user daemon-reload
    systemctl --user enable "$SERVICE_NAME" 2>/dev/null || true
    systemctl --user start "$SERVICE_NAME" 2>/dev/null || true
    success "systemd unit installed: ${SERVICE_NAME}.service"
    info "Manage with: systemctl --user start|stop|status ${SERVICE_NAME}"
  else
    warn "systemd not found. Starting daemon directly..."
    OD_PORT="$PORT" OD_DATA_DIR="${HOME}/.open-design/data" "$NODE_BIN" "$CLI_PATH" --no-open &
    DAEMON_PID=$!
    info "Daemon started (PID: ${DAEMON_PID})"
  fi
elif [ "$OS" = "Darwin" ]; then
  PLIST_NAME="com.open-design.daemon"
  PLIST_PATH="${HOME}/Library/LaunchAgents/${PLIST_NAME}.plist"
  mkdir -p "$(dirname "$PLIST_PATH")"

  cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_NAME}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${NODE_BIN}</string>
    <string>${CLI_PATH}</string>
    <string>--port</string>
    <string>${PORT}</string>
    <string>--no-open</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${NODE_SOURCE_DIR}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>OD_PORT</key>
    <string>${PORT}</string>
    <key>OD_DATA_DIR</key>
    <string>${HOME}/.open-design/data</string>
    <key>PATH</key>
    <string>${PATH}:/usr/local/bin</string>
  </dict>
  <key>StandardOutPath</key>
  <string>${HOME}/.open-design/daemon.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/.open-design/daemon.error.log</string>
</dict>
</plist>
PLIST

  launchctl load "$PLIST_PATH" 2>/dev/null || true
  success "launchd plist installed: ${PLIST_NAME}"
  info "Manage with: launchctl unload|load ${PLIST_PATH}"
else
  warn "No service manager detected. Starting daemon directly..."
  OD_PORT="$PORT" OD_DATA_DIR="${HOME}/.open-design/data" "$NODE_BIN" "$CLI_PATH" --no-open &
  DAEMON_PID=$!
  info "Daemon started (PID: ${DAEMON_PID})"
fi

# --- Health check ---
info "Waiting for health check (up to ${HEALTH_TIMEOUT}s)..."
HEALTH_URL="http://127.0.0.1:${PORT}/api/health"
HEALTH_OK=0
ELAPSED=0

while [ "$ELAPSED" -lt "$HEALTH_TIMEOUT" ]; do
  HTTP_CODE="$(http_get_code "$HEALTH_URL")"
  if [ "$HTTP_CODE" = "200" ]; then
    HEALTH_OK=1
    break
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [ "$HEALTH_OK" = "1" ]; then
  success "Daemon is healthy (200 OK)"
else
  warn "Health check did not pass within ${HEALTH_TIMEOUT}s."
  info "Check logs at ${HOME}/.open-design/daemon.log"
fi

# --- Summary ---
printf "\n"
printf "${BOLD}${GREEN}  -- Installation Complete (Node.js) --${RESET}\n"
printf "\n"
printf "  Mode:         node\n"
printf "  URL:          http://127.0.0.1:%s\n" "$PORT"
printf "  Source:       %s\n" "$NODE_SOURCE_DIR"
printf "  Data:         %s/.open-design/data\n" "$HOME"
printf "  Config:       %s\n" "$ENV_FILE"
if [ "$OS" = "Linux" ] && [ -f "${HOME}/.config/systemd/user/${SERVICE_NAME}.service" ]; then
  printf "  Service:      systemd (${SERVICE_NAME}.service)\n"
elif [ "$OS" = "Darwin" ] && [ -f "${HOME}/Library/LaunchAgents/com.open-design.daemon.plist" ]; then
  printf "  Service:      launchd (com.open-design.daemon)\n"
fi
printf "\n"
printf "  Next steps:\n"
printf "    Update:    %s/update.sh\n" "$SCRIPT_DIR"
printf "    Uninstall: %s/uninstall.sh\n" "$SCRIPT_DIR"
printf "\n"

fi # end mode dispatch

# ---------------------------------------------------------------------------
# Launch setup wizard
# ---------------------------------------------------------------------------
if [ "${NON_INTERACTIVE:-0}" = "0" ] && command -v od >/dev/null 2>&1; then
  printf "${BOLD}[open-design]${RESET} Launching setup wizard...\n\n"
  OD_PORT="$PORT" od setup
elif [ "${NON_INTERACTIVE:-0}" = "0" ]; then
  printf "[open-design] Run 'od setup' to configure API keys, agents, and MCP servers.\n"
  printf "    Open http://127.0.0.1:%s in your browser\n\n" "$PORT"
else
  printf "    Open http://127.0.0.1:%s in your browser\n\n" "$PORT"
fi
