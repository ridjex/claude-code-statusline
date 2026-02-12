.PHONY: test test-verbose demo install

test:
	./tests/run-tests.sh

test-verbose:
	./tests/run-tests.sh -v

demo:
	./scripts/generate-demo.sh

install:
	./install.sh
