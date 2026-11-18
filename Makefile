SHELL := /bin/sh

# Load local environment. If .env is absent, create it from the committed example.
ENV_FILE := .env
ENV_EXAMPLE := .env.example
ifeq ($(wildcard $(ENV_FILE)),)
$(shell cp $(ENV_EXAMPLE) $(ENV_FILE) && chmod 600 $(ENV_FILE))
endif
-include $(ENV_FILE)
export

SRC := src
BUNDLE := cd $(SRC) && bundle
BIN := $(SRC)/bin/jira-cld
RUN := cd $(SRC) && bundle exec ruby bin/jira-cld
PROJECT ?= alpha
RANGE ?= 1h
CONFIG ?=
HTTP_HOST ?= 127.0.0.1
HTTP_PORT ?= 8765
HTTP_PATH ?= /mcp
HOST_CONFIG ?= $(HOME)/.config/jira-cld/config.yml
HOST_CONFIG_DIR ?= $(HOME)/.config/jira-cld
HOST_DATA ?= $(HOME)/.local/share/jira-cld
UI_DOCKER_PORT ?= 9292
PROJECT_ARG = $(if $(PROJECT),--project $(PROJECT),)
CONFIG_ARG = $(if $(CONFIG),--config $(CONFIG),)
DOCKER_IMAGE ?= jira-cld
DOCKER_TAG ?= local
DOCKERFILE := docker/Dockerfile
DOCKER_NAME ?= jira-cld-$(PROJECT)
DOCKER_UI_NAME ?= jira-cld-ui
DOCKER_RESTART ?=

.PHONY: help env install update test lint lint-fix fmt check run mcp mcp-http run-http http print-opencode ui setup doctor stats cache-stats cache-clear db-migrate db-check assets-list assets-verify memory latency docker-headless docker-full docker-build docker-run-http docker-up docker-down docker-logs docker-status docker-run-ui docker-up-ui docker-down-ui docker-logs-ui docker-status-ui clean

env:
	@test -f $(ENV_FILE) || (cp $(ENV_EXAMPLE) $(ENV_FILE) && chmod 600 $(ENV_FILE))
	@echo "$(ENV_FILE) ready"

help:
	@printf '%s\n' \
	  'make install              bundle install (src/)' \
	  'make test                 run minitest' \
	  'make lint                 run rubocop' \
	  'make check                test + lint + assets:verify' \
	  'make run                  run MCP server (PROJECT=alpha)' \
	  'make mcp                  alias for run (stdio)' \
	  'make mcp-http             run Streamable HTTP MCP on 127.0.0.1:8765/mcp' \
	  'make print-opencode       print remote opencode snippet (URL only)' \
	  'make docker-run-http      run HTTP MCP in Docker (foreground)' \
	  'make docker-up            build + run HTTP MCP in Docker (detached)' \
	  'make docker-down          stop and remove the container' \
	  'make docker-logs          follow container logs' \
	  'make docker-status        container status + health check' \
	  'make docker-up-ui         build + run UI in Docker (detached)' \
	  'make docker-run-ui        run UI in Docker (foreground)' \
	  'make docker-down-ui       stop and remove the UI container' \
	  'make docker-logs-ui       follow UI container logs (contains URL)' \
	  'make docker-status-ui     UI container status' \
	  'make ui                   run local UI' \
	  'make setup                non-interactive setup (JIRA_URL=... PROJECT=...)' \
	  'make doctor               run doctor (offline with OFFLINE=1)' \
	  'make stats                stats table (RANGE=1h)' \
	  'make cache-stats          cache namespace table' \
	  'make cache-clear          clear cache (scope=expired, requires YES=1)' \
	  'make db-migrate           apply migrations' \
	  'make db-check             sqlite integrity check' \
	  'make assets-verify        verify vendored assets' \
	  'make docker-headless      build headless docker image' \
	  'make docker-full          build docker image with UI'

install: env
	$(BUNDLE) install

update:
	$(BUNDLE) update

test:
	$(BUNDLE) exec rake test

lint:
	$(BUNDLE) exec rubocop

