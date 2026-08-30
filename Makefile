.PHONY: check

check:
	bash -n -- *.sh
	shellcheck -- *.sh
	shfmt -d -- *.sh
	actionlint
