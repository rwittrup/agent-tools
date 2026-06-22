---
name: linear-ticket-creating
description: Produces structured tickets in Linear to provide developers and agents the necessary information to understand and implement a feature or user story
---

# Skill: Linear Ticket Creating

## Purpose

Write a useful Linear ticket with enough information so that developers and agents can implement the feature, but without forcing a specific implementation.

---

Format of the ticket, along with word count limits for each section if applicable

```
# Problem - 50

# Acceptance Criteria

# Test Plan

## Validation command

# Out of scope

# Product Constraints - if necessary

# Approach - SEE BELOW
```

# Problem
- High-level summary of the problem and why this work is needed.
- Not what you're building — why it matters and what problem it solves.

# Acceptance Criteria
- BDD styling, with Given, When, then
  ```
  Given [context],
  When [action], 
  Then [outcome]
  ```
- Add as many as needed to fully cover the expected behavior

# Test Plan and Validation command
Numbered steps, each mapped to one or more acceptance criteria above.
Each step must be specific enough that an agent can execute it without ambiguity.
Example:
1. Run integration tests — covers AC1, AC2
2. Query DB for created record — covers AC3
3. Check Datadog logs for expected trace — covers AC4

## Example tools and tests to be consider as part of the validation:
- Unit tests
- Integration tests
- DB query
- Ruby script
- Other CLI tools - Datadog
- BASH scripts / commands, including things like CLI commands
- [others as relevant to this ticket]

## Available Tools
- `just` (target: `just validate-[component]`)
- Datadog MCP
- Direct DB access
- Ruby script execution
- [others as relevant to this ticket]

## Validation Command
- Should be one command a user or agent can run that fully executes the test plan
- It can run one or more tests
- It should be a code block, that a user can copy and paste into a terminal to run

# Out of scope
- explicit exclusions to prevent scope creep

# Product Constraints
- any special constraints to restrict the approach
- should be provided by a user - before specifying any constraints, ask the user to confirm - don't assume

# Approach
- The chosen approach in enough detail that an implementer can act without re-deriving the design.
- Include: key files to modify, interfaces to define or change, patterns to follow, anything non-obvious.

Within the `Approach` section, include more details depending on what part of the codebase is affected.

Example, for a story involving the call-handler and call-transcription services, ruby API, and frontend:

```
# Approach
## Call-handler and call-transcription - 50

## Ruby - 50

## Frontend - 50 
```