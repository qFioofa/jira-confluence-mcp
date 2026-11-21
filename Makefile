SHELL := /bin/sh

# Load local environment. If .env is absent, create it from the committed example.
ENV_FILE := .env
ENV_EXAMPLE := .env.example
ifeq ($(wildcard $(ENV_FILE)),)
$(shell cp $(ENV_EXAMPLE) $(ENV_FILE) && chmod 600 $(ENV_FILE))
endif
-include $(ENV_FILE)
export

PROJECT ?= $(MCP_PROJECT_ID)
HTTP_HOST ?= $(or $(MCP_HTTP_HOST),127.0.0.1)
HTTP_PORT ?= $(or $(MCP_HTTP_PORT),8765)
HTTP_PATH ?= $(or $(MCP_HTTP_PATH),/mcp)
ALLOWED_HOSTS ?= $(if $(strip $(MCP_HTTP_ALLOWED_HOSTS)),$(MCP_HTTP_ALLOWED_HOSTS),localhost,127.0.0.1)

DOCKER_IMAGE ?= jira-mcp
DOCKER_TAG ?= local
DOCKERFILE := mcp/Dockerfile
DOCKER_NAME ?= jira-mcp

.PHONY: help env install test core-test mcp-test web-test web-install web-setup web-migrate web \
        local-mcp mcp check compose-up compose-down docker-mcp-build docker-mcp-up docker-mcp-down \
        docker-mcp-logs docker-mcp-status clean

env:
	@test -f $(ENV_FILE) || (cp $(ENV_EXAMPLE) $(ENV_FILE) && chmod 600 $(ENV_FILE))
	@echo "$(ENV_FILE) ready"

help:
	@printf '%s\n' \
	  'make install              install lib, mcp and rails bundles' \
	  'make local-mcp            run standalone MCP HTTP server (Rack + Puma)' \
	  'make test                 run core, MCP and Rails tests' \
	  'make core-test            run jira_core tests' \
	  'make mcp-test             run jira_mcp tests' \
	  'make web-test             run Rails tests' \
	  'make web                  run Rails server' \
	  'make docker-mcp-up        build and start the MCP container' \
	  'make docker-mcp-down      stop and remove the MCP container' \
	  'make compose-up           run the whole stack with Docker Compose' \
	  'make compose-down         stop the Compose stack'

install: env
	cd lib && bundle install
	cd mcp && bundle install
	cd rails && bundle install

test: core-test mcp-test web-test

core-test:
	cd lib && bundle exec rake test

mcp-test:
	cd mcp && bundle exec rake test

web-install:
	cd rails && bundle install

web-setup: web-install
	cd rails && bin/rails db:prepare db:seed

web-migrate:
	cd rails && bin/rails db:migrate

web:
	cd rails && bin/rails server

web-test:
	cd rails && bin/rails test

local-mcp: env
	cd mcp && $(if $(PROJECT),MCP_PROJECT_ID=$(PROJECT),) bundle exec ruby bin/jira-mcp-http \
	  --host $(HTTP_HOST) --port $(HTTP_PORT) --path $(HTTP_PATH)

mcp: local-mcp

check: test

compose-up:
	DOCKER_BUILDKIT=0 docker compose up --build

compose-down:
	docker compose down

docker-mcp-build:
	docker build -f $(DOCKERFILE) -t $(DOCKER_IMAGE):$(DOCKER_TAG) .

docker-mcp-up: docker-mcp-build
	@docker rm -f $(DOCKER_NAME) >/dev/null 2>&1 || true
	@docker run -d --name $(DOCKER_NAME) \
	  --env-file $(ENV_FILE) \
	  $(if $(PROJECT),-e MCP_PROJECT_ID=$(PROJECT),) \
	  -e MCP_HTTP_HOST=0.0.0.0 \
	  -e MCP_HTTP_PORT=8765 \
	  -e MCP_HTTP_PATH=$(HTTP_PATH) \
	  -e MCP_HTTP_ALLOWED_HOSTS=$(ALLOWED_HOSTS) \
	  -p 127.0.0.1:$(HTTP_PORT):8765 \
	  $(DOCKER_IMAGE):$(DOCKER_TAG)
	@printf 'waiting for http://127.0.0.1:%s/health ' "$(HTTP_PORT)"
	@i=0; until curl -fsS "http://127.0.0.1:$(HTTP_PORT)/health" >/dev/null 2>&1; do \
	  i=$$((i+1)); \
	  if [ $$i -ge 30 ]; then \
	    echo; echo "health check failed; last logs:"; \
	    docker logs --tail=50 $(DOCKER_NAME) 2>&1; exit 1; \
	  fi; \
	  printf '.'; sleep 1; \
	done; echo; echo "jira-mcp: http://127.0.0.1:$(HTTP_PORT)$(HTTP_PATH) (container $(DOCKER_NAME))"

docker-mcp-down:
	@if docker rm -f $(DOCKER_NAME) >/dev/null 2>&1; then \
	  echo "removed $(DOCKER_NAME)"; \
	else \
	  echo "$(DOCKER_NAME) is not running"; \
	fi

docker-mcp-logs:
	docker logs -f --tail=100 $(DOCKER_NAME)

docker-mcp-status:
	@docker ps --filter "name=^/$(DOCKER_NAME)$$" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
	@curl -fsS "http://127.0.0.1:$(HTTP_PORT)/health" 2>/dev/null && echo || echo "health: no response"

clean:
	rm -rf lib/.bundle mcp/.bundle rails/.bundle lib/vendor/bundle mcp/vendor/bundle rails/vendor/bundle
	rm -rf lib/tmp mcp/tmp rails/tmp lib/*.gem mcp/*.gem
