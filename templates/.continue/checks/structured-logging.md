---
name: Structured Logging
description: No console.log — use structured winston logging
---

Check that all logging uses the project's structured winston logger, never `console.log`, `console.warn`, `console.error`, or `console.debug`.

**Required pattern:**

- Import the logger from `@messaging/backend-logger`
- Use `logger.info()`, `logger.warn()`, `logger.error()` with structured metadata
- Include relevant context (request IDs, entity IDs, operation names) in log metadata

**Violations:**

- Any use of `console.log`, `console.warn`, `console.error`, `console.debug`
- Using `console.info` or `console.trace`
- Logging without structured metadata (bare string messages with no context object)

**Why this matters:**

Structured logging enables searchability in Datadog, correlates logs with traces, and ensures consistent format across all Lambda functions. Console methods bypass log levels and structured formatting.
