# WoodPantry — Root Makefile
# Manages the local dev stack and smoke tests via podman compose.

COMPOSE := podman compose -f local/docker-compose.yaml --env-file local/.env
TESTS_DIR := tests

# --- Dev Stack ---

.PHONY: dev
dev: dev-down ## Start the full local stack (rebuild images)
	$(COMPOSE) up --build -d
	@echo ""
	@echo "Stack is starting. Run 'make logs' to watch output."
	@echo "Services: ingredients=:8081  recipes=:8082  pantry=:8083  matching=:8084  ingestion=:8085"
	@echo "Postgres=:5432  RabbitMQ=:5672 (mgmt=:15672)"

.PHONY: dev-up
dev-up: ## Start the stack without rebuilding
	$(COMPOSE) up -d

.PHONY: dev-down
dev-down: ## Tear down the stack and remove orphans
	$(COMPOSE) down --remove-orphans --volumes 2>/dev/null || true

.PHONY: dev-restart
dev-restart: dev-down dev ## Rebuild and restart everything

.PHONY: logs
logs: ## Tail all service logs
	$(COMPOSE) logs -f

.PHONY: ps
ps: ## Show running containers
	$(COMPOSE) ps

# --- Testing ---

.PHONY: test
test: dev wait-healthy ## Bring up stack, run smoke tests, tear down
	@bash $(TESTS_DIR)/run_all.sh; rc=$$?; $(MAKE) dev-down; exit $$rc

.PHONY: test-only
test-only: wait-healthy ## Run smoke tests against an already-running stack
	@bash $(TESTS_DIR)/run_all.sh

.PHONY: test-health
test-health: ## Run only health-check smoke tests
	@bash $(TESTS_DIR)/smoke_health.sh

.PHONY: wait-healthy
wait-healthy: ## Wait for all services to pass health checks (up to 120s)
	@echo "Waiting for services to become healthy..."
	@for i in $$(seq 1 24); do \
		if bash $(TESTS_DIR)/smoke_health.sh > /dev/null 2>&1; then \
			echo "All services healthy."; \
			exit 0; \
		fi; \
		echo "  attempt $$i/24 — retrying in 5s..."; \
		sleep 5; \
	done; \
	echo "ERROR: Services did not become healthy within 120s."; \
	$(COMPOSE) ps; \
	$(COMPOSE) logs --tail=20; \
	exit 1

# --- Cleanup ---

.PHONY: clean
clean: dev-down ## Full teardown including named volumes
	podman volume prune -f 2>/dev/null || true

# --- Help ---

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
