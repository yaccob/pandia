SRC      := example.md
FILTER   := diagram-filter.lua
PDF      := $(SRC:.md=.pdf)
HTML     := $(SRC:.md=.html)
IMGDIR   := img
IMAGE    := yaccob/pandia
VERSION  := 1.6.0
CONTAINER_RT := $(shell which podman 2>/dev/null || which docker 2>/dev/null)
TEST_PORT := 13301
TEST_CONTAINER := pandia-test-all

PANDOC_COMMON := --lua-filter=$(FILTER) --from=gfm+tex_math_dollars

.PHONY: all pdf html clean test test-quick test-all test-container vscode-ext vscode-install docker-pdf docker-html docker-build docker-push docker-test mutate mutate-full

# --- Local targets (require pandoc + tools installed) ---

all: pdf html

pdf: $(PDF)
html: $(HTML)

$(PDF): $(SRC) $(FILTER)
	pandoc $(PANDOC_COMMON) \
		--to=pdf \
		--pdf-engine=pdflatex \
		-V geometry:margin=2.5cm \
		-V mainfont="Helvetica" \
		-V classoption=fleqn \
		--standalone \
		-o $@ $<

$(HTML): $(SRC) $(FILTER)
	pandoc $(PANDOC_COMMON) \
		--to=html5 \
		--standalone \
		--mathjax \
		-V maxwidth=60em \
		-V "header-includes=<script>window.MathJax={chtml:{displayAlign:'left'}};</script>" \
		--metadata title="Markdown with Diagrams and Formulas" \
		-o $@ $<

clean:
	rm -rf $(PDF) $(HTML) $(IMGDIR)

test:
	bash test/test.sh

test-quick:
	bash test/test-dir.sh
	bash test/test-diagrams.sh
	bash test/test-robustness.sh
	bash test/test-cli.sh
	bash test/test-docs.sh

# --- Mutation testing ---

mutate:
	@bash test/mutate.sh $(or $(MUTATE_ROUNDS),100) test-quick

mutate-full:
	@bash test/mutate.sh $(or $(MUTATE_ROUNDS),100) test-all

# --- Full pre-commit test suite ---

test-all: test-quick test-cli-integration test-container test-vscode
	@printf "\n\033[1;32m=== All test levels passed ===\033[0m\n"

test-cli-integration: html
	@printf "\n\033[1m=== CLI integration: example.md ===\033[0m\n"
	@bash test/test-cli-integration.sh $(HTML)

test-container: docker-build
	@printf "\n\033[1m=== Container tests (pure image) ===\033[0m\n"
	@bash test/test-container.sh $(TEST_PORT)

VSCODE_SRC := $(wildcard pandia-vscode/src/*.ts) pandia-vscode/package.json pandia-vscode/tsconfig.json
VSIX       := pandia-vscode/pandia-preview-0.1.0.vsix

test-vscode: vscode-install
	@printf "\n\033[1m=== VS Code extension ===\033[0m\n"
	cd "$(CURDIR)/pandia-vscode" && node --test test/*.test.mjs

# --- VS Code extension ---

$(VSIX): $(VSCODE_SRC)
	cd "$(CURDIR)/pandia-vscode" && npm install && npx tsc && npx @vscode/vsce package --allow-missing-repository

vscode-ext: $(VSIX)

vscode-install: $(VSIX)
	code --install-extension $(VSIX)

# --- Docker targets ---

docker-pdf:
	docker run --rm -v "$$PWD:/data" $(IMAGE) -t pdf -o $(PDF) $(SRC)

docker-html:
	docker run --rm -v "$$PWD:/data" $(IMAGE) -t html -o $(HTML) $(SRC)

docker-build:
	$(CONTAINER_RT) build -t $(IMAGE):$(VERSION) -t $(IMAGE):latest .

docker-push: docker-build
	docker push $(IMAGE):$(VERSION)
	docker push $(IMAGE):latest

docker-test:
	docker run --rm -v "$$PWD:/data" --entrypoint /bin/sh $(IMAGE) -c "apk add --no-cache bash >/dev/null 2>&1 && bash /data/test/test.sh /data/$(FILTER)"
