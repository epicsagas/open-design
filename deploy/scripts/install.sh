#!/bin/sh
# Open Design — One-Click Installer
# Docker Compose wrapper for Linux and macOS
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/nexu-io/open-design/main/deploy/scripts/install.sh | sh
#   ./install.sh [--non-interactive] [--port 7456] [--image <ref>] [--skip-docker-install] [--no-systemd]
set -eu

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DEFAULT_PORT=7456
DEFAULT_IMAGE="docker.io/vanjayak/open-design:latest"
DEFAULT_MEM_LIMIT="384m"
HEALTH_TIMEOUT=60
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${DEPLOY_DIR}/.env"
COMPOSE_FILE="${DEPLOY_DIR}/docker-compose.yml"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
BOLD="" RED="" GREEN="" YELLOW="" RESET=""
if [ -t 1 ]; then
  BOLD="\033[1m" RED="\033[31m" GREEN="\033[32m" YELLOW="\033[33m" RESET="\033[0m"
fi

info()  { printf "${BOLD}[open-design]${RESET} %s\n" "$1"; }
warn()  { printf "${BOLD}${YELLOW}[open-design]${RESET} %s\n" "$1" >&2; }
error() { printf "${BOLD}${RED}[open-design]${RESET} %s\n" "$1" >&2; }
success() { printf "${BOLD}${GREEN}[open-design]${RESET} %s\n" "$1"; }

prompt_text() {
  _label="$1" _default="$2"
  if [ "$NON_INTERACTIVE" = "1" ]; then
    eval "$_label=\$_default"
    return
  fi
  printf "%s [%s]: " "$_label" "$_default" >&2
  read -r _val
  eval "$_label=\${_val:-\$_default}"
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

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
NON_INTERACTIVE=0
OPT_PORT=""
OPT_IMAGE=""
OPT_SKIP_DOCKER=0
OPT_NO_SYSTEMD=0

for arg in "$@"; do
  case "$arg" in
    --non-interactive) NON_INTERACTIVE=1 ;;
    --port=*) OPT_PORT="${arg#--port=}" ;;
    --image=*) OPT_IMAGE="${arg#--image=}" ;;
    --skip-docker-install) OPT_SKIP_DOCKER=1 ;;
    --no-systemd) OPT_NO_SYSTEMD=1 ;;
    --help|-h)
      echo "Usage: install.sh [options]"
      echo ""
      echo "Options:"
      echo "  --non-interactive       Use defaults for all prompts"
      echo "  --port <n>              Host port (default: ${DEFAULT_PORT})"
      echo "  --image <ref>           Docker image reference"
      echo "  --skip-docker-install   Do not attempt to install Docker"
      echo "  --no-systemd            Skip systemd unit creation"
      echo "  --help                  Show this help"
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
printf "${BOLD}  ╔══════════════════════════════════════╗${RESET}\n"
printf "${BOLD}  ║     O P E N   D E S I G N           ║${RESET}\n"
printf "${BOLD}  ║     One-Click Installer              ║${RESET}\n"
printf "${BOLD}  ╚══════════════════════════════════════╝${RESET}\n"
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
# 2. Docker prerequisite check
# ---------------------------------------------------------------------------
check_docker() {
  if command -v docker >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

check_docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    return 0
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

check_docker_running() {
  if docker info >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

if ! check_docker; then
  if [ "$OPT_SKIP_DOCKER" = "1" ]; then
    error "Docker is not installed and --skip-docker-install was set."
    exit 1
  fi

  warn "Docker is not installed."

  case "$DISTRO" in
    ubuntu|debian)
      install_cmd="sudo apt-get update && sudo apt-get install -y docker.io docker-compose-plugin"
      info "Install with: ${install_cmd}"
      ;;
    fedora)
      install_cmd="sudo dnf install -y docker docker-compose-plugin"
      info "Install with: ${install_cmd}"
      ;;
    centos|rhel|rocky|alma)
      install_cmd="sudo yum install -y docker docker-compose-plugin"
      info "Install with: ${install_cmd}"
      ;;
    macos)
      install_cmd="brew install --cask docker"
      info "Install with: ${install_cmd}"
      info "Or download from: https://www.docker.com/products/docker-desktop/"
      ;;
    *)
      error "Cannot auto-detect Docker install method for: ${DISTRO}"
      info "Install Docker manually: https://docs.docker.com/get-docker/"
      exit 1
      ;;
  esac

  if [ "$NON_INTERACTIVE" = "0" ]; then
    if prompt_confirm "Install Docker now?" 0; then
      info "Running: ${install_cmd}"
      eval "$install_cmd"
    else
      error "Docker is required. Install it and re-run this script."
      exit 1
    fi
  else
    error "Docker is required in non-interactive mode. Install it first."
    exit 1
  fi
