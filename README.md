# LabOps — Automated Lab Manager

One-command setup for a fully automated lab environment with Proxmox VM management, browser-based RDP, and a real-time dashboard.

```
git clone https://github.com/jclark2496/labops.git
cd labops
make install
```

---

## What You Get

- **Lab Manager Dashboard** — Web UI to monitor containers, manage VMs, and connect via RDP
- **Proxmox VM Provisioning** — Terraform + Ansible automation for Windows lab VMs
- **Browser-Based RDP** — Apache Guacamole for in-browser remote desktop (no RDP client needed)
- **Lightweight API Server** — Node.js server powering the dashboard API
- **Container Management** — Portainer CE for Docker visibility

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Your Machine (Docker Host)                                  │
│  Docker bridge network: labops-net (172.20.0.0/24)          │
│                                                              │
│  labops-nginx       172.20.0.50  :8080                       │
│    Dashboard UI + reverse proxy                              │
│                                                              │
│  labops-api         172.20.0.30  :3000(int)                   │
│    LabOps API server (VM CRUD, health checks)                │
│                                                              │
│  labops-guacamole   172.20.0.81  :8085  (amd64/Rosetta)     │
│  labops-guacd       172.20.0.80         (amd64/Rosetta)      │
│  labops-guac-postgres 172.20.0.82       (arm64 native)       │
│    In-browser RDP to lab VMs                                 │
│                                                              │
│  labops-portainer   172.20.0.60  :9000                       │
│    Container management dashboard                            │
└──────────────────────┬──────────────────────────────────────┘
                       │ LAN
┌──────────────────────▼──────────────────────────────────────┐
│  Proxmox Server (Hypervisor)                                 │
│                                                              │
│  VM Templates (100-199) — golden images you create           │
│  Lab VMs (200-299) — cloned from templates via Terraform     │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

| Requirement | Auto-installed? | Notes |
|---|---|---|
| **Docker** | Yes | Docker Desktop (macOS) or Docker Engine (Linux) |
| **Terraform** | Yes | For VM provisioning |
| **Ansible** | Yes | For VM configuration |
| **Python packages** | Yes | pywinrm, requests |
| **Proxmox VE** | No | Your hypervisor with Windows VM templates |
| **Proxmox API Token** | No | Create in Datacenter → Permissions → API Tokens |

`make install` automatically installs all tools marked "Yes" on macOS and Linux — you don't need to install anything manually except Proxmox setup.

### Windows (WSL 2)

On Windows, run everything inside WSL 2 (Windows Subsystem for Linux):

**One-time setup (PowerShell as Administrator):**
```powershell
wsl --install        # Installs WSL 2 + Ubuntu (reboot when prompted)
```

