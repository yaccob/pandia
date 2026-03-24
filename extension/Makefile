VSIX := pandia-preview-0.1.0.vsix

.PHONY: build install test

build: $(VSIX)

$(VSIX): $(wildcard src/*.ts) package.json tsconfig.json
	npm install && npx tsc && npx @vscode/vsce package --allow-missing-repository

install: $(VSIX)
	code --install-extension $(VSIX)

test: $(VSIX)
	node --test test/*.test.mjs
