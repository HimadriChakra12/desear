SHELL := /bin/bash

SETTINGS := config/searxng/settings.yml
SETTINGS_EXAMPLE := config/searxng/settings.yml.example
PLACEHOLDER := REPLACE_ME_WITH_RANDOM_SECRET

.PHONY: help init check-secret up down build restart logs ps health \
        backup restore clean

help:
	@echo "make init          - create config/searxng/settings.yml with a fresh secret_key"
	@echo "make up            - start the stack (fails if secret_key is missing/placeholder)"
	@echo "make down          - stop the stack"
	@echo "make build         - rebuild the wrapper image"
	@echo "make restart       - restart all services"
	@echo "make logs          - follow logs for all services"
	@echo "make ps            - show container status"
	@echo "make health        - curl the wrapper health + categories endpoints"
	@echo "make backup        - run backups/backup.sh"
	@echo "make restore FILE=backups/backup-....tar.gz - run backups/restore.sh"
	@echo "make clean         - stop stack and remove containers (keeps data/config)"

# ---------------------------------------------------------------------
# Secret key handling
# ---------------------------------------------------------------------

init:
	@if [ -f "$(SETTINGS)" ]; then \
		echo "$(SETTINGS) already exists - not overwriting."; \
		echo "Delete it first if you want to regenerate."; \
	else \
		cp "$(SETTINGS_EXAMPLE)" "$(SETTINGS)"; \
		KEY=$$(openssl rand -hex 32); \
		sed -i.bak "s/$(PLACEHOLDER)/$$KEY/" "$(SETTINGS)"; \
		rm -f "$(SETTINGS).bak"; \
		echo "Created $(SETTINGS) with a freshly generated secret_key."; \
	fi

check-secret:
	@if [ ! -f "$(SETTINGS)" ]; then \
		echo "ERROR: $(SETTINGS) is missing."; \
		echo "  Run 'make init' first to generate one."; \
		exit 1; \
	fi
	@if grep -q "$(PLACEHOLDER)" "$(SETTINGS)"; then \
		echo "ERROR: $(SETTINGS) still has the placeholder secret_key."; \
		echo "  Run 'make init' (on a fresh checkout) or manually replace"; \
		echo "  '$(PLACEHOLDER)' with the output of: openssl rand -hex 32"; \
		exit 1; \
	fi
	@echo "secret_key OK."

# ---------------------------------------------------------------------
# Stack lifecycle
# ---------------------------------------------------------------------

up: check-secret
	docker compose up -d --build

down:
	docker compose down

build:
	docker compose build wrapper

restart: check-secret
	docker compose restart

logs:
	docker compose logs -f

ps:
	docker compose ps

health:
	@curl -sf http://localhost:8000/api/categories >/dev/null && echo "wrapper: OK"
	@curl -sfo /dev/null -w "web UI: HTTP %{http_code}\n" http://localhost:8000/

# ---------------------------------------------------------------------
# Backup / restore
# ---------------------------------------------------------------------

backup:
	./backups/backup.sh

restore:
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make restore FILE=backups/backup-YYYYMMDD-HHMMSS.tar.gz"; \
		echo "   or: make restore-git FILE=backup-YYYYMMDD-HHMMSS.tar.gz"; \
		exit 1; \
	fi
	./backups/restore.sh "$(FILE)"

restore-git:
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make restore-git FILE=backup-YYYYMMDD-HHMMSS.tar.gz"; \
		exit 1; \
	fi
	./backups/restore.sh --from-git "$(FILE)"

clean:
	docker compose down --remove-orphans
