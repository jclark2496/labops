# LabOps — Engineering Reference

> **For AI assistants and engineers:** This document is the technical reference for the LabOps codebase. Read it before making changes.

---

## 1. Project Purpose

LabOps is a **standalone, product-agnostic automated lab manager** for Sales Engineers. It provisions and manages Windows VMs on a Proxmox hypervisor, provides browser-based RDP access via Apache Guacamole, and exposes a web dashboard for monitoring and control.

**Key constraints:**
- Must install with a single `make install` command
- No product-specific branding (no vendor names, no "MDR")
- All secrets via `.env` (gitignored) — no hardcoded credentials
- Target audience: 200+ SEs with varying technical backgrounds
- Can be extended by layering additional projects on the `labops-net` Docker network

---

## 2. Architecture

```
Docker Host (labops-net: 172.20.0.0/24)
├── labops-nginx         172.20.0.50  :8080→80     Dashboard + reverse proxy
├── labops-n8n           172.20.0.30  :5678         Lab management API
├── labops-guacamole     172.20.0.81  :8085→8080    Browser RDP (amd64/Rosetta)
├── labops-guacd         172.20.0.80                Protocol daemon (amd64/Rosetta)
├── labops-guac-postgres 172.20.0.82                Guacamole DB (arm64)
└── labops-portainer     172.20.0.60  :9000         Container management

Proxmox Server (user-configured IP)
├── VM Templates (100-199)  — golden images
└── Lab VMs (200-299)       — cloned via Terraform
```

### Nginx Proxy Routes

| Path | Backend | Purpose |
|---|---|---|
| `/` | static files | Dashboard (index.html) |
| `/api/` | `172.20.0.30:5678/webhook/` | n8n webhook endpoints |
| `/guacamole/` | `172.20.0.81:8080/guacamole/` | Guacamole + WebSocket tunnel |
| `/health` | nginx | Simple health check |

---

## 3. Key Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | All 6 service definitions, networks, volumes |
| `Makefile` | Operational interface: install, up, down, provision, health |
| `.env.example` | Environment template — all variables documented |
| `nginx/html/index.html` | Dashboard SPA (single HTML file, inline CSS/JS) |
| `nginx/conf/default.conf` | Nginx proxy routes (Guacamole WebSocket, n8n API) |
| `n8n/workflows/vm_management.json` | VM CRUD API via Proxmox REST |
| `n8n/workflows/container_health.json` | Container status + config API |
| `guacamole/init/01-initdb.sql` | Guacamole PostgreSQL schema (auto-runs on first start) |
| `proxmox/create-template.sh` | Creates Windows 11 template VM via Proxmox REST API |
| `proxmox/finalize-template.sh` | Finalizes template: Ansible config + Sysprep + convert to template |
| `proxmox/ansible/finalize-template.yml` | Ansible playbook: configure Windows, install QEMU agent, Sysprep |
| `proxmox/TEMPLATE-GUIDE.md` | Step-by-step template creation guide for SEs |
| `proxmox/terraform/main.tf` | VM provisioning (lab-win11, lab-win11-unmanaged, lab-winserver) |
| `proxmox/ansible/setup-vm.yml` | VM config: disable firewall, enable RDP, create demo user |
| `proxmox/provision.sh` | Terraform + Ansible wrapper script |
| `scripts/health-check.sh` | CLI health check for all services + Proxmox |

---

## 4. API Endpoints (n8n webhooks)

All endpoints are proxied through nginx at `/api/`.

| Endpoint | Method | What it does |
|---|---|---|
| `/api/vms` | GET | List VMs 200-299 from Proxmox API |
| `/api/vms/:vmid/start` | POST | Start a VM |
| `/api/vms/:vmid/stop` | POST | Graceful shutdown |
| `/api/vms/:vmid/destroy` | DELETE | Destroy a VM |
| `/api/containers` | GET | Docker container status (via `docker ps`) |
| `/api/health` | GET | Aggregate health check |
| `/api/config` | GET | Dashboard config from env vars (Guac creds, Proxmox URL) |

**n8n requirement:** `NODE_FUNCTION_ALLOW_BUILTIN=fs,path,child_process` must be set in `docker-compose.yml` for Code nodes to run shell commands. This is already configured.

---

## 5. Guacamole RDP Connection Flow

