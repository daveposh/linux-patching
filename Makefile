# Makefile for Linux Patching Scripts

.PHONY: help test test-all test-build test-syntax test-config test-profiles test-interactive clean

help: ## Show this help message
	@echo "Linux Patching - Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

test: test-all ## Run all tests (alias for test-all)

test-all: ## Run all tests
	@./test/run-tests.sh all

test-build: ## Build test Docker images
	@./test/run-tests.sh build

test-syntax: ## Test script syntax
	@./test/run-tests.sh syntax

test-config: ## Test configuration loading
	@./test/run-tests.sh config

test-profiles: ## Test profile loading
	@./test/run-tests.sh profiles

test-filtering: ## Test package filtering
	@./test/run-tests.sh filtering

test-show-config: ## Test show-config script
	@./test/run-tests.sh show-config

test-scheduler: ## Test scheduler logic
	@./test/run-tests.sh scheduler

test-windows: ## Test maintenance windows
	@./test/run-tests.sh windows

test-interactive: ## Start interactive test container
	@./test/run-tests.sh interactive

test-scenarios: ## Run test scenarios
	@echo "Running test scenarios..."
	@for scenario in test/scenarios/*.sh; do \
		echo "Running $$scenario..."; \
		docker run --rm -v "$(PWD):/test" linux-patching-test:base \
			bash "/test/$$scenario" || exit 1; \
	done

clean: ## Clean up Docker images
	@echo "Cleaning up test images..."
	-docker rmi linux-patching-test:base linux-patching-test:with-updates 2>/dev/null || true
	@echo "Clean complete"

.DEFAULT_GOAL := help
