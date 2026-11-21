.PHONY: help check test
.DEFAULT_GOAL := help

# Read here, before any include, so it names this file even when MAKEFILES loads others.
THIS_MAKEFILE := $(lastword $(MAKEFILE_LIST))
SHELL_FILES := $(wildcard *.sh) test

help: ## List the targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  %-6s %s\n", $$1, $$2}' $(THIS_MAKEFILE)

check: ## Lint the shell scripts and workflows (shellcheck, shfmt, actionlint)
	shellcheck -- $(SHELL_FILES)
	shfmt -d -- $(SHELL_FILES)
	actionlint

test: ## Run the test suite
	bash test
