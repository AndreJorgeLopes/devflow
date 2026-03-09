---
description: [devflow v0.1.0] Retain a new learning, discovery, or hard-won insight into Hindsight so it's available in future sessions.
---

You need to retain a new learning into long-term memory via Hindsight.

## Steps

1. **Parse the learning** from the arguments below. If the user provided a brief note, expand it into a well-structured memory. If no arguments are provided, ask the user what they learned.

2. **Classify the learning** into one of these categories:
   - **Mental Model** — a reusable pattern or architectural understanding
   - **Hard Rule** — a constraint that must always be followed
   - **Gotcha** — a non-obvious pitfall or edge case
   - **Decision** — a choice made with specific rationale
   - **Technique** — a specific approach or method that works well
   - **Discovery** — a new finding about a tool, library, or system

3. **Structure the memory** with these fields:
   - **Title**: A concise, searchable title (max 10 words)
   - **Category**: One of the categories above
   - **Content**: The full learning, written clearly so it's useful out of context
   - **Context**: What project/area/file this relates to
   - **Why it matters**: One sentence on why this is worth remembering

4. **Store the memory** using the `hindsight_retain` MCP tool. Pass the structured content as the memory payload.

5. **Confirm** to the user what was retained, showing the title and category.

## Example

If the user says: "TypeORM migrations need to be added to migrate.ts manually"

You would retain:

- **Title**: "TypeORM migrations must be registered in migrate.ts"
- **Category**: Hard Rule
- **Content**: "After generating a new TypeORM migration, you must manually import it and add it to the migrations array in migrate.ts. The migration won't run automatically just by existing in the migrations directory."
- **Context**: Database migrations, TypeORM, infrastructure/database
- **Why it matters**: Forgetting this step causes silent migration failures in deployment.

$ARGUMENTS
