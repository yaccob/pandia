IMAGE        := yaccob/pandia
VERSION      := 1.7.0
CONTAINER_RT := $(shell which podman 2>/dev/null || which docker 2>/dev/null)

.PHONY: build test

# Build context must be project root because Dockerfile COPYs from server/ and cli/
build:
	cd .. && $(CONTAINER_RT) build -f container/Dockerfile -t $(IMAGE):$(VERSION) -t $(IMAGE):latest .

# Run all container tests, collecting failures
test: build
	@rc=0; \
	bash test/test-container.sh || rc=1; \
	bash test/test-entrypoint.sh || rc=1; \
	exit $$rc
