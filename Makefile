# =============================================================================
# LabOps — Automated Lab Manager Makefile
# Docker Compose-based training environment for 200+ SEs
#
# Usage:
#   make install     → full first-time setup (run this once — installs everything)
#   make up          → start the stack
#   make down        → stop the stack
#   make restart     → restart all containers
#   make status      → show container health
#   make logs        → tail all logs
#   make create-template → create Windows 11 template VM
#   make finalize-template → finalize template (Sysprep + convert)
#   make provision   → provision lab VMs
#   make teardown    → tear down lab VMs
#   make health      → run health check
#   make clean       → stop stack and remove all volumes (destructive!)
# =============================================================================

COMPOSE = docker compose

.DEFAULT_GOAL := help

# ── Help ──────────────────────────────────────────────────────────────────────

.PHONY: help
help:
	@echo ""
	@echo "  LabOps — Make targets"
	@echo ""
	@echo "  make install      Full first-time setup (installs all dependencies)"
	@echo "  make up           Start all containers"
	@echo "  make down         Stop all containers"
	@echo "  make restart      Restart all containers"
	@echo "  make status       Show container health"
	@echo "  make logs         Tail all container logs"
	@echo "  make create-template   Create Windows 11 template VM"
	@echo "  make finalize-template Finalize template (Sysprep + convert)"
	@echo "  make provision    Provision lab VMs (windows-client)"
	@echo "  make teardown     Tear down lab VMs"
	@echo "  make health       Run health check"
	@echo "  make clean        Remove all containers and volumes (destructive)"
	@echo ""

# ── Install (first-time) ────────────────────────────────────────────────────

.PHONY: install
install: _install-deps _check-docker _env _generate-config _up _wait-healthy _import-workflows
	@echo ""
	@echo "  _          _      ___"
	@echo " | |    __ _| |__  / _ \ _ __  ___"
	@echo " | |   / _\` | '_ \| | | | '_ \/ __|"
	@echo " | |__| (_| | |_) | |_| | |_) \__ \\"
	@echo " |_____\__,_|_.__/ \___/| .__/|___/"
	@echo "                        |_|"
	@echo ""
	@echo "=========================================="
	@echo "  LabOps — Ready"
	@echo "=========================================="
	@echo ""
	@echo "  Dashboard:      http://localhost:8080"
	@echo "  n8n:            http://localhost:5678"
	@echo "  Guacamole:      http://localhost:8085/guacamole"
	@echo "  Portainer:      http://localhost:9000"
	@echo ""
	@echo "  Next steps:"
	@echo "    1. Open http://localhost:8080 in your browser"
	@echo "    2. Edit .env with your Proxmox credentials"
	@echo "    3. Run 'make provision' to spin up lab VMs"
	@echo ""

# ── Core stack operations ─────────────────────────────────────────────────────

.PHONY: up
up:
	@echo "▶ Starting LabOps stack..."
	$(COMPOSE) up -d
	@echo "✅ Stack started — run 'make status' to check health"

.PHONY: down
down:
	@echo "■ Stopping LabOps stack..."
	$(COMPOSE) down
	@echo "✅ Stack stopped"

.PHONY: restart
restart:
	@echo "▶ Restarting LabOps stack..."
	$(COMPOSE) restart

.PHONY: status
status:
	$(COMPOSE) ps

.PHONY: logs
logs:
	$(COMPOSE) logs -f

# ── Template Creation ─────────────────────────────────────────────────────────

.PHONY: create-template
create-template:
	@echo "▶ Creating Windows 11 template VM..."
	@bash proxmox/create-template.sh

.PHONY: finalize-template
finalize-template:
	@echo "▶ Finalizing Windows 11 template..."
	@bash proxmox/finalize-template.sh

# ── Provisioning ──────────────────────────────────────────────────────────────

.PHONY: provision
provision:
	@echo "▶ Provisioning lab VMs..."
	@bash proxmox/provision.sh windows-client

.PHONY: teardown
teardown:
	@echo "▶ Tearing down lab VMs..."
	@bash proxmox/provision.sh teardown

