---
paths:
  - "**/test_*"
  - "**/tests/**"
  - "**/*_test.*"
  - "**/*.test.*"
  - "**/*.spec.*"
---

# Testing Standards

- Add unit tests for new public functions and branches. Use mocking for external API dependencies.
- Fix pre-existing test failures in a separate commit before proceeding with new work.
- When suppressing a warning with an inline ignore, add a justification comment explaining why.
