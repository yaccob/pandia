.PHONY: test

# Run all server tests, collecting failures
test:
	@rc=0; \
	bash test/test-dir.sh || rc=1; \
	bash test/test-diagrams.sh || rc=1; \
	bash test/test-robustness.sh || rc=1; \
	bash test/test-docs.sh || rc=1; \
	bash test/test-math-visual.sh || rc=1; \
	node test/test-diagram-layout.mjs || rc=1; \
	exit $$rc
