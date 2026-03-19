#!/bin/bash
# proxmox/finalize-template.sh
# Finalizes a Windows 11 VM as a Proxmox template.
#
# This script:
#   1. Verifies the template VM exists and is running
#   2. Gets the VM's IP address
#   3. Runs the finalize-template.yml Ansible playbook (disables firewall, creates
#      demo user, installs QEMU agent, runs Sysprep)
#   4. Waits for Sysprep to shut down the VM
#   5. Converts the VM to a Proxmox template
#
# Usage:
#   ./finalize-template.sh [TEMPLATE_VM_ID]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ANSIBLE_DIR="$SCRIPT_DIR/ansible"

# Load .env if it exists
[ -f "$PROJECT_DIR/.env" ] && set -a && source "$PROJECT_DIR/.env" && set +a

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${CYAN}[LABOPS]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Configuration ────────────────────────────────────────────────────────────

TEMPLATE_ID="${1:-${TEMPLATE_VM_ID:-100}}"

[ -n "$PROXMOX_URL" ]          || err "PROXMOX_URL not set. Configure your .env file."
[ -n "$PROXMOX_NODE" ]         || err "PROXMOX_NODE not set. Configure your .env file."
[ -n "$PROXMOX_TOKEN_ID" ]     || err "PROXMOX_TOKEN_ID not set. Configure your .env file."
[ -n "$PROXMOX_TOKEN_SECRET" ] || err "PROXMOX_TOKEN_SECRET not set. Configure your .env file."

API_BASE="${PROXMOX_URL}/api2/json"
AUTH_HEADER="PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}"

# Helper: make an API call
api() {
  local method=$1 endpoint=$2
  shift 2
  curl -sk -X "$method" \
    -H "Authorization: ${AUTH_HEADER}" \
    "${API_BASE}${endpoint}" \
    "$@"
}

# ── 1. Verify the template VM exists and is running ──────────────────────────

log "Checking VM ${TEMPLATE_ID} status..."
VM_STATUS=$(api GET "/nodes/${PROXMOX_NODE}/qemu/${TEMPLATE_ID}/status/current" 2>/dev/null)

if echo "$VM_STATUS" | grep -q '"errors"'; then
  err "VM ${TEMPLATE_ID} does not exist. Run 'make create-template' first."
fi

STATUS=$(echo "$VM_STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['status'])" 2>/dev/null || echo "unknown")

if [ "$STATUS" != "running" ]; then
  err "VM ${TEMPLATE_ID} is not running (status: ${STATUS}). Start it and finish Windows installation first."
fi

ok "VM ${TEMPLATE_ID} is running."

# ── 2. Get the VM's IP address ───────────────────────────────────────────────

log "Getting VM IP address..."

get_vm_ip() {
  local vmid=$1
  local proxmox_ip
  proxmox_ip=$(echo "$PROXMOX_URL" | sed 's|https\?://||' | sed 's|:.*||')
  local max_wait=120
  local waited=0

  while [ $waited -lt $max_wait ]; do
    # Try QEMU Guest Agent first (via API)
    local agent_resp
    agent_resp=$(api POST "/nodes/${PROXMOX_NODE}/qemu/${vmid}/agent/network-get-interfaces" 2>/dev/null || true)
    local ip
    ip=$(echo "$agent_resp" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)['data']['result']
    for iface in data:
        for addr in iface.get('ip-addresses', []):
            ip = addr.get('ip-address', '')
            if ip.startswith('192.168.') or ip.startswith('10.') or ip.startswith('172.'):
                print(ip)
                sys.exit(0)
except:
    pass
" 2>/dev/null || true)

    if [ -n "$ip" ]; then
      echo "$ip"
      return 0
    fi

    # Fallback: try SSH to Proxmox host
    ip=$(ssh -q -o ConnectTimeout=5 root@"$proxmox_ip" "qm guest exec $vmid -- ipconfig 2>/dev/null" 2>/dev/null | \
      grep -oE '192\.168\.[0-9]+\.[0-9]+|10\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)

    if [ -n "$ip" ] && [ "$ip" != "$proxmox_ip" ]; then
      echo "$ip"
      return 0
    fi

    sleep 5
    waited=$((waited + 5))
    echo -n "." >&2
  done

  echo "" >&2
  return 1
}

VM_IP=$(get_vm_ip "$TEMPLATE_ID") || true

if [ -z "$VM_IP" ]; then
  warn "Could not auto-detect VM IP. The QEMU Guest Agent may not be installed yet."
  echo ""
  read -p "Enter the VM IP address manually: " VM_IP
  [ -n "$VM_IP" ] || err "No IP address provided."
fi

ok "VM IP: ${VM_IP}"

# ── 3. Create temporary Ansible inventory ────────────────────────────────────

TEMP_INVENTORY=$(mktemp /tmp/labops-inventory.XXXXXX.ini)
trap "rm -f $TEMP_INVENTORY" EXIT

cat > "$TEMP_INVENTORY" <<EOF
[template]
${VM_IP}

[template:vars]
ansible_user=${LAB_VM_USER:-Administrator}
ansible_password=${LAB_VM_PASSWORD:-Demo1234!}
ansible_connection=winrm
ansible_port=5985
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
EOF

log "Temporary inventory created for ${VM_IP}"

# ── 4. Run the finalize-template playbook ────────────────────────────────────

log "Running Ansible finalize-template playbook..."
log "This will configure the VM and run Sysprep."
echo ""

cd "$ANSIBLE_DIR"
ansible-playbook -i "$TEMP_INVENTORY" finalize-template.yml -v

echo ""
ok "Ansible playbook completed."

# ── 5. Wait for VM to shut down (Sysprep does this) ─────────────────────────

log "Waiting for VM ${TEMPLATE_ID} to shut down after Sysprep..."
MAX_WAIT=600
WAITED=0

while [ $WAITED -lt $MAX_WAIT ]; do
  STATUS=$(api GET "/nodes/${PROXMOX_NODE}/qemu/${TEMPLATE_ID}/status/current" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['data']['status'])" 2>/dev/null || echo "unknown")

  if [ "$STATUS" = "stopped" ]; then
    ok "VM ${TEMPLATE_ID} has shut down."
    break
  fi

  if [ $WAITED -ge $MAX_WAIT ]; then
    err "VM did not shut down within ${MAX_WAIT}s. Check Sysprep status in the Proxmox console."
  fi

  sleep 10
  WAITED=$((WAITED + 10))
  echo -n "."
done
echo ""

# ── 6. Convert VM to template ───────────────────────────────────────────────

log "Converting VM ${TEMPLATE_ID} to a template..."
RESPONSE=$(api POST "/nodes/${PROXMOX_NODE}/qemu/${TEMPLATE_ID}/template" 2>&1)

if echo "$RESPONSE" | grep -q '"errors"'; then
  echo "$RESPONSE"
  err "Failed to convert VM to template."
fi

ok "VM ${TEMPLATE_ID} is now a Proxmox template."

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}=========================================="
echo "  Template ${TEMPLATE_ID} is ready!"
echo -e "==========================================${NC}"
echo ""
echo "  You can now provision lab VMs from this template:"
echo "    make provision"
echo ""
echo "  The template is locked and cannot be started directly."
echo "  Lab VMs will be full clones (IDs 200+)."
echo ""
