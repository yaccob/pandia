---
name: test-all
description: Run the complete pre-commit test suite via make test-all
disable-model-invocation: false
---

Run the full pre-commit test suite:

```bash
make test-all
```

This runs all test levels defined in the Makefile's `test-all` target. Expect unit tests, integration tests, container tests, and extension tests. The exact composition may change — the Makefile is the source of truth.

Run ALL steps and collect all errors. Report a complete summary.

If all levels passed, write the session marker:

```bash
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) test-all passed" > /tmp/claude-test-all-passed.txt
```

If ANY level failed, do NOT write the marker.