lint-fix:
	$(BUNDLE) exec rubocop -A

fmt: lint-fix

check: test lint assets-verify

run: mcp

mcp:
	cd $(SRC) && MCP_PROJECT_ID=$(PROJECT) bundle exec ruby bin/jira-cld mcp

mcp-http: run-http

run-http:
	cd $(SRC) && MCP_PROJECT_ID=$(PROJECT) MCP_HTTP_HOST=$(HTTP_HOST) MCP_HTTP_PORT=$(HTTP_PORT) MCP_HTTP_PATH=$(HTTP_PATH) \
	  bundle exec ruby bin/jira-cld mcp-http

http: run-http

print-opencode:
	cd $(SRC) && bundle exec ruby bin/jira-cld config print-opencode --http --host $(HTTP_HOST) --port $(HTTP_PORT) --path $(HTTP_PATH) $(PROJECT_ARG) $(CONFIG_ARG)

docker-run-http: docker-headless
	@test -f "$(HOST_CONFIG)" || (echo "missing $(HOST_CONFIG); run make setup PROJECT=$(PROJECT)"; exit 2)
	@test -d "$(HOST_DATA)" || mkdir -p "$(HOST_DATA)"
	docker run --rm --name jira-cld-$(PROJECT) \
	  --user "$$(id -u):$$(id -g)" \
	  -p 127.0.0.1:$(HTTP_PORT):$(HTTP_PORT) \
	  -e MCP_PROJECT_ID=$(PROJECT) \
	  -e JIRA_BASE_URL -e JIRA_DEPLOYMENT -e JIRA_EMAIL -e JIRA_API_TOKEN -e JIRA_PAT \
	  -e CONFLUENCE_BASE_URL -e CONFLUENCE_API_TOKEN -e CONFLUENCE_EMAIL -e CONFLUENCE_PAT -e CLD_SPACE \
	  -v "$(HOST_CONFIG):/home/jira/.config/jira-cld/config.yml:ro" \
	  -v "$(HOST_DATA):/home/jira/.local/share/jira-cld" \
	  $(DOCKER_IMAGE):$(DOCKER_TAG)-headless mcp-http --host 0.0.0.0 --port $(HTTP_PORT) --path $(HTTP_PATH)

docker-up: docker-headless
	@test -f "$(HOST_CONFIG)" || (echo "missing $(HOST_CONFIG); run make setup PROJECT=$(PROJECT)"; exit 2)
	@test -d "$(HOST_DATA)" || mkdir -p "$(HOST_DATA)"
	@docker rm -f $(DOCKER_NAME) >/dev/null 2>&1 || true
	@docker run -d --name $(DOCKER_NAME) \
	  $(if $(DOCKER_RESTART),--restart $(DOCKER_RESTART),) \
	  --user "$$(id -u):$$(id -g)" \
	  -p 127.0.0.1:$(HTTP_PORT):$(HTTP_PORT) \
	  -e MCP_PROJECT_ID=$(PROJECT) \
	  -e JIRA_BASE_URL -e JIRA_DEPLOYMENT -e JIRA_EMAIL -e JIRA_API_TOKEN -e JIRA_PAT \
	  -e CONFLUENCE_BASE_URL -e CONFLUENCE_API_TOKEN -e CONFLUENCE_EMAIL -e CONFLUENCE_PAT -e CLD_SPACE \
	  -v "$(HOST_CONFIG):/home/jira/.config/jira-cld/config.yml:ro" \
	  -v "$(HOST_DATA):/home/jira/.local/share/jira-cld" \
	  $(DOCKER_IMAGE):$(DOCKER_TAG)-headless mcp-http --host 0.0.0.0 --port $(HTTP_PORT) --path $(HTTP_PATH)
	@printf 'waiting for http://127.0.0.1:%s/health ' "$(HTTP_PORT)"
	@i=0; until curl -fsS "http://127.0.0.1:$(HTTP_PORT)/health" >/dev/null 2>&1; do \
	  i=$$((i+1)); \
	  if [ $$i -ge 30 ]; then \
	    echo; echo "health check failed; last logs:"; \
	    docker logs --tail=50 $(DOCKER_NAME) 2>&1; exit 1; \
	  fi; \
	  printf '.'; sleep 1; \
	done; echo; echo "jira-cld MCP: http://127.0.0.1:$(HTTP_PORT)$(HTTP_PATH) (container $(DOCKER_NAME))"

