# =============================================================================
# LabOps — Automated Lab Manager Makefile
# Docker Compose-based training environment for 200+ SEs
#
# Usage:
#   make install     → full first-time setup (run this once)
#   make up          → start the stack
#   make down        → stop the stack
#   make restart     → restart all containers
#   make status      → show container health
#   make logs        → tail all logs
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
	@echo "  make install      Full first-time setup"
	@echo "  make up           Start all containers"
	@echo "  make down         Stop all containers"
	@echo "  make restart      Restart all containers"
	@echo "  make status       Show container health"
	@echo "  make logs         Tail all container logs"
	@echo "  make provision    Provision lab VMs (windows-client)"
	@echo "  make teardown     Tear down lab VMs"
	@echo "  make health       Run health check"
	@echo "  make clean        Remove all containers and volumes (destructive)"
	@echo ""

# ── Install (first-time) ────────────────────────────────────────────────────

.PHONY: install
install: _check-docker _env _up _wait-healthy
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
	@echo "  n8n:            http://localhost:5678"
	@echo "  Guacamole:      http://localhost:8085/guacamole"
	@echo "  Portainer:      http://localhost:9000"
	@echo "  Front-End:      http://localhost:8080"
	@echo ""
	@echo "  Run 'make status' to verify all services."
	@echo ""

# ── Core stack operations ─────────────────────────────────────────────────────

.PHONY: up
up:
	@echo ">> Starting LabOps stack..."
	$(COMPOSE) up -d
	@echo "Stack started -- run 'make status' to check health"

.PHONY: down
down:
	@echo ">> Stopping LabOps stack..."
	$(COMPOSE) down
	@echo "Stack stopped"

.PHONY: restart
restart:
	@echo ">> Restarting LabOps stack..."
	$(COMPOSE) restart

.PHONY: status
status:
	$(COMPOSE) ps

.PHONY: logs
logs:
	$(COMPOSE) logs -f

# ── Provisioning ──────────────────────────────────────────────────────────────

.PHONY: provision
provision:
	@echo ">> Provisioning lab VMs..."
	@bash proxmox/provision.sh windows-client

.PHONY: teardown
teardown:
	@echo ">> Tearing down lab VMs..."
	@bash proxmox/provision.sh teardown

# ── Health ────────────────────────────────────────────────────────────────────

.PHONY: health
health:
	@echo ">> Running health check..."
	@bash scripts/health-check.sh

# ── Internal helpers ──────────────────────────────────────────────────────────

.PHONY: _check-docker
_check-docker:
	@echo ">> Checking prerequisites..."
	@docker info > /dev/null 2>&1 || (echo "ERROR: Docker is not running. Start Docker Desktop first." && exit 1)
	@echo "   Docker is running"
	@docker compose version > /dev/null 2>&1 || (echo "ERROR: Docker Compose not found. Update Docker Desktop." && exit 1)
	@echo "   Docker Compose available"

.PHONY: _env
_env:
	@if [ ! -f .env ]; then \
		echo ">> Creating .env from .env.example..."; \
		cp .env.example .env; \
		echo "   .env created from template"; \
	else \
		echo "   .env exists"; \
	fi
	@N8N_PW=$$(grep '^N8N_PASSWORD=' .env 2>/dev/null | cut -d'=' -f2-); \
	if [ -z "$$N8N_PW" ]; then \
		echo ""; \
		echo "ERROR: N8N_PASSWORD is not set in .env"; \
		echo "       Edit .env and set a value for N8N_PASSWORD before continuing."; \
		echo ""; \
		exit 1; \
	else \
		echo "   N8N_PASSWORD is set"; \
	fi

.PHONY: _up
_up:
	@echo ">> Starting containers..."
	$(COMPOSE) up -d

.PHONY: _wait-healthy
_wait-healthy:
	@echo ">> Waiting for labops-guac-postgres to be healthy (up to 60s)..."
	@for i in $$(seq 1 12); do \
		if docker inspect --format='{{.State.Health.Status}}' labops-guac-postgres 2>/dev/null | grep -q healthy; then \
			echo "   labops-guac-postgres is healthy"; \
			break; \
		fi; \
		if [ $$i -eq 12 ]; then \
			echo "WARNING: labops-guac-postgres health check timed out (60s)"; \
			echo "         It may still be initializing. Check with: make status"; \
		fi; \
		printf "."; \
		sleep 5; \
	done

# ── Cleanup ───────────────────────────────────────────────────────────────────

.PHONY: clean
clean:
	@echo "WARNING: This will stop all containers and delete all volumes."
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 0
	$(COMPOSE) down -v
	@echo "All containers and volumes removed"
