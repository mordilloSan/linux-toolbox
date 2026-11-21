.PHONY: help check test
.DEFAULT_GOAL := help

# Read here, before any include, so it names this file even when MAKEFILES loads others.
THIS_MAKEFILE := $(lastword $(MAKEFILE_LIST))
SHELL_FILES := $(wildcard *.sh) test

# The installer's status tag, coloured only on a terminal and never with NO_COLOR set.
ifeq ($(NO_COLOR)$(if $(MAKE_TERMOUT),,plain),)
esc := $(shell printf '\033')
ok := $(esc)[90m[$(esc)[38;5;154m  OK  $(esc)[90m]$(esc)[0m
else
ok := [  OK  ]
endif

help: ## List the targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf " %-6s %s\n", $$1, $$2}' $(THIS_MAKEFILE)

check: ## Lint the shell scripts and workflows (shellcheck, shfmt, actionlint)
	@shellcheck -- $(SHELL_FILES)
	@echo ' $(ok) shellcheck: $(words $(SHELL_FILES)) files'
	@shfmt -d -- $(SHELL_FILES)
	@echo ' $(ok) shfmt: $(words $(SHELL_FILES)) files'
	@actionlint
	@echo ' $(ok) actionlint: $(words $(wildcard .github/workflows/*.yml)) workflows'

test: ## Run the test suite
	@bash test
