---
name: pr-formatting
description: Produces review-ready PR descriptions—Summary, Context, Changes, Validation (copied from the validation artifact) so reviewers can re-run verification independently. Use when opening draft PRs, Graphite stacks, or any PR where validation steps must not be omitted.
---

# Skill: PR Formatter

## Purpose
Produce PR descriptions that are easy to review, include full context, and always contain clear validation/acceptance steps.

---

## PR Description Template

```markdown
## Summary
One to three sentences. What does this PR do and why does it exist?
Assume the reviewer has not read the ticket. Give them enough to orient.

## Context
What problem does this solve? What was broken, missing, or needed?
If this is part of a stack, explain where it fits and what it depends on.

## Changes
A brief description of what was actually changed — not a file list, but a
plain-language summary of the meaningful changes. Group logically if needed.

- [change or area] — [brief explanation]
- [change or area] — [brief explanation]

## Validation
How was this verified? Copy the steps from the validation artifact.
A reviewer or future engineer should be able to re-run this independently.

### Steps
1. [Step] — [what it checks]
   ```
   just validate-call-handler
   ```
   Expected: all tests pass, no errors

2. [Step] — [what it checks]
   ```sql
   SELECT * FROM calls WHERE status = 'completed' LIMIT 5;
   ```
   Expected: records present with correct fields populated
```

---

## Rules

**Summary** — not a restatement of the ticket title. Write it for someone who opens the PR cold.

**Context** — this is the "why." If the context is obvious, keep it short. If there's a non-obvious constraint or root cause, explain it here.

**Changes** — avoid bullet lists of filenames. Group by concern and explain the intent. A reviewer should understand the shape of the change before looking at the diff.

**Validation** — always present. Never omit. Copy from the validation artifact — these should match exactly what the Validator ran. A PR without validation steps is incomplete.

---

## Frontend PRs
For frontend-only PRs, replace the Validation section with:

```markdown
## Validation

### Manual Testing Steps
1. [Navigate to / do X]
2. [What you should see]
3. [Edge case to exercise]
4. [What correct behavior looks like]

### Automated
- React unit tests: `npm test`
- Playwright: covered by CI on merge
```