# ── Health ────────────────────────────────────────────────────────────────────

.PHONY: health
health:
	@bash scripts/health-check.sh

# ── Dependency Installation ─────────────────────────────────────────────────

.PHONY: _install-deps
_install-deps:
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════╗"
	@echo "║  LabOps — Installing Dependencies                       ║"
	@echo "╚══════════════════════════════════════════════════════════╝"
	@echo ""
	@# ── Homebrew ──
	@if command -v brew >/dev/null 2>&1; then \
		echo "✅ Homebrew is installed"; \
	else \
		echo "▶ Installing Homebrew..."; \
		/bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; \
		echo "✅ Homebrew installed"; \
	fi
	@# ── Docker Desktop ──
	@if command -v docker >/dev/null 2>&1; then \
		echo "✅ Docker is installed"; \
	else \
		echo "▶ Installing Docker Desktop (this may take a few minutes)..."; \
		brew install --cask docker; \
		echo "✅ Docker Desktop installed"; \
		echo ""; \
		echo "⚠️  Docker Desktop needs to be started manually the first time."; \
		echo "   Please open Docker Desktop from your Applications folder,"; \
		echo "   wait for it to finish starting, then run 'make install' again."; \
		echo ""; \
		exit 1; \
	fi
	@# ── Terraform ──
	@if command -v terraform >/dev/null 2>&1; then \
		echo "✅ Terraform is installed"; \
	else \
		echo "▶ Installing Terraform..."; \
		brew install terraform; \
		echo "✅ Terraform installed"; \
	fi
	@# ── Ansible ──
	@if command -v ansible-playbook >/dev/null 2>&1; then \
		echo "✅ Ansible is installed"; \
	else \
		echo "▶ Installing Ansible..."; \
		brew install ansible; \
		echo "✅ Ansible installed"; \
	fi
	@# ── Python packages ──
	@echo "▶ Checking Python packages..."
	@pip3 install -q pywinrm requests 2>/dev/null || \
		pip3 install --user -q pywinrm requests 2>/dev/null || \
		echo "⚠️  Could not install Python packages. Run manually: pip3 install pywinrm requests"
	@echo "✅ Python packages ready"
	@echo ""

# ── Internal helpers ──────────────────────────────────────────────────────────

.PHONY: _check-docker
_check-docker:
	@echo "▶ Verifying Docker..."
	@docker info > /dev/null 2>&1 || (echo "❌ Docker is not running. Start Docker Desktop first." && exit 1)
	@echo "✅ Docker is running"
	@docker compose version > /dev/null 2>&1 || (echo "❌ Docker Compose not found. Update Docker Desktop." && exit 1)
	@echo "✅ Docker Compose available"

.PHONY: _env
_env:
	@if [ ! -f .env ]; then \
		echo "▶ Creating .env from template..."; \
		cp .env.example .env; \
		echo "✅ .env created — edit it with your Proxmox credentials when ready"; \
	else \
		echo "✅ .env exists"; \
	fi
	@N8N_PW=$$(grep '^N8N_PASSWORD=' .env 2>/dev/null | cut -d'=' -f2-); \
	if [ -z "$$N8N_PW" ]; then \
		echo ""; \
		echo "⚠️  N8N_PASSWORD is not set in .env"; \
		echo "   Generating a random password..."; \
		NEW_PW=$$(python3 -c "import secrets; print(secrets.token_urlsafe(16))"); \
		if [ "$$(uname)" = "Darwin" ]; then \
			sed -i '' "s/^N8N_PASSWORD=.*/N8N_PASSWORD=$$NEW_PW/" .env; \
		else \
			sed -i "s/^N8N_PASSWORD=.*/N8N_PASSWORD=$$NEW_PW/" .env; \
		fi; \
		echo "✅ N8N_PASSWORD auto-generated: $$NEW_PW"; \
	else \
		echo "✅ N8N_PASSWORD is set"; \
	fi
	@if [ ! -f proxmox/terraform/terraform.tfvars ] && [ -f .env ]; then \
		echo "▶ Generating terraform.tfvars from .env..."; \
		. ./.env; \
		printf 'proxmox_url          = "%s"\nproxmox_node         = "%s"\nproxmox_token_id     = "%s"\nproxmox_token_secret = "%s"\n' \
			"$$PROXMOX_URL" "$$PROXMOX_NODE" "$$PROXMOX_TOKEN_ID" "$$PROXMOX_TOKEN_SECRET" \
			> proxmox/terraform/terraform.tfvars; \
		echo "✅ terraform.tfvars generated"; \
	fi