fi

if ! check_docker_compose; then
  error "Docker Compose is not available."
  info "Install the compose plugin: https://docs.docker.com/compose/install/"
  exit 1
fi

if ! check_docker_running; then
  warn "Docker daemon is not running."
  case "$DISTRO" in
    ubuntu|debian|fedora|centos|rhel|rocky|alma)
      info "Start with: sudo systemctl start docker"
      ;;
    macos)
      info "Open Docker Desktop from your Applications folder."
      ;;
  esac
  if [ "$NON_INTERACTIVE" = "0" ]; then
    if prompt_confirm "Retry after starting Docker?" 1; then
      if ! check_docker_running; then
        error "Docker is still not running. Start it and re-run."
        exit 1
      fi
    else
      exit 1
    fi
  else
    exit 1
  fi
fi

DOCKER_VERSION="$(docker --version 2>/dev/null || echo 'unknown')"
COMPOSE_VERSION="$(docker compose version 2>/dev/null || echo 'unknown')"
info "Docker: ${DOCKER_VERSION}"
info "Compose: ${COMPOSE_VERSION}"

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
      prompt_text "Enter a different port" "$DEFAULT_PORT"
      PORT="$_val"
    else
      error "Port ${PORT} is occupied. Use --port to specify a different one."
      exit 1
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 4. Interactive prompts
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 5. Generate .env
# ---------------------------------------------------------------------------
if [ -f "$ENV_FILE" ]; then
  BACKUP="${ENV_FILE}.$(date +%Y%m%d%H%M%S).bak"
  info "Existing .env found. Backing up to ${BACKUP}"
  cp "$ENV_FILE" "$BACKUP"
fi

cat > "$ENV_FILE" << ENVFILE
# Generated by install.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
OPEN_DESIGN_IMAGE=${IMAGE}
OPEN_DESIGN_PORT=${PORT}
OPEN_DESIGN_ALLOWED_ORIGINS=${ALLOWED_ORIGINS}
OPEN_DESIGN_MEM_LIMIT=${MEM_LIMIT}
NODE_OPTIONS=--max-old-space-size=192
ENVFILE

info "Written ${ENV_FILE}"

# ---------------------------------------------------------------------------
# 6. Pull and start
# ---------------------------------------------------------------------------
info "Pulling image: ${IMAGE}"
docker compose -f "$COMPOSE_FILE" pull

info "Starting Open Design..."
docker compose -f "$COMPOSE_FILE" up -d --no-build

# ---------------------------------------------------------------------------
# 7. Health check
# ---------------------------------------------------------------------------
info "Waiting for health check (up to ${HEALTH_TIMEOUT}s)..."

HEALTH_URL="http://127.0.0.1:${PORT}/api/health"
HEALTH_OK=0
ELAPSED=0

while [ "$ELAPSED" -lt "$HEALTH_TIMEOUT" ]; do
  if command -v curl >/dev/null 2>&1; then
    HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' "$HEALTH_URL" 2>/dev/null || echo '000')"
  elif command -v wget >/dev/null 2>&1; then
    HTTP_CODE="$(wget -q -O /dev/null --server-response "$HEALTH_URL" 2>&1 | grep 'HTTP/' | tail -1 | awk '{print $2}')"
  else
    HTTP_CODE="000"
  fi

  if [ "$HTTP_CODE" = "200" ]; then
    HEALTH_OK=1
    break
  fi

  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [ "$HEALTH_OK" = "1" ]; then
  success "Daemon is healthy (${HTTP_CODE} OK)"
else
  warn "Health check did not pass within ${HEALTH_TIMEOUT}s."
  info "Check status: docker compose -f ${COMPOSE_FILE} logs"
fi

# ---------------------------------------------------------------------------
# 8. systemd unit (Linux only)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 9. Summary
# ---------------------------------------------------------------------------
printf "\n"
printf "${BOLD}${GREEN}  ── Installation Complete ──────────────────────────${RESET}\n"
printf "\n"
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

# ---------------------------------------------------------------------------
# 10. Launch setup wizard
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