The dashboard creates dynamic RDP connections via the Guacamole REST API. This pattern (from `index.html`):

1. `POST /guacamole/api/tokens` with admin credentials → get `authToken`
2. `POST /guacamole/api/session/data/postgresql/connections?token=...` with RDP parameters → get `connection.identifier`
3. Build client URL: `btoa(connId + '\0c\0postgresql')` → open in new tab

Guacamole credentials come from `/api/config` (which reads `.env` vars via n8n), not hardcoded in HTML.

---

## 6. Critical Gotchas

### Guacamole and guacd are amd64-only
Both run via Docker's Rosetta 2 on Apple Silicon. They're tagged `platform: linux/amd64` in docker-compose.yml. They work fine but take longer to start (~30s).

### n8n workflows are auto-imported during install
The `_import-workflows` Makefile target imports and activates workflows via the n8n REST API during `make install`. The `n8n-data` volume preserves state across restarts, so re-import is only needed after `make clean`.

### Guacamole connection records accumulate
Every `connectRDP()` call creates a new connection in the PostgreSQL database. They accumulate over time. Clean manually:
```bash
docker exec labops-guac-postgres psql -U guacamole -d guacamole_db -c "DELETE FROM guacamole_connection;"
```

### Proxmox uses self-signed certs
All HTTP requests to Proxmox use `allowUnauthorizedCerts: true` (n8n) or `-k` (curl). This is expected.

### Docker Compose V2
The Makefile uses `docker compose` (no hyphen — Compose V2 plugin). Both forms work with current Docker Desktop.

---

## 7. Environment Variables

All from `.env` (gitignored). See `.env.example` for documentation.

| Variable | Required | Used by |
|---|---|---|
| `N8N_PASSWORD` | Yes | n8n admin login |
| `PROXMOX_URL` | For VM mgmt | n8n workflows, provision.sh |
| `PROXMOX_NODE` | For VM mgmt | n8n workflows, provision.sh |
| `PROXMOX_TOKEN_ID` | For VM mgmt | n8n workflows, Terraform |
| `PROXMOX_TOKEN_SECRET` | For VM mgmt | n8n workflows, Terraform |
| `WIN11_ISO` | For template | create-template.sh |
| `VIRTIO_ISO` | No (default: virtio-win.iso) | create-template.sh |
| `TEMPLATE_VM_ID` | No (default: 100) | create-template.sh, finalize-template.sh |
| `GUAC_ADMIN_USER` | No (default: guacadmin) | Dashboard RDP connect |
| `GUAC_ADMIN_PASSWORD` | No (default: guacadmin) | Dashboard RDP connect |
| `LAB_VM_USER` | No (default: demo) | Dashboard RDP connect, Ansible |
| `LAB_VM_PASSWORD` | For RDP | Dashboard RDP connect, Ansible |

---

## 8. Makefile Targets

| Target | What it does |
|---|---|
| `make install` | Checks Docker, creates .env, starts stack, waits for healthy, prints URLs |
| `make up/down/restart` | Standard Docker Compose lifecycle |
| `make status` | `docker compose ps` |
| `make logs` | `docker compose logs -f` |
| `make create-template` | Creates Windows 11 template VM via Proxmox API |
| `make finalize-template` | Runs Ansible finalization + Sysprep + converts VM to template |
| `make provision` | Runs `proxmox/provision.sh windows-client` |
| `make teardown` | Runs `proxmox/provision.sh teardown` |
| `make health` | Runs `scripts/health-check.sh` |
| `make clean` | Confirmation prompt → `docker compose down -v` (destructive) |

---

## 9. Network

The `labops-net` Docker bridge network (172.20.0.0/24) is created by this project. Other projects (e.g., attack simulation) can join by declaring:

```yaml
networks:
  labops-net:
    external: true
```

IP assignments are static in docker-compose.yml. Do not change them without updating nginx proxy routes.

---

## 10. Terraform Resources

| Resource | VM IDs | Template Default | Description |
|---|---|---|---|
| `lab_win11` | 200+ | Template 100 | Windows 11 workstation |
| `lab_win11_unmanaged` | 201 | Template 102 | Windows 11 (no security software) |
| `lab_winserver` | 210+ | Template 101 | Windows Server |

Terraform state is stored locally in `proxmox/terraform/` (gitignored).

---

*Last updated: 2026-03-16*
