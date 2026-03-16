# Windows 11 Template Creation Guide

This guide walks you through creating a Windows 11 VM template on Proxmox. Once created, LabOps uses this template to clone lab VMs in seconds.

---

## What Is a Template?

A **template** is a pre-configured Windows 11 image that acts as a "golden master." When you run `make provision`, LabOps clones this template to create identical lab VMs. This means:

- Every lab VM starts with the same configuration
- Provisioning takes minutes instead of hours
- No manual Windows installation per VM

You create the template **once**, then clone it as many times as you need.

---

## Prerequisites

Before starting, make sure you have:

- Proxmox VE installed and accessible
- A Windows 11 ISO file (download from Microsoft)
- The VirtIO drivers ISO (download from https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/)
- Your `.env` file configured with Proxmox credentials

---

## Step 1: Upload ISOs to Proxmox

### Upload Windows 11 ISO

1. Open your Proxmox web UI (e.g., `https://192.168.1.2:8006`)
2. In the left panel, select your node, then click **local** under storage
3. Click the **ISO Images** tab
4. Click **Upload** and select your Windows 11 ISO file
5. Wait for the upload to complete
6. Note the exact filename (e.g., `Win11_23H2_English_x64.iso`)

### Upload VirtIO Drivers ISO

1. Download the VirtIO drivers ISO from:
   `https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso`
2. Upload it to Proxmox the same way (local storage, ISO Images tab)
3. Note the exact filename (e.g., `virtio-win.iso` or `virtio-win-0.1.240.iso`)

### Update Your .env

Add the ISO filenames to your `.env` file:

```bash
WIN11_ISO=Win11_23H2_English_x64.iso
VIRTIO_ISO=virtio-win.iso
```

---

## Step 2: Create the Template VM

From your LabOps project directory, run:

```bash
make create-template
```

This creates a VM on Proxmox with the right hardware configuration for Windows 11 (UEFI, TPM 2.0, VirtIO disk, etc.) and starts it. The VM boots from the Windows 11 ISO.

---

## Step 3: Install Windows 11

1. Open the Proxmox web UI
2. Find VM 100 (or your chosen template ID) in the left panel
3. Click **Console** to open the VM's display

### Installation Walkthrough

1. **Press any key** when prompted to boot from CD
2. Select your language and keyboard layout, click **Next**
3. Click **Install now**
4. Click **I don't have a product key** (or enter one if you have it)
5. Select **Windows 11 Pro**, click **Next**
6. Accept the license terms
7. Select **Custom: Install Windows only**

### Loading VirtIO Disk Drivers (Important!)

At the "Where do you want to install Windows?" screen, you'll see **no drives listed**. This is expected -- you need to load the VirtIO drivers:

1. Click **Load driver**
2. Click **Browse**
3. Navigate to the VirtIO CD drive (usually D: or E:)
4. Go to `vioscsi` > `w11` > `amd64`
5. Click **OK**
6. Select the **Red Hat VirtIO SCSI** driver, click **Next**
7. The 80 GB drive will now appear
8. Select it and click **Next**

### Complete the Installation

1. Windows will install and reboot (this takes 10-15 minutes)
2. After reboot, go through the Windows OOBE (Out of Box Experience):
   - Select your region and keyboard layout
   - **Network**: If prompted, click "I don't have internet" then "Continue with limited setup"
   - **Account**: Create a local account (any name/password -- Sysprep will reset this)
   - **Privacy settings**: Turn everything off, click **Accept**
3. Wait for the desktop to load

### Enable WinRM (Required for Finalization)

Once you're at the Windows desktop, open **PowerShell as Administrator** and run:

```powershell
# Enable WinRM for Ansible connectivity
winrm quickconfig -force
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
```

---

## Step 4: Finalize the Template

Back on your Mac, run:

```bash
make finalize-template
```

This runs an Ansible playbook that:
- Disables Windows Firewall
- Enables Remote Desktop
- Creates the demo user account
- Installs the QEMU Guest Agent
- Configures auto-login
- Adds a Windows Defender exclusion
- Runs Sysprep to generalize the image

**Sysprep will automatically shut down the VM**, and the script will convert it to a Proxmox template.

---

## Step 5: Verify the Template

1. Open the Proxmox web UI
2. VM 100 should now show a **template icon** (small document icon)
3. You cannot start a template directly -- it is a read-only golden image

---

## Step 6: Provision Lab VMs

You're ready to create lab VMs from your template:

```bash
make provision
```

This clones the template into a new VM (ID 200+), starts it, and configures it for your lab.

---

## Troubleshooting

### "No drives found" during Windows install
You need to load the VirtIO drivers. See "Loading VirtIO Disk Drivers" above.

### Windows asks for a Microsoft account
Disconnect the VM's network adapter in Proxmox before the OOBE, or use the "I don't have internet" option.

### WinRM connection fails during finalize
Make sure you ran the WinRM commands in PowerShell (Step 3). Also verify the VM's IP address is reachable from your Mac.

### Sysprep fails
If Sysprep fails, it usually means Windows Update is running. Wait for updates to finish, then try again. You can also check `C:\Windows\System32\Sysprep\Panther\setupact.log` for details.

### Template VM ID conflict
If VM 100 already exists, either delete it or set a different ID in `.env`:
```bash
TEMPLATE_VM_ID=105
```

---

## Summary

The complete template creation flow:

```
make install              # One-time: install tools and start LabOps
make create-template      # Create the template VM and boot Windows ISO
  ... install Windows ... # Manual: install Windows 11 in the Proxmox console
make finalize-template    # Automated: configure Windows + Sysprep + convert to template
make provision            # Clone the template into lab VMs
```

Once the template exists, you only need `make provision` to create new lab VMs.
