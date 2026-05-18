#!/bin/sh
# Open Design — Updater
# Reads OPEN_DESIGN_INSTALL_MODE from .env and updates accordingly
#
# Usage: ./update.sh [--image <ref>] [--non-interactive]
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="${DEPLOY_DIR}/docker-compose.yml"
ENV_FILE="${DEPLOY_DIR}/.env"
HEALTH_TIMEOUT=60

BOLD="" GREEN="" YELLOW="" RED="" RESET=""
if [ -t 1 ]; then
  BOLD="\033[1m" GREEN="\033[32m" YELLOW="\033[33m" RED="\033[31m" RESET="\033[0m"
fi

info()    { printf "${BOLD}[open-design]${RESET} %s\n" "$1"; }
warn()    { printf "${BOLD}${YELLOW}[open-design]${RESET} %s\n" "$1" >&2; }
error()   { printf "${BOLD}${RED}[open-design]${RESET} %s\n" "$1" >&2; }
success() { printf "${BOLD}${GREEN}[open-design]${RESET} %s\n" "$1"; }

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

OPT_IMAGE=""

for arg in "$@"; do
  case "$arg" in
    --image=*) OPT_IMAGE="${arg#--image=}" ;;
    --non-interactive) ;;
    --help|-h)
      echo "Usage: update.sh [options]"
      echo "  --image <ref>       Pull a specific image (Docker mode only)"
      echo "  --non-interactive   Skip confirmation prompts"
      exit 0
      ;;
  esac
done

printf "\n"
info "Updating Open Design..."

# --- Read .env ---
INSTALL_MODE=""
PORT=7456
SOURCE_DIR=""

if [ -f "$ENV_FILE" ]; then
  _mode="$(grep '^OPEN_DESIGN_INSTALL_MODE=' "$ENV_FILE" | cut -d= -f2)"
  if [ -n "$_mode" ]; then INSTALL_MODE="$_mode"; fi

  _port="$(grep '^OPEN_DESIGN_PORT=' "$ENV_FILE" | cut -d= -f2)"
  if [ -n "$_port" ]; then PORT="$_port"; fi

  _src="$(grep '^OPEN_DESIGN_SOURCE_DIR=' "$ENV_FILE" | cut -d= -f2)"
  if [ -n "$_src" ]; then SOURCE_DIR="$_src"; fi
fi

if [ -z "$INSTALL_MODE" ]; then
  # Fallback: detect from what exists
  if [ -f "$COMPOSE_FILE" ] && command -v docker >/dev/null 2>&1; then
    INSTALL_MODE="docker"
  else
    INSTALL_MODE="node"
  fi
  info "No install mode in .env. Detected: ${INSTALL_MODE}"
fi

info "Install mode: ${INSTALL_MODE}"

# --- Health check helper ---
HEALTH_URL="http://127.0.0.1:${PORT}/api/health"

wait_for_health() {
  info "Waiting for health check (up to ${HEALTH_TIMEOUT}s)..."
  _elapsed=0
  while [ "$_elapsed" -lt "$HEALTH_TIMEOUT" ]; do
    HTTP_CODE="$(http_get_code "$HEALTH_URL")"
    if [ "$HTTP_CODE" = "200" ]; then
      success "Daemon is healthy (200 OK)"
      return 0
    fi
    sleep 2
    _elapsed=$((_elapsed + 2))
  done
  warn "Health check did not pass within ${HEALTH_TIMEOUT}s."
  return 1
}

# =========================================================================
# DOCKER MODE
# =========================================================================
if [ "$INSTALL_MODE" = "docker" ]; then

  if [ -n "$OPT_IMAGE" ]; then
    export OPEN_DESIGN_IMAGE="$OPT_IMAGE"
  fi

  info "Pulling latest image..."
  docker compose -f "$COMPOSE_FILE" pull

  info "Restarting service..."
  docker compose -f "$COMPOSE_FILE" up -d --no-build

  wait_for_health || {
    info "Check logs: docker compose -f ${COMPOSE_FILE} logs"
  }

  info "Cleaning up old images..."
  docker image prune -f >/dev/null 2>&1 || true

# =========================================================================
# NODE MODE
# =========================================================================
elif [ "$INSTALL_MODE" = "node" ]; then

  if [ -z "$SOURCE_DIR" ]; then
    SOURCE_DIR="${HOME}/.open-design/source"
  fi

  if [ ! -d "${SOURCE_DIR}/.git" ]; then
    error "Source directory not found: ${SOURCE_DIR}"
    error "Re-run install.sh to set up Node.js mode."
    exit 1
  fi

  info "Pulling latest source..."
  git -C "$SOURCE_DIR" pull --ff-only || {
    warn "git pull failed. Attempting forced update..."
    git -C "$SOURCE_DIR" fetch origin
    git -C "$SOURCE_DIR" reset --hard origin/main
  }

  info "Installing dependencies..."
  cd "$SOURCE_DIR"
  pnpm install --frozen-lockfile 2>/dev/null || pnpm install

  info "Building daemon..."
  pnpm --filter @open-design/daemon build

  # Restart service
  if command -v systemctl >/dev/null 2>&1 && [ -f "${HOME}/.config/systemd/user/open-design.service" ]; then
    info "Restarting systemd service..."
    systemctl --user restart open-design
  elif [ -f "${HOME}/Library/LaunchAgents/com.open-design.daemon.plist" ]; then
    info "Restarting launchd service..."
    launchctl unload "${HOME}/Library/LaunchAgents/com.open-design.daemon.plist" 2>/dev/null || true
    launchctl load "${HOME}/Library/LaunchAgents/com.open-design.daemon.plist" 2>/dev/null || true
  else
    warn "No service manager found. Restart the daemon manually."
  fi

  wait_for_health || {
    info "Check logs at ${HOME}/.open-design/daemon.log"
  }

else
  error "Unknown install mode: ${INSTALL_MODE}"
  exit 1
fi

printf "\n"
success "Open Design updated successfully."
info "URL: http://127.0.0.1:${PORT}"
printf "\n"
