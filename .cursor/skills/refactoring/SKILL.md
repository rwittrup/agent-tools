---
name: refactoring
description: Improves code structure without behavior changes; requires test baseline, small steps, and behavioral equivalence. Use when extracting responsibilities, reducing complexity, renaming, introducing interfaces, or moving code across layers—never mixing bug fixes into the same commit as a refactor.
---

# Skill: Refactor

## Purpose
Improve the structure of existing code without changing its behavior. Every refactor must prove behavioral equivalence — through tests, not assertion.

---

## Rule Zero
A refactor commit contains no behavior changes. If you find a bug while refactoring, stop. Commit the refactor as-is, then address the bug in a separate commit with its own context.

---

## Process

### 1. Define the Scope
Before touching anything:
- What is being refactored? (file, function, package, interface)
- What is the stated goal? (extract responsibility, reduce complexity, improve naming, introduce interface, etc.)
- What is explicitly out of scope?

Write this down. Scope creep in refactors is how bugs get introduced.

### 2. Establish the Equivalence Baseline
Before changing any code, confirm that existing tests cover the behavior you're about to move:

```bash
# Go — check coverage on the target
go test ./internal/[package]/... -cover -v

# Ruby
bundle exec rspec spec/[path] --format documentation
```

If coverage is thin, write characterization tests first. These tests don't test what *should* happen — they test what *does* happen right now. They're your safety net.

### 3. Produce a Validation Artifact
Same as any other ticket. The artifact for a refactor is:
- The existing tests, confirming they pass before the refactor
- A just target that runs them: `just validate-refactor-[scope]`
- If adding characterization tests, include those too

Run it. Confirm green. This is your baseline.

### 4. Refactor in Small Steps
- One logical change per commit
- Run the validation artifact after each step
- If you break something, you know exactly which step did it

**Common patterns:**
- **Extract function** — pull a block into a named function with a clear responsibility
- **Extract interface** — define an interface for a concrete dependency, update call sites
- **Rename for clarity** — rename a function, variable, or type that's misleading
- **Flatten nesting** — invert conditionals, use early returns to reduce nesting depth
- **Move to correct layer** — relocate code that's in the wrong package or layer

### 5. Confirm Equivalence
After all steps:
```bash
just validate-refactor-[scope]
```
All tests must pass. No new tests should be needed if the behavior is truly unchanged.

---

## Commit Format for Refactors
Use the `refactor:` prefix in the subject:
```
refactor: Extract retry logic from ProcessCall into RetryHandler
```

Body should explain *why* the refactor improves things:
```
ProcessCall was handling call processing, retry scheduling, and
error classification — three distinct responsibilities. Extracting
RetryHandler makes each piece testable in isolation and removes
the need to mock the entire call flow to test retry behavior.
```

Also apply the **commit-formatting** skill for 50/72 wrapping and team conventions where they apply.

---

## When to Stop and Escalate
Stop and surface to the human if you find:
- A bug (don't fix it — flag it)
- An area with no test coverage that would be risky to move
- A dependency you didn't expect that changes the scope
- A change that would require modifying an interface used by multiple callers
