#!/bin/sh
# Open Design — Uninstaller
# Stops and removes the Docker Compose deployment
#
# Usage: ./uninstall.sh [--keep-data] [--non-interactive]
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
success() { printf "${BOLD}${GREEN}[open-design]${RESET} %s\n" "$1"; }

NON_INTERACTIVE=0
KEEP_DATA=0

for arg in "$@"; do
  case "$arg" in
    --non-interactive) NON_INTERACTIVE=1 ;;
    --keep-data)       KEEP_DATA=1 ;;
    --help|-h)
      echo "Usage: uninstall.sh [options]"
      echo "  --keep-data         Preserve the open_design_data volume"
      echo "  --non-interactive   Skip confirmation prompts"
      exit 0
      ;;
  esac
done

printf "\n"
printf "${BOLD}${RED}  ── Open Design Uninstaller ─────────────────────────${RESET}\n"
printf "\n"

if [ "$NON_INTERACTIVE" = "0" ]; then
  if [ "$KEEP_DATA" = "0" ]; then
    warn "This will stop Open Design and DELETE all data (projects, artifacts, config)."
  else
    warn "This will stop Open Design. Data volume will be preserved."
  fi
  printf "Continue? [y/N]: "
  read -r _confirm
  case "$_confirm" in
    [Yy]*) ;;
    *) info "Cancelled."; exit 0 ;;
  esac
fi

# Stop and remove containers
if docker compose -f "$COMPOSE_FILE" ps -q 2>/dev/null | grep -q .; then
  info "Stopping containers..."
  if [ "$KEEP_DATA" = "1" ]; then
    docker compose -f "$COMPOSE_FILE" down
  else
    docker compose -f "$COMPOSE_FILE" down -v
  fi
  success "Containers stopped."
else
  info "No running containers found."
fi

# Remove systemd unit (Linux)
SYSTEMD_UNIT="${HOME}/.config/systemd/user/open-design.service"
if [ -f "$SYSTEMD_UNIT" ]; then
  info "Removing systemd unit..."
  systemctl --user disable --now open-design 2>/dev/null || true
  rm -f "$SYSTEMD_UNIT"
  systemctl --user daemon-reload
  success "systemd unit removed."
fi

# Remove .env
if [ -f "$ENV_FILE" ]; then
  info "Removing ${ENV_FILE}..."
  rm -f "$ENV_FILE"
fi

printf "\n"
success "Open Design has been uninstalled."
if [ "$KEEP_DATA" = "1" ]; then
  info "Data volume 'open_design_data' was preserved."
  info "Remove it manually: docker volume rm open_design_data"
fi
printf "\n"