docker-down:
	@if docker rm -f $(DOCKER_NAME) >/dev/null 2>&1; then \
	  echo "removed $(DOCKER_NAME)"; \
	else \
	  echo "$(DOCKER_NAME) is not running"; \
	fi

docker-logs:
	docker logs -f --tail=100 $(DOCKER_NAME)

docker-status:
	@docker ps --filter "name=^/$(DOCKER_NAME)$$" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
	@curl -fsS "http://127.0.0.1:$(HTTP_PORT)/health" 2>/dev/null && echo || echo "health: no response"

docker-run-ui: docker-full
	@test -f "$(HOST_CONFIG)" || (echo "missing $(HOST_CONFIG); run make setup PROJECT=$(PROJECT)"; exit 2)
	@test -d "$(HOST_DATA)" || mkdir -p "$(HOST_DATA)"
	docker run --rm --name $(DOCKER_UI_NAME) \
	  --user "$$(id -u):$$(id -g)" \
	  -p 127.0.0.1:$(UI_DOCKER_PORT):$(UI_DOCKER_PORT) \
	  -e UI_HOST=0.0.0.0 -e UI_PORT=$(UI_DOCKER_PORT) -e UI_OPEN=0 -e JIRA_CLD_NO_OPEN=1 \
	  -e MCP_PROJECT_ID=$(PROJECT) \
	  -e JIRA_BASE_URL -e JIRA_DEPLOYMENT -e JIRA_EMAIL -e JIRA_API_TOKEN -e JIRA_PAT \
	  -e CONFLUENCE_BASE_URL -e CONFLUENCE_API_TOKEN -e CONFLUENCE_EMAIL -e CONFLUENCE_PAT -e CLD_SPACE \
	  -v "$(HOST_CONFIG_DIR):/home/jira/.config/jira-cld" \
	  -v "$(HOST_DATA):/home/jira/.local/share/jira-cld" \
	  $(DOCKER_IMAGE):$(DOCKER_TAG)-full ui

docker-up-ui: docker-full
	@test -f "$(HOST_CONFIG)" || (echo "missing $(HOST_CONFIG); run make setup PROJECT=$(PROJECT)"; exit 2)
	@test -d "$(HOST_DATA)" || mkdir -p "$(HOST_DATA)"
	@docker rm -f $(DOCKER_UI_NAME) >/dev/null 2>&1 || true
	@docker run -d --name $(DOCKER_UI_NAME) \
	  $(if $(DOCKER_RESTART),--restart $(DOCKER_RESTART),) \
	  --user "$$(id -u):$$(id -g)" \
	  -p 127.0.0.1:$(UI_DOCKER_PORT):$(UI_DOCKER_PORT) \
	  -e UI_HOST=0.0.0.0 -e UI_PORT=$(UI_DOCKER_PORT) -e UI_OPEN=0 -e JIRA_CLD_NO_OPEN=1 \
	  -e MCP_PROJECT_ID=$(PROJECT) \
	  -e JIRA_BASE_URL -e JIRA_DEPLOYMENT -e JIRA_EMAIL -e JIRA_API_TOKEN -e JIRA_PAT \
	  -e CONFLUENCE_BASE_URL -e CONFLUENCE_API_TOKEN -e CONFLUENCE_EMAIL -e CONFLUENCE_PAT -e CLD_SPACE \
	  -v "$(HOST_CONFIG_DIR):/home/jira/.config/jira-cld" \
	  -v "$(HOST_DATA):/home/jira/.local/share/jira-cld" \
	  $(DOCKER_IMAGE):$(DOCKER_TAG)-full ui
	@printf 'waiting for UI URL '
	@i=0; url=""; while [ -z "$$url" ]; do \
	  url=$$(docker logs $(DOCKER_UI_NAME) 2>&1 | grep -o 'http://[^ ]*' | tail -1); \
	  if [ -n "$$url" ]; then break; fi; \
	  i=$$((i+1)); \
	  if [ $$i -ge 30 ]; then \
	    echo; echo "UI failed to start; last logs:"; \
	    docker logs --tail=50 $(DOCKER_UI_NAME) 2>&1; exit 1; \
	  fi; \
	  printf '.'; sleep 1; \
	done; echo; echo "jira-cld UI: $$url (container $(DOCKER_UI_NAME))"

