variable "proxmox_url" {
  description = "Proxmox API URL (e.g. https://192.168.1.2:8006)"
  type        = string
}

variable "proxmox_node" {
  description = "Proxmox node name (verify with: pvesh get /nodes)"
  type        = string
}

variable "proxmox_token_id" {
  description = "Proxmox API token ID (format: user@realm!tokenname)"
  type        = string
}

variable "proxmox_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "win11_template_id" {
  description = "VM ID of the Windows 11 template to clone from"
  type        = number
  default     = 100
}

variable "unmanaged_template_id" {
  description = "VM ID of the unmanaged Windows 11 template (no security software)"
  type        = number
  default     = 102
}

variable "winserver_template_id" {
  description = "VM ID of the Windows Server template to clone from"
  type        = number
  default     = 101
}

variable "win11_count" {
  description = "Number of Windows 11 lab VMs to create"
  type        = number
  default     = 1
}

variable "winserver_count" {
  description = "Number of Windows Server lab VMs to create"
  type        = number
  default     = 0
}
