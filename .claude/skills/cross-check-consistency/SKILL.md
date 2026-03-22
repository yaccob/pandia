---
name: cross-check-consistency
description: Cross-check consistency between code, documentation and tests — finds gaps, contradictions and stale content
disable-model-invocation: false
---

Cross-check that code, documentation and tests are consistent with each other. This goes beyond mechanical checks (the `test-docs` make target) — it verifies that the three layers tell the same story and that no claim goes unverified.

## Discovery

Do NOT rely on hardcoded file lists. Discover the current project structure:

1. **Code:** Find CLI scripts in `bin/`, server code (`*.mjs`), entrypoint, Lua filter, VS Code extension source
2. **Documentation:** Find all `README.md` files, API specs (`openapi.yaml` or similar), any tutorials or guides
3. **Tests:** Find all test files in `test/` and in extension test directories

If any expected artifact is missing or has been renamed, report that as a finding rather than silently skipping it.

## What to check

### 1. Documentation accuracy (Doku ↔ Code)
- Do prose descriptions match actual behavior?
- Are architecture descriptions still correct?
- Are examples correct and runnable with the current CLI syntax?
- Are there stale references to removed features, endpoints, or flags?

### 2. Documentation completeness (Code → Doku)
- Are all CLI options documented? Run the CLI with `--help` and compare.
- Are all API parameters documented? Cross-check against the API spec.
- Are all VS Code settings documented? Cross-check against `package.json`.
- Are all supported diagram types documented?
- Are there undocumented features or behaviors?

### 3. Test coverage of documented features (Doku → Tests)
- Every documented CLI option — is there a test that exercises it?
- Every documented API parameter — is there a test that exercises it?
- Every documented VS Code setting — is there a test for it?
- Every documented diagram type — is there a rendering test for it?
- Every documented error behavior — is there a test that verifies it?

### 4. Consistency across documents (Doku ↔ Doku)
- Do the project README and the API spec describe the same API?
- Do the project README and the VS Code extension README agree on how the server works?
- Are version numbers consistent across all files?

## How to perform the cross-check

1. Discover all relevant files (see Discovery above)
2. Read all documentation files
3. Read behavior-relevant parts of CLI scripts, server code, and entrypoint
4. Scan test files for what they assert (not implementation details)
5. Run the CLI with `--help` and compare against docs and tests
6. Cross-check API spec against README and test assertions
7. Cross-check VS Code `package.json` settings against README and tests
8. For each documented feature, grep for a corresponding test assertion

## Output

Report findings as a structured list:

- **Errors** — factually wrong content (must fix)
- **Stale** — references to removed features (must fix)
- **Untested** — documented features without test coverage (should fix)
- **Missing docs** — undocumented features (should fix)
- **Suggestions** — improvements to clarity or structure (nice to have)

For each finding, include the source file, the relevant content, and what needs to change.

After the cross-check, ask the user if they want you to apply fixes.