docker-down-ui:
	@if docker rm -f $(DOCKER_UI_NAME) >/dev/null 2>&1; then \
	  echo "removed $(DOCKER_UI_NAME)"; \
	else \
	  echo "$(DOCKER_UI_NAME) is not running"; \
	fi

docker-logs-ui:
	docker logs -f --tail=100 $(DOCKER_UI_NAME)

docker-status-ui:
	@docker ps --filter "name=^/$(DOCKER_UI_NAME)$$" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
	@url=$$(docker logs $(DOCKER_UI_NAME) 2>&1 | grep -o 'http://[^ ]*' | tail -1); \
	if [ -n "$$url" ]; then \
	  curl -s -o /dev/null -w 'http=%{http_code}\n' "$$url"; \
	else \
	  echo "ui: no URL in logs"; \
	fi

ui:
	$(RUN) ui

setup:
	$(RUN) setup --non-interactive \
	  --jira-url "$(or $(JIRA_URL),$(JIRA_BASE_URL))" \
	  --deployment "$(or $(DEPLOYMENT),$(JIRA_DEPLOYMENT),cloud)" \
	  $(if $(or $(EMAIL),$(JIRA_EMAIL)),--email "$(or $(EMAIL),$(JIRA_EMAIL))",) \
	  $(if $(PAT_REF),--pat-ref "$(PAT_REF)",) \
	  $(if $(TOKEN_REF),--token-ref "$(TOKEN_REF)",) \
	  --confluence-url "$(or $(CONFLUENCE_URL),$(CONFLUENCE_BASE_URL))" \
	  --space "$(or $(SPACE),$(CLD_SPACE),CLD)" \
	  --project "$(PROJECT)" \
	  --jira-key "$(or $(JIRA_KEY),$(PROJECT))" $(CONFIG_ARG)

doctor:
	$(RUN) doctor $(PROJECT_ARG) $(CONFIG_ARG) $(if $(filter 1,$(OFFLINE)),--offline,)

stats:
	$(RUN) stats $(PROJECT_ARG) --range $(RANGE) $(CONFIG_ARG)

cache-stats:
	$(RUN) cache stats $(PROJECT_ARG) $(CONFIG_ARG)

cache-clear:
	@test "$(YES)" = "1" || (echo "refusing: set YES=1, e.g. make cache-clear PROJECT=alpha YES=1 SCOPE=expired"; exit 2)
	$(RUN) cache clear $(PROJECT_ARG) --scope $(or $(SCOPE),expired) --yes $(CONFIG_ARG)

db-migrate:
	$(RUN) db migrate $(PROJECT_ARG) $(CONFIG_ARG)

db-check:
	$(RUN) db check $(PROJECT_ARG) $(CONFIG_ARG)

assets-list:
	$(BUNDLE) exec rake assets:list

assets-verify:
	$(BUNDLE) exec rake assets:verify

memory:
	cd $(SRC) && MCP_PROJECT_ID=$(PROJECT) bundle exec rake memory:measure

latency:
	$(BUNDLE) exec rake latency:measure

docker-headless:
	docker build -f $(DOCKERFILE) --build-arg INSTALL_UI=false -t $(DOCKER_IMAGE):$(DOCKER_TAG)-headless .

docker-full:
	docker build -f $(DOCKERFILE) --build-arg INSTALL_UI=true -t $(DOCKER_IMAGE):$(DOCKER_TAG)-full .

docker-build: docker-headless docker-full

clean:
	rm -rf src/tmp src/coverage src/.bundle src/vendor/bundle result src/jira-cld-*.gem
