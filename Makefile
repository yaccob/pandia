.PHONY: build test-all

build:
	$(MAKE) -C container build
	$(MAKE) -C extension install

test-all:
	$(MAKE) -C server test
	$(MAKE) -C container test
	$(MAKE) -C cli test
	$(MAKE) -C extension test
