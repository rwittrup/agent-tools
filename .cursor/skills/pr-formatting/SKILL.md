---
name: pr-formatting
description: Produces review-ready PR descriptions—Summary, Context, Changes, Validation so reviewers can re-run verification independently. Use when opening draft PRs, Graphite stacks, or any PR where validation steps must not be omitted.
---

# Skill: PR Formatter

## Purpose
Produce PR descriptions that are easy to review, include full context, and always contain clear validation/acceptance steps.

---

## PR Format 
```
# Summary
# Context
# Changes
# Acceptance
```

### Summary
- Not a restatement of the ticket title
- Write it for someone who opens the PR cold.
- One to three sentences. What does this PR do and why does it exist?
- Assume the reviewer has not read the ticket. Give them enough to orient.

## Context
- This is the "why."
- If the context is obvious, keep it short.
- If there's a non-obvious constraint or root cause, explain it here.
- What problem does this solve? What was broken, missing, or needed? 

## Changes
- Avoid bullet lists of filenames
- Group by concern and explain the intent
- Group by core components and responsibilities
- A reviewer should understand the shape of the change before looking at the diff
- A brief description of what was actually changed, a plain-language summary of the meaningful changes.

## Acceptance
- Always present. Never omit. A PR without acceptance steps is incomplete.
- Steps needed to accept the change
- This could consist of, but is not limited to:
  - actions to perform in the UI - especially useful for frontend stories
  - tests to run - unit, integration, e2e. If providing these, make sure to include the exact snippet of code for the reviewer to run
  - database queries
  - log queries (Datadog)

Examples:
````
1. [what it checks]
   ```
   just validate-call-handler
   ```
   Expected: all tests pass, no errors

2. [what it checks]
   ```
   SELECT * FROM calls WHERE status = 'completed' LIMIT 5;
   ```
   Expected: records present with correct fields populated
````