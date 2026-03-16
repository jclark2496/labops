#!/bin/bash
# proxmox/create-template.sh
# Creates a Proxmox VM ready for Windows 11 installation via the Proxmox REST API.
#
# Usage:
#   ./create-template.sh [TEMPLATE_VM_ID]
#
# Prerequisites:
#   - .env configured with PROXMOX_URL, PROXMOX_NODE, PROXMOX_TOKEN_ID, PROXMOX_TOKEN_SECRET
#   - WIN11_ISO set in .env (name of the Windows 11 ISO on Proxmox storage)
#   - VirtIO drivers ISO uploaded to Proxmox (VIRTIO_ISO in .env, default: virtio-win.iso)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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
VM_NAME="win11-template"
WIN11_ISO="${WIN11_ISO:?WIN11_ISO is not set in .env. Set it to the name of your Windows 11 ISO (e.g., Win11_23H2_English_x64.iso)}"
VIRTIO_ISO="${VIRTIO_ISO:-virtio-win.iso}"

# ── Validate prerequisites ──────────────────────────────────────────────────

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

# ── Check if VM already exists ───────────────────────────────────────────────

log "Checking if VM ${TEMPLATE_ID} already exists..."
EXISTING=$(api GET "/nodes/${PROXMOX_NODE}/qemu/${TEMPLATE_ID}/status/current" 2>/dev/null | grep -c '"status"' || true)
if [ "$EXISTING" -gt 0 ]; then
  err "VM ${TEMPLATE_ID} already exists. Delete it first or choose a different ID."
fi

# ── Create the VM ────────────────────────────────────────────────────────────

log "Creating VM ${TEMPLATE_ID} (${VM_NAME})..."
log "  CPU: 4 vCPU (host type)"
log "  RAM: 8192 MB"
log "  Disk: 80 GB (VirtIO SCSI on local-lvm)"
log "  BIOS: UEFI/OVMF with EFI disk"
log "  TPM: 2.0 (required for Windows 11)"
log "  Network: VirtIO on vmbr0"
log "  CD-ROM 1: ${WIN11_ISO}"
log "  CD-ROM 2: ${VIRTIO_ISO}"

RESPONSE=$(api POST "/nodes/${PROXMOX_NODE}/qemu" \
  -d "vmid=${TEMPLATE_ID}" \
  -d "name=${VM_NAME}" \
  -d "ostype=win11" \
  -d "machine=pc-q35-8.1" \
  -d "cpu=host" \
  -d "cores=4" \
  -d "memory=8192" \
  -d "bios=ovmf" \
  -d "efidisk0=local-lvm:1,efitype=4m,pre-enrolled-keys=1" \
  -d "tpmstate0=local-lvm:1,version=v2.0" \
  -d "scsihw=virtio-scsi-single" \
  -d "scsi0=local-lvm:80,iothread=1" \
  -d "ide0=local:iso/${WIN11_ISO},media=cdrom" \
  -d "ide2=local:iso/${VIRTIO_ISO},media=cdrom" \
  -d "net0=virtio,bridge=vmbr0" \
  -d "boot=order=ide0;scsi0" \
  -d "onboot=0" \
  -d "agent=1" \
  2>&1)

# Check for errors
if echo "$RESPONSE" | grep -q '"errors"'; then
  echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
  err "Failed to create VM. See error above."
fi

ok "VM ${TEMPLATE_ID} created."

# ── Start the VM ─────────────────────────────────────────────────────────────

log "Starting VM ${TEMPLATE_ID}..."
api POST "/nodes/${PROXMOX_NODE}/qemu/${TEMPLATE_ID}/status/start" >/dev/null 2>&1
ok "VM ${TEMPLATE_ID} started."

# ── Print next steps ─────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}=========================================="
echo "  Template VM ${TEMPLATE_ID} created and started."
echo -e "==========================================${NC}"
echo ""
echo "  Next steps:"
echo "    1. Open Proxmox UI: ${PROXMOX_URL}"
echo "    2. Open the console for VM ${TEMPLATE_ID}"
echo "    3. Install Windows 11 (select VirtIO drivers when prompted for disk)"
echo "    4. After Windows desktop loads, run: make finalize-template"
echo ""
