---
name: Joi Input Validation
description: All inputs must be validated with Joi schemas
---

Check that all external inputs are validated using Joi schemas before being used in business logic.

**Required pattern:**

- API request bodies validated with a Joi schema
- SQS message payloads validated with a Joi schema
- Path parameters and query strings validated with a Joi schema
- Validation happens at the handler/entry-point level, not deep in business logic

**Violations:**

- Handlers that use request body properties without prior Joi validation
- Trusting `event.body` or `event.queryStringParameters` without validation
- Using TypeScript type assertions (`as SomeType`) as a substitute for runtime validation
- Inline validation logic (manual `if` checks) instead of declarative Joi schemas

**Why this matters:**

Joi schemas provide runtime type safety, descriptive error messages, and documentation of expected input shapes. TypeScript types are erased at runtime and provide no protection against malformed input.
