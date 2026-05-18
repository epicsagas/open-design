#!/bin/sh
# Open Design — Updater
# Pulls the latest image and restarts the service
#
# Usage: ./update.sh [--image <ref>] [--non-interactive]
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="${DEPLOY_DIR}/docker-compose.yml"
HEALTH_TIMEOUT=60

BOLD="" GREEN="" YELLOW="" RESET=""
if [ -t 1 ]; then
  BOLD="\033[1m" GREEN="\033[32m" YELLOW="\033[33m" RESET="\033[0m"
fi

info()    { printf "${BOLD}[open-design]${RESET} %s\n" "$1"; }
warn()    { printf "${BOLD}${YELLOW}[open-design]${RESET} %s\n" "$1" >&2; }
success() { printf "${BOLD}${GREEN}[open-design]${RESET} %s\n" "$1"; }

OPT_IMAGE=""
NON_INTERACTIVE=0

for arg in "$@"; do
  case "$arg" in
    --image=*) OPT_IMAGE="${arg#--image=}" ;;
    --non-interactive) NON_INTERACTIVE=1 ;;
    --help|-h)
      echo "Usage: update.sh [options]"
      echo "  --image <ref>       Pull a specific image instead of latest"
      echo "  --non-interactive   Skip confirmation prompts"
      exit 0
      ;;
  esac
done

printf "\n"
info "Updating Open Design..."

# Read current port from .env if it exists
PORT=7456
ENV_FILE="${DEPLOY_DIR}/.env"
if [ -f "$ENV_FILE" ]; then
  _port="$(grep '^OPEN_DESIGN_PORT=' "$ENV_FILE" | cut -d= -f2)"
  if [ -n "$_port" ]; then PORT="$_port"; fi
fi

# Override image if specified
if [ -n "$OPT_IMAGE" ]; then
  export OPEN_DESIGN_IMAGE="$OPT_IMAGE"
fi

# Pull latest image
info "Pulling latest image..."
docker compose -f "$COMPOSE_FILE" pull

# Restart with new image
info "Restarting service..."
docker compose -f "$COMPOSE_FILE" up -d --no-build

# Health check
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
  success "Update complete. Daemon is healthy."
else
  warn "Health check did not pass. Check logs: docker compose -f ${COMPOSE_FILE} logs"
fi

# Clean up dangling images
info "Cleaning up old images..."
docker image prune -f >/dev/null 2>&1 || true

printf "\n"
success "Open Design updated successfully."
info "URL: http://127.0.0.1:${PORT}"
printf "\n"
