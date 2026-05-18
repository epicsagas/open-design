#!/bin/sh
# Open Design — Uninstaller
# Reads OPEN_DESIGN_INSTALL_MODE from .env and uninstalls accordingly
# Data is PRESERVED by default. Use --delete-data to remove it.
#
# Usage: ./uninstall.sh [--delete-data] [--non-interactive]
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${DEPLOY_DIR}/.env"
COMPOSE_FILE="${DEPLOY_DIR}/docker-compose.yml"

BOLD="" RED="" GREEN="" YELLOW="" RESET=""
if [ -t 1 ]; then
  BOLD="\033[1m" RED="\033[31m" GREEN="\033[32m" YELLOW="\033[33m" RESET="\033[0m"
fi

info()    { printf "${BOLD}[open-design]${RESET} %s\n" "$1"; }
warn()    { printf "${BOLD}${YELLOW}[open-design]${RESET} %s\n" "$1" >&2; }
error()   { printf "${BOLD}${RED}[open-design]${RESET} %s\n" "$1" >&2; }
success() { printf "${BOLD}${GREEN}[open-design]${RESET} %s\n" "$1"; }

DELETE_DATA=0

for arg in "$@"; do
  case "$arg" in
    --delete-data)    DELETE_DATA=1 ;;
    --keep-data)      ;; # accepted for backward compat, now the default
    --non-interactive) ;;
    --help|-h)
      echo "Usage: uninstall.sh [options]"
      echo "  --delete-data       Delete data (projects, artifacts, config)"
      echo "                      Data is PRESERVED by default"
      echo "  --non-interactive   Skip confirmation prompts"
      exit 0
      ;;
  esac
done

printf "\n"
printf "${BOLD}${RED}  -- Open Design Uninstaller --${RESET}\n"
printf "\n"

if [ "$DELETE_DATA" = "1" ]; then
  warn "WARNING: --delete-data specified. All data (projects, artifacts, config) will be deleted."
else
  warn "This will stop Open Design and remove its service configuration."
  info "Data will be preserved. Use --delete-data to also remove data."
fi
printf "Continue? [y/N]: "
read -r _confirm
case "$_confirm" in
  [Yy]*) ;;
  *) info "Cancelled."; exit 0 ;;
esac

# --- Read .env ---
INSTALL_MODE=""
SOURCE_DIR=""

if [ -f "$ENV_FILE" ]; then
  _mode="$(grep '^OPEN_DESIGN_INSTALL_MODE=' "$ENV_FILE" | cut -d= -f2)"
  if [ -n "$_mode" ]; then INSTALL_MODE="$_mode"; fi

  _src="$(grep '^OPEN_DESIGN_SOURCE_DIR=' "$ENV_FILE" | cut -d= -f2)"
  if [ -n "$_src" ]; then SOURCE_DIR="$_src"; fi
fi

if [ -z "$INSTALL_MODE" ]; then
  if [ -f "$COMPOSE_FILE" ] && command -v docker >/dev/null 2>&1; then
    INSTALL_MODE="docker"
  else
    INSTALL_MODE="node"
  fi
fi

info "Install mode: ${INSTALL_MODE}"

# =========================================================================
# DOCKER MODE
# =========================================================================
if [ "$INSTALL_MODE" = "docker" ]; then

  if docker compose -f "$COMPOSE_FILE" ps -q 2>/dev/null | grep -q .; then
    info "Stopping containers..."
    docker compose -f "$COMPOSE_FILE" down
    success "Containers stopped."
  else
    info "No running containers found."
  fi

  if [ "$DELETE_DATA" = "1" ]; then
    info "Removing Docker volume..."
    docker volume rm open_design_data 2>/dev/null || true
  fi

# =========================================================================
# NODE MODE
# =========================================================================
elif [ "$INSTALL_MODE" = "node" ]; then

  if [ -z "$SOURCE_DIR" ]; then
    SOURCE_DIR="${HOME}/.open-design/source"
  fi

  if command -v systemctl >/dev/null 2>&1 && [ -f "${HOME}/.config/systemd/user/open-design.service" ]; then
    info "Stopping systemd service..."
    systemctl --user disable --now open-design 2>/dev/null || true
    rm -f "${HOME}/.config/systemd/user/open-design.service"
    systemctl --user daemon-reload
    success "systemd unit removed."
  elif [ -f "${HOME}/Library/LaunchAgents/com.open-design.daemon.plist" ]; then
    info "Stopping launchd service..."
    launchctl unload "${HOME}/Library/LaunchAgents/com.open-design.daemon.plist" 2>/dev/null || true
    rm -f "${HOME}/Library/LaunchAgents/com.open-design.daemon.plist"
    success "launchd plist removed."
  else
    info "No service file found."
  fi

  if [ -d "$SOURCE_DIR" ]; then
    info "Removing source: ${SOURCE_DIR}..."
    rm -rf "$SOURCE_DIR"
  fi

  if [ "$DELETE_DATA" = "1" ]; then
    DATA_DIR="${HOME}/.open-design/data"
    if [ -d "$DATA_DIR" ]; then
      info "Removing data: ${DATA_DIR}..."
      rm -rf "$DATA_DIR"
    fi
    LOG_FILE="${HOME}/.open-design/daemon.log"
    ERR_LOG="${HOME}/.open-design/daemon.error.log"
    rm -f "$LOG_FILE" "$ERR_LOG" 2>/dev/null || true
  fi

  # Remove .open-design dir if empty
  if [ -d "${HOME}/.open-design" ] && [ -z "$(ls -A "${HOME}/.open-design" 2>/dev/null)" ]; then
    rmdir "${HOME}/.open-design" 2>/dev/null || true
  fi

else
  error "Unknown install mode: ${INSTALL_MODE}"
  exit 1
fi

# --- Remove .env (common) ---
if [ -f "$ENV_FILE" ]; then
  info "Removing ${ENV_FILE}..."
  rm -f "$ENV_FILE"
fi

printf "\n"
success "Open Design has been uninstalled."
if [ "$DELETE_DATA" = "0" ]; then
  info "Data was preserved."
  if [ "$INSTALL_MODE" = "docker" ]; then
    info "Remove Docker volume manually: docker volume rm open_design_data"
  else
    info "Remove data manually: rm -rf ${HOME}/.open-design/data"
  fi
fi
printf "\n"