.PHONY: _generate-config
_generate-config:
	@echo "▶ Generating dashboard config..."
	@. .env 2>/dev/null; \
	printf '{\n  "guacProxy": "/guacamole",\n  "guacAdmin": "%s",\n  "guacAdminPw": "%s",\n  "guacDs": "postgresql",\n  "vmUser": "%s",\n  "vmPassword": "%s",\n  "proxmoxUrl": "%s",\n  "nginxPort": "%s",\n  "guacPort": "%s",\n  "portainerPort": "%s",\n  "n8nPort": "%s"\n}' \
		"$${GUAC_ADMIN_USER:-guacadmin}" \
		"$${GUAC_ADMIN_PASSWORD:-guacadmin}" \
		"$${LAB_VM_USER:-demo}" \
		"$${LAB_VM_PASSWORD:-SEdemo2026}" \
		"$${PROXMOX_URL:-}" \
		"$${NGINX_PORT:-8080}" \
		"$${GUAC_PORT:-8085}" \
		"$${PORTAINER_PORT:-9000}" \
		"$${N8N_PORT:-5678}" \
		> nginx/html/config.json
	@echo "✅ Dashboard config generated"

.PHONY: _up
_up:
	@echo "▶ Starting containers..."
	$(COMPOSE) up -d

.PHONY: _wait-healthy
_wait-healthy:
	@echo "▶ Waiting for services to be healthy (up to 60s)..."
	@for i in $$(seq 1 12); do \
		if docker inspect --format='{{.State.Health.Status}}' labops-guac-postgres 2>/dev/null | grep -q healthy; then \
			echo "✅ All services healthy"; \
			break; \
		fi; \
		if [ $$i -eq 12 ]; then \
			echo "⚠️  Health check timed out — services may still be starting"; \
			echo "   Check with: make status"; \
		fi; \
		printf "."; \
		sleep 5; \
	done

.PHONY: _import-workflows
_import-workflows:
	@echo "▶ Importing n8n workflows..."
	@N8N_PW=$$(grep '^N8N_PASSWORD=' .env | cut -d'=' -f2-); \
	for f in n8n/workflows/*.json; do \
		curl -s -X POST "http://localhost:5678/api/v1/workflows" \
			-H "Content-Type: application/json" \
			-u "admin:$$N8N_PW" \
			-d @"$$f" > /dev/null 2>&1 && \
			echo "  ✅ Imported $$(basename $$f)" || \
			echo "  ⚠️  Failed to import $$(basename $$f)"; \
	done
	@echo "▶ Activating workflows..."
	@N8N_PW=$$(grep '^N8N_PASSWORD=' .env | cut -d'=' -f2-); \
	curl -s "http://localhost:5678/api/v1/workflows" -u "admin:$$N8N_PW" 2>/dev/null | \
		python3 -c "import sys,json; [print(w['id']) for w in json.load(sys.stdin).get('data',[])]" 2>/dev/null | \
		while read wid; do \
			curl -s -X PATCH "http://localhost:5678/api/v1/workflows/$$wid" \
				-H "Content-Type: application/json" \
				-u "admin:$$N8N_PW" \
				-d '{"active":true}' > /dev/null 2>&1; \
		done; \
	echo "✅ Workflows imported and activated"

# ── Cleanup ───────────────────────────────────────────────────────────────────

.PHONY: clean
clean:
	@echo "⚠️  This will stop all containers and delete all volumes."
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 0
	$(COMPOSE) down -v
	@echo "✅ All containers and volumes removed"
