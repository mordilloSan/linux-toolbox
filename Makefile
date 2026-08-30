.PHONY: check test

SHELL_FILES := $(wildcard *.sh) test

check:
	bash -n -- $(SHELL_FILES)
	shellcheck -- $(SHELL_FILES)
	shfmt -d -- $(SHELL_FILES)
	actionlint

test:
	bash test
