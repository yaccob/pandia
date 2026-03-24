.PHONY: test

# Run all CLI tests, collecting failures
test:
	@rc=0; \
	bash test/test-cli.sh || rc=1; \
	bash test/test-watch.sh || rc=1; \
	exit $$rc
