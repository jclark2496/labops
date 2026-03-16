terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.50"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_url
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure  = true # Self-signed cert on Proxmox — expected
}

# ─── Windows 11 Lab Workstation ─────────────────────────────────────────────

resource "proxmox_virtual_environment_vm" "lab_win11" {
  count     = var.win11_count
  node_name = var.proxmox_node
  vm_id     = 200 + count.index
  name      = "lab-win11-${count.index + 1}"

  clone {
    vm_id = var.win11_template_id
    full  = true
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192 # 8GB
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    file_format  = "raw"
    size         = 80
  }

  operating_system {
    type = "win11"
  }

  started = true
  tags    = ["lab-vm", "windows11"]
}

# ─── Windows 11 Unmanaged Workstation ───────────────────────────────────────

resource "proxmox_virtual_environment_vm" "lab_win11_unmanaged" {
  node_name = var.proxmox_node
  vm_id     = 201
  name      = "lab-win11-unmanaged"

  clone {
    vm_id = var.unmanaged_template_id
    full  = true
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  # No disk block — sata0 disk is inherited from the template clone

  operating_system {
    type = "win11"
  }

  started = true
  tags    = ["lab-vm", "windows11", "unmanaged"]
}

# ─── Windows Server ─────────────────────────────────────────────────────────

resource "proxmox_virtual_environment_vm" "lab_winserver" {
  count     = var.winserver_count
  node_name = var.proxmox_node
  vm_id     = 210 + count.index
  name      = "lab-winserver-${count.index + 1}"

  clone {
    vm_id = var.winserver_template_id
    full  = true
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192 # 8GB
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    file_format  = "raw"
    size         = 80
  }

  operating_system {
    type = "win11" # closest type for Server 2022
  }

  started = true
  tags    = ["lab-vm", "windows-server"]
}

# ─── Outputs ────────────────────────────────────────────────────────────────

output "win11_vm_ids" {
  value       = proxmox_virtual_environment_vm.lab_win11[*].vm_id
  description = "VM IDs for Windows 11 lab workstations"
}

output "unmanaged_vm_id" {
  value       = proxmox_virtual_environment_vm.lab_win11_unmanaged.vm_id
  description = "VM ID for the unmanaged Windows 11 workstation"
}

output "winserver_vm_ids" {
  value       = proxmox_virtual_environment_vm.lab_winserver[*].vm_id
  description = "VM IDs for Windows Server lab machines"
}
