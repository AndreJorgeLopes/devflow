---
name: No Any Types
description: "No `any` types or type assertions"
---

Check that the code does not use the `any` type or unsafe type assertions.

**Violations:**

- Variables, parameters, or return types typed as `any`
- Using `as any` to silence type errors
- Using `@ts-ignore` or `@ts-expect-error` to suppress type checking
- Using non-null assertions (`!`) without clear justification
- Casting to an intermediate `unknown` then to a specific type (`as unknown as Foo`) to bypass type checking

**Acceptable exceptions:**

- Third-party library types that genuinely require `any` (should be wrapped in a typed adapter)
- Generic utility types where `any` is part of a constraint (e.g., `T extends Record<string, any>`) — but prefer `unknown` where possible
- Test mocks where partial implementations are typed with `Partial<T>` rather than `any`

**Why this matters:**

`any` disables TypeScript's type checker for that value and everything it flows into. It silently propagates, turning typed code into effectively untyped code. Using `unknown` with proper narrowing preserves safety.