Then install [Docker Desktop for Windows](https://docs.docker.com/desktop/install/windows-install/) and enable **WSL 2 backend** + **Ubuntu integration** in Settings → Resources → WSL Integration.

**Install (Ubuntu terminal):**
```bash
git clone https://github.com/jclark2496/labops.git
cd labops
./setup-wsl.sh       # Installs make/pip3, verifies Docker, runs make install
```

All `localhost` URLs (e.g., `http://localhost:8080`) work from your Windows browser.

## Quick Start

### 1. Clone and Install

```bash
git clone https://github.com/jclark2496/labops.git
cd labops
make install
```

This will:
1. Install Docker, Terraform, Ansible, and Python packages (if not present)
2. Create `.env` and auto-generate passwords
3. Start all 6 containers
4. Wait for services to be healthy
5. Print service URLs

If Docker Desktop was just installed, you'll be prompted to open it first, then re-run `make install`.

### 2. Configure Your Environment

Edit `.env` with your values:

```bash
# Required for VM management
PROXMOX_URL=https://<your-proxmox-ip>:8006
PROXMOX_NODE=<your-node-name>
PROXMOX_TOKEN_ID=<user@realm!tokenname>
PROXMOX_TOKEN_SECRET=<your-token-secret>

# Required for RDP connect
LAB_VM_USER=demo
LAB_VM_PASSWORD=<your-vm-password>
```

### 3. Open the Dashboard

Navigate to `http://localhost:8080` to access the LabOps Control Center.

## Template Setup

Before you can provision lab VMs, you need a Windows 11 template on Proxmox. This is a one-time setup:

```bash
make install                # Install tools and start LabOps
# Edit .env with your Proxmox credentials and ISO filenames
make create-template        # Create the template VM and boot Windows ISO
```

Install Windows 11 in the Proxmox console (see `proxmox/TEMPLATE-GUIDE.md` for a full walkthrough), then:

```bash
make finalize-template      # Configure Windows, Sysprep, convert to template
make provision              # Clone the template into lab VMs
```

After the template exists, you only need `make provision` to create new lab VMs.

## Service URLs

| Service | URL | Purpose |
|---|---|---|
| **Dashboard** | `http://localhost:8080` | Lab Manager Control Center |
| **Guacamole** | `http://localhost:8085/guacamole` | Browser-Based RDP |
| **Portainer** | `http://localhost:9000` | Container Management |

## Make Targets

| Command | Description |
|---|---|
| `make install` | Full first-time setup |
| `make up` | Start all containers |
| `make down` | Stop all containers |
| `make restart` | Restart all containers |
| `make status` | Show container health |
| `make logs` | Tail all container logs |
| `make create-template` | Create a Windows 11 template VM on Proxmox |
| `make finalize-template` | Finalize template (Sysprep + convert to template) |
| `make provision` | Provision a Windows 11 lab VM |
| `make teardown` | Destroy all lab VMs (keeps templates) |
| `make health` | Run full health check |
| `make clean` | Remove all containers and volumes (destructive) |

## VM Provisioning

After the Docker stack is running, provision lab VMs on your Proxmox server:

### Setup Terraform

```bash
cd proxmox/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Proxmox credentials
```

### Provision VMs

```bash
make provision          # Provisions a Windows 11 lab VM
# or
./proxmox/provision.sh windows-client    # Same thing
./proxmox/provision.sh windows-server    # Windows Server VM
./proxmox/provision.sh status            # Check VM status
./proxmox/provision.sh teardown          # Destroy all lab VMs
```

### Configure VMs with Ansible

After a VM boots, update `proxmox/ansible/inventory.ini` with its IP, then:

```bash
cd proxmox/ansible
ansible-playbook -i inventory.ini setup-vm.yml
```

This will:
- Disable Windows Firewall (lab environment only)
- Enable RDP
- Create a demo user account
- Configure WinRM for future Ansible runs

## Dashboard Features

The LabOps Control Center at `http://localhost:8080` provides:

- **VM Management** — View all lab VMs with real-time status from Proxmox. Start, stop, or destroy VMs with one click.
- **Connect RDP** — Opens a browser-based RDP session to any running VM via Guacamole. No RDP client needed.
- **Provision New VM** — Select a template and spin up a new VM directly from the dashboard.
- **Container Health** — Real-time status of all Docker services with color-coded indicators.
- **Quick Links** — Direct links to Guacamole, Portainer, and Proxmox consoles.

## API Server

LabOps uses a lightweight Node.js API server (`api/server.js`) as its backend. It starts automatically with `make install` -- no workflow imports or activation needed.

| Endpoint | What it does |
|----------|-------------|
| `/api/vms` | Powers the Virtual Machines panel. Queries the Proxmox API to list VMs (IDs 200-299). |
| `/api/vms/:id/start`, `stop`, `destroy` | Start, stop, or destroy a VM via Proxmox. |
| `/api/containers` | Powers the Services panel. Queries the Docker socket for real-time container status. |
| `/api/health` | Aggregate health check endpoint. |
| `/api/config` | Dashboard configuration (Guacamole credentials, Proxmox URL, port mappings) from `.env`. |

> **Note:** The LabOps API server replaces n8n for this repo. No workflow imports or activation needed. n8n is still used by the adversary-sim and mdr-demo-lab repos for AI scenario generation.

## Troubleshooting

### Docker containers won't start
```bash
make status    # Check what's running
make logs      # Check logs for errors
```

### Guacamole shows "connection refused"
On Apple Silicon Macs, Guacamole and guacd are amd64 images running via Rosetta emulation and take longer to start (~30s). On Linux x86-64, they run natively. Wait and retry.

### Can't reach Proxmox API
- Verify `PROXMOX_URL` in `.env` points to your Proxmox server
- Ensure the API token has `PVEVMAdmin + PVEDatastoreAdmin + PVESDNUser` permissions
- Proxmox uses a self-signed cert — this is expected and handled

### Dashboard shows "Cannot reach Proxmox API"
- Verify the labops-api container is running (`make status`)
- Check that `PROXMOX_*` variables are set in `.env`
- The LabOps API server replaces n8n for this repo. No workflow imports or activation needed.

### VM provisioning fails
- Verify `terraform.tfvars` exists in `proxmox/terraform/` (auto-generated from `.env` on `make install`)
- Ensure the template VM IDs in `terraform.tfvars` match your Proxmox setup

**Optional: SSH key for Proxmox** — Some provisioning commands can use SSH for faster VM interaction. Set up key-based auth: `ssh-copy-id root@<your-proxmox-ip>`. Not required — the REST API is used by default.

## Optional: Add Attack Simulation

LabOps is a standalone lab manager. If you also need attack simulation capabilities (CALDERA, Kali, attack scenarios), you can layer the attack simulation project on top:

1. LabOps creates the `labops-net` Docker network
2. The attack sim project declares this network as `external: true`
3. Attack sim containers join the same network and can interact with lab VMs

See the attack simulation project's README for setup instructions.

## Project Structure

```
labops/
├── README.md                    # This file
├── CLAUDE.md                    # Technical reference for AI assistants
├── Makefile                     # make install, up, down, provision, health
├── .env.example                 # Environment template (copy to .env)
├── .gitignore                   # Blocks .env, terraform secrets
├── docker-compose.yml           # Services: nginx, api, guacamole stack, portainer
├── api/
│   ├── server.js                # LabOps API server (VM CRUD, health, config)
│   └── Dockerfile               # Dockerfile for labops-api container
├── nginx/
│   ├── conf/default.conf        # Reverse proxy: /, /guacamole/, /api/
│   └── html/
│       ├── index.html           # Lab Manager Dashboard (SPA)
│       ├── settings.html        # Platform settings — update check, adversary-sim detection/redirect
│       └── shared.css           # Shared design system — Orbitron wordmark, colors, components
├── guacamole/
│   └── init/
│       └── 01-initdb.sql        # Guacamole PostgreSQL schema
├── proxmox/
│   ├── create-template.sh       # Create Windows 11 template VM via API
│   ├── finalize-template.sh     # Finalize template (Ansible + Sysprep + convert)
│   ├── provision.sh             # VM provisioning wrapper
│   ├── TEMPLATE-GUIDE.md        # Step-by-step template creation guide
│   ├── terraform/
│   │   ├── main.tf              # VM resource definitions
│   │   ├── variables.tf         # Input variables
│   │   └── terraform.tfvars.example
│   └── ansible/
│       ├── inventory.ini        # VM host inventory
│       ├── setup-vm.yml         # VM configuration playbook
│       └── finalize-template.yml # Template finalization playbook
└── scripts/
    └── health-check.sh          # CLI health check for all services
```

## License

MIT
