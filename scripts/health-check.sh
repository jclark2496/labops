#!/usr/bin/env bash
# LabOps Health Check Script
# Checks the health of all LabOps services and prints a summary table.

# Do NOT use set -e; we want to check all services even if some are down.

# --- Colors ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- State ---
ALL_HEALTHY=true

# --- Load .env if present ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
if [[ -f "$ENV_FILE" ]]; then
    # Export variables from .env, ignoring comments and blank lines
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

# --- Helpers ---
print_header() {
    echo ""
    echo -e "${BOLD}=========================================${NC}"
    echo -e "${BOLD}       LabOps Health Check${NC}"
    echo -e "${BOLD}=========================================${NC}"
    echo -e "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${BOLD}-----------------------------------------${NC}"
    printf "${BOLD}%-28s %-12s${NC}\n" "SERVICE" "STATUS"
    echo -e "${BOLD}-----------------------------------------${NC}"
}

print_row() {
    local name="$1"
    local status="$2"  # UP, DOWN, DEGRADED
    local color

    case "$status" in
        UP|HEALTHY)
            color="$GREEN"
            ;;
        DOWN)
            color="$RED"
            ALL_HEALTHY=false
            ;;
        DEGRADED|UNHEALTHY)
            color="$YELLOW"
            ALL_HEALTHY=false
            ;;
        *)
            color="$NC"
            ;;
    esac

    printf "  %-26s ${color}%-12s${NC}\n" "$name" "$status"
}

print_footer() {
    echo -e "${BOLD}-----------------------------------------${NC}"
    if $ALL_HEALTHY; then
        echo -e "  Overall: ${GREEN}ALL SERVICES HEALTHY${NC}"
    else
        echo -e "  Overall: ${RED}ONE OR MORE SERVICES DOWN${NC}"
    fi
    echo -e "${BOLD}=========================================${NC}"
    echo ""
}

# --- Check if a Docker container is running and healthy ---
check_container() {
    local container="$1"
    local display_name="${2:-$1}"

    # Check if container exists and is running
    local state
    state=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null) || state="not_found"

    if [[ "$state" != "running" ]]; then
        print_row "$display_name" "DOWN"
        return
    fi

    # Check health status if the container has a healthcheck defined
    local health
    health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container" 2>/dev/null) || health="none"

    case "$health" in
        healthy|none)
            print_row "$display_name" "UP"
            ;;
        unhealthy)
            print_row "$display_name" "UNHEALTHY"
            ;;
        starting)
            print_row "$display_name" "DEGRADED"
            ;;
        *)
            print_row "$display_name" "UP"
            ;;
    esac
}

# --- Check an HTTP endpoint ---
check_http() {
    local url="$1"
    local display_name="$2"
    local http_code

    http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null) || http_code="000"

    if [[ "$http_code" =~ ^2[0-9]{2}$ ]] || [[ "$http_code" =~ ^3[0-9]{2}$ ]]; then
        print_row "$display_name" "UP"
    else
        print_row "$display_name" "DOWN"
    fi
}

# ===========================
#  Main
# ===========================
print_header

# -- Docker Containers --
CONTAINERS=(
    "labops-nginx:Nginx"
    "labops-n8n:n8n"
    "labops-guacamole:Guacamole"
    "labops-guacd:Guacd"
    "labops-guac-postgres:Guac Postgres"
    "labops-portainer:Portainer"
)

for entry in "${CONTAINERS[@]}"; do
    container="${entry%%:*}"
    display="${entry#*:}"
    check_container "$container" "$display"
done

echo -e "${BOLD}-----------------------------------------${NC}"

# -- HTTP Endpoints --
check_http "http://localhost:8080/health" "Nginx HTTP"
check_http "http://localhost:8085/guacamole" "Guacamole HTTP"
check_http "http://localhost:5678" "n8n HTTP"

# -- Proxmox (optional) --
if [[ -n "${PROXMOX_URL:-}" ]]; then
    # Strip trailing slash if present, hit the API version endpoint
    PROXMOX_API="${PROXMOX_URL%/}/api2/json/version"
    http_code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$PROXMOX_API" 2>/dev/null) || http_code="000"
    if [[ "$http_code" =~ ^[23][0-9]{2}$ ]]; then
        print_row "Proxmox API" "UP"
    else
        print_row "Proxmox API" "DOWN"
    fi
fi

print_footer

# --- Exit code ---
if $ALL_HEALTHY; then
    exit 0
else
    exit 1
fi
