#!/bin/bash
# proxmox/provision.sh
# One-command lab VM provisioning for LabOps
#
# Usage:
#   ./provision.sh windows-client     # Spin up Windows 11 lab VM
#   ./provision.sh windows-server     # Spin up Windows Server lab VM
#   ./provision.sh status             # Show all running lab VMs
#   ./provision.sh teardown           # Destroy all lab VMs (keeps templates)
#
# Prerequisites:
#   - Terraform installed: brew install terraform
#   - Ansible installed: brew install ansible
#   - pywinrm installed: pip3 install pywinrm
#   - .env file configured with Proxmox credentials

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"
ANSIBLE_DIR="$SCRIPT_DIR/ansible"

# Load .env if it exists
[ -f "$PROJECT_DIR/.env" ] && set -a && source "$PROJECT_DIR/.env" && set +a

# Export Terraform vars from .env
export TF_VAR_proxmox_url="${PROXMOX_URL:-}"
export TF_VAR_proxmox_node="${PROXMOX_NODE:-}"
export TF_VAR_proxmox_token_id="${PROXMOX_TOKEN_ID:-}"
export TF_VAR_proxmox_token_secret="${PROXMOX_TOKEN_SECRET:-}"

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

check_prereqs() {
  command -v terraform >/dev/null 2>&1 || err "terraform not installed. Run: brew install terraform"
  command -v ansible-playbook >/dev/null 2>&1 || err "ansible not installed. Run: brew install ansible"
  [ -n "$PROXMOX_URL" ] || err "PROXMOX_URL not set. Configure your .env file."
  [ -n "$PROXMOX_TOKEN_SECRET" ] || err "PROXMOX_TOKEN_SECRET not set. Configure your .env file."
}

get_proxmox_ip() {
  echo "$PROXMOX_URL" | sed 's|https\?://||' | sed 's|:.*||'
}

get_vm_ip() {
  local vmid=$1
  local proxmox_ip=$(get_proxmox_ip)
  local max_wait=120
  local waited=0
  log "Waiting for VM $vmid to get an IP address..."
  while [ $waited -lt $max_wait ]; do
    local ip=$(ssh -q root@$proxmox_ip "qm guest exec $vmid -- ipconfig 2>/dev/null" 2>/dev/null | \
      grep -oP '192\.168\.\d+\.\d+' | head -1)
    if [ -n "$ip" ] && [ "$ip" != "$proxmox_ip" ]; then
      echo "$ip"
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
    echo -n "."
  done
  echo ""
  warn "Could not auto-detect VM IP after ${max_wait}s. Check your router's DHCP table."
  echo "unknown"
}

cmd_windows_client() {
  log "Provisioning Windows 11 lab workstation..."
  check_prereqs

  cd "$TERRAFORM_DIR"
  [ -f terraform.tfvars ] || err "terraform.tfvars not found. Copy terraform.tfvars.example and fill in values."

  log "Running Terraform..."
  terraform init -upgrade -input=false
  terraform apply -auto-approve -var="win11_count=1" -var="winserver_count=0"

  log "Waiting 60s for VM to boot..."
  sleep 60

  local vmid=200
  local vm_ip=$(get_vm_ip $vmid)
  echo ""

  if [ "$vm_ip" != "unknown" ]; then
    ok "VM is up at $vm_ip"
    ok "  VM ID:    200"
    ok "  IP:       $vm_ip"
    ok "  RDP:      Connect via LabOps dashboard or: mstsc /v:$vm_ip"
    echo ""
    log "To configure the VM with Ansible, update inventory.ini and run:"
    echo "  cd $ANSIBLE_DIR && ansible-playbook -i inventory.ini setup-vm.yml --limit win11_vms"
  else
    warn "VM started but IP unknown. Manual steps:"
    warn "  1. Check your router DHCP table for a new Windows device"
    warn "  2. Update proxmox/ansible/inventory.ini with the IP"
    warn "  3. Run: cd proxmox/ansible && ansible-playbook -i inventory.ini setup-vm.yml"
  fi
}

cmd_windows_server() {
  log "Provisioning Windows Server lab VM..."
  check_prereqs

  cd "$TERRAFORM_DIR"
  terraform init -upgrade -input=false
  terraform apply -auto-approve -var="win11_count=0" -var="winserver_count=1"

  log "Waiting 60s for VM to boot..."
  sleep 60

  ok "Windows Server provisioned. Check Proxmox UI for status."
  ok "VM ID: 210"
}

cmd_status() {
  check_prereqs
  local proxmox_ip=$(get_proxmox_ip)
  log "Lab VM status on Proxmox ($proxmox_ip):"
  echo ""
  ssh root@$proxmox_ip "qm list" | awk 'NR==1 || ($1 >= 200)'
  echo ""
}

cmd_teardown() {
  warn "This will DESTROY all lab VMs (IDs 200-299). Templates are safe."
  read -p "Are you sure? (yes/no): " confirm
  [ "$confirm" = "yes" ] || { log "Cancelled."; exit 0; }

  log "Destroying lab VMs via Terraform..."
  cd "$TERRAFORM_DIR"
  terraform destroy -auto-approve

  ok "All lab VMs destroyed. Templates are intact."
}

# ─── Main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
  windows-client)  cmd_windows_client ;;
  windows-server)  cmd_windows_server ;;
  status)          cmd_status ;;
  teardown)        cmd_teardown ;;
  *)
    echo "Usage: $0 {windows-client|windows-server|status|teardown}"
    echo ""
    echo "  windows-client   Spin up Windows 11 lab VM (VM 200)"
    echo "  windows-server   Spin up Windows Server lab VM (VM 210)"
    echo "  status           Show all running lab VMs"
    echo "  teardown         Destroy all lab VMs (keeps templates)"
    exit 1
    ;;
esac
