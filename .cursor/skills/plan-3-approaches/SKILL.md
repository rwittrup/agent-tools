---
name: plan-3-approaches
description: Generates three approaches to add new behavior—staff/architect, quick delivery, and wild card. Use when planning implementation options for a feature or Jira ticket.
---

# Plan 3 Approaches

Generate 3 approaches to add the new behavior. Skip conversational preamble ("Agreed, this one's trickier...", "Happy to break this down...") — go straight into the approaches.

If the request is missing details that would change the shape of the approaches, or implies two constraints that seem to conflict, ask at least one clarifying question before or alongside presenting the approaches, rather than guessing silently.

## Structure

Label each approach with its archetype so it's unambiguous which is which — don't rely on ordering alone:

# Approach 1 — Staff/Architect
Thoughtful, as if done by a staff engineer or architect with a deep understanding of the system. This can include refactorings, to make the code easier to change, so that the implementation ends up being less code.

Bias is simple, easy to support and grow. Prefer shaping the code, extracting new components, thinking about the overall design.
Example: refactor to define a new interface, existing code uses a base implementation, and then solve by creating a new implementation

# Approach 2 — Quick and Dirty
Not introducing any bugs or serious performance issues, but not necessarily considering the larger design of the system. As if done by a senior engineer, trying to get this delivered quickly, with the chance to clean it up later.

# Approach 3 — Wild Card
An interesting or novel approach, as if done by a really talented engineer with a broad range of experiences. Something that works, and works well, but may not be obvious to other engineers on the team.

## Within each approach

Use the same subsections, in the same order, across all three approaches — a reader comparing them shouldn't have to hunt for where the tradeoffs are in one and not the others:

- **Idea** — one or two sentences on the core move.
- **Shape** — the design, described at the level of components, not implementation steps. A reader should come away knowing what pieces exist and how they collaborate, not which hook or SDK call you'd reach for. For each component that's new, changed, or extracted, name it and give:
  - **Responsibility** — what it's for, in a phrase.
  - **Changes** — new / extends existing / modifies behavior of.
  - **Collaborators** — what it gets data from and what it sends data to (and roughly what data, when that's not obvious from the names).

  Skip implementation-level detail (specific hooks, SDK methods, state variables, loop mechanics) unless the ticket genuinely can't be understood without it. "A `DocumentsTable` component that owns sort/page state and refetches on change" is the right altitude; "`useState` for page/pageSize" is not.
- **Tradeoffs** — always a bulleted list, stated as objectively as possible. This is not the place to argue for or against the approach — just name what's true about it (cost, risk, what it sets up well, what it forecloses). Save your opinion about which approach is best for the Recommendation section.

If the change spans multiple applications or services (e.g. a Go service plus a Ruby API plus a frontend), break the Shape out per-application within each approach (e.g. `## Backend` / `## Frontend` subheadings, each listing that application's components) — and use the same per-application breakdown across all three approaches, not a different structure per approach.

Bake in safety by default rather than calling it out as a bonus: assume approaches shouldn't introduce regressions, should stay backwards-compatible in-flight, and should keep working if the applications involved get deployed at different times. Don't add a separate "regression-proofing" section — this is just a property every approach should have. Likewise, don't add a section mapping each approach back to the acceptance criteria — every approach should already satisfy them; if one genuinely can't, that's a signal to ask a clarifying question, not to document the gap.

## Recommendation

End with a `## Recommendation` section (not "a note on picking" or similar). The pick itself goes on its own line, by itself, so it's scannable at a glance — not folded into a sentence:

```
Recommended: Approach N
```

Then explain why in a sentence or two below it. If it's genuinely useful, note how to evolve from a faster approach into a more durable one later (e.g. "ship Approach 2 now, file a follow-up to migrate to Approach 1's shape once X lands") — but only when there's a real path, not as boilerplate.
