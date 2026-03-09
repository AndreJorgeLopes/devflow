---
name: Handler Factory Usage
description: All Lambda handlers must use endpointHandlerFactory or sqsHandlerFactory
---

Check that every Lambda handler in the `application/` directory is created using the appropriate factory function.

**Required pattern:**

- HTTP endpoint handlers must use `endpointHandlerFactory` from `infrastructure/aws`
- SQS consumer handlers must use `sqsHandlerFactory` from `infrastructure/aws`

**Violations:**

- Exporting a raw async function as a handler without wrapping it in a factory
- Using `middy()` directly instead of going through the factory
- Creating custom handler wrappers that bypass the standard factories

**Why this matters:**

The handler factories apply required middleware (error handling, logging, tracing, input parsing) consistently. Bypassing them means missing critical cross-cutting concerns.
