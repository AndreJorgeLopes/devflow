---
name: Error Handling
description: Proper error handling with domain error classes, no bare try/catch with generic Error
---

Check that error handling uses domain-specific error classes and follows project conventions.

**Required pattern:**

- Throw domain error classes defined in `domain/` (not generic `Error`)
- Catch blocks should handle specific error types, not catch-all
- Error context (entity IDs, operation, input summary) must be preserved
- Let the `errorFilterMiddleware` handle translation to HTTP responses — handlers should not manually set status codes for errors

**Violations:**

- `throw new Error("something went wrong")` — use a domain error class instead
- Bare `catch (e) { throw e }` — pointless re-throw, remove the try/catch
- `catch (e) { return { statusCode: 500 } }` — swallowing errors, let middleware handle it
- Catching errors only to log and re-throw without adding context
- Empty catch blocks that silently swallow errors

**Acceptable patterns:**

- Catching a specific error type to wrap it in a domain error with additional context
- Catching at a boundary (handler level) to ensure cleanup (close connections, release locks)
- Using `finally` for resource cleanup

**Why this matters:**

Domain error classes carry semantic meaning (NotFound, ValidationError, Conflict) that the error middleware translates into correct HTTP responses. Generic errors lose this context and result in opaque 500s.
