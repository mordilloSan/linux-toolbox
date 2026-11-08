.PHONY: check test

SHELL_FILES := $(wildcard *.sh) test

check:
	shellcheck -- $(SHELL_FILES)
	shfmt -d -- $(SHELL_FILES)
	actionlint

test:
	bash test
