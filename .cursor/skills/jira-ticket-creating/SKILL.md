---
name: jira-ticket-creating
description: Produces structured tickets in Jira to provide developers and agents the necessary information to understand and implement a feature or user story
---

# Skill: Jira Ticket Creating

## Purpose

Write a Jira ticket that carries everything an implementing agent needs, without prescribing the implementation.

The agent starts with a fresh context and has none of the planning conversation that produced the ticket, so the ticket has to carry it. Point to code locations rather than prescribing the implementation, so the agent isn't stuck with a stale path.

---

Format of the ticket, along with word count limits for each section if applicable

```
# Problem - 50
# Requirements
# Acceptance criteria
# Out-of-scope (if necessary)
# Glossary terms and relevant ADR's (if necessary)
# Settled decisions (if necessary)
```

Problem, Requirements, and Acceptance criteria are required for every ticket, no matter how small. The remaining sections are included only when they apply.

# Problem
- High-level summary of the problem and why this work is needed.
- Not what you're building — why it matters and what problem it solves.

# Requirements
- What the system must do, written as behaviors.
- Describe observable behavior, not implementation steps.

# Acceptance criteria
- Each criterion must be phrased so it can become a test: `/tdd` drives red-green from them and `/code-review` checks the diff against them.
- BDD styling, with Given, When, Then
  ```
  Given [context],
  When [action],
  Then [outcome]
  ```
- Add as many as needed to fully cover the requirements.

# Out-of-scope (if necessary)
- Explicit exclusions. These prevent most PR surprises.

# Glossary terms and relevant ADR's (if necessary)
- Domain terms from `GLOSSARY.md` the agent needs to read the ticket correctly.
- Pointers to relevant ADRs or files. Point to locations, don't paste or prescribe code.

# Settled decisions (if necessary)
- Decisions already made, so the agent doesn't re-litigate them.
- Only record decisions the user actually made. Before listing one, ask the user to confirm — don't assume.
