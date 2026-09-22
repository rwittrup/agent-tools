---
name: feature-refining
description: Refines a rough idea or existing Jira ticket into a fully defined feature spec as markdown. Runs two question phases (5 high-level, then 5 deeper), drafts after phase 1, finalizes after phase 2. Use before planning or jira-ticket-creating when requirements are vague or incomplete.
---

# Feature refining

Turn a rough idea or an existing Jira ticket into a locked feature spec. Output is a markdown file the software factory can use as `Job.spec`, or that **jira-ticket-creating** can paste into Jira. This skill does not create or update Jira issues.

## Inputs

- A rough idea, problem statement, or link/key to an existing Jira ticket
- Optional: codebase context, affected components, prior discussion

When a Jira ticket is provided, read it first. Treat its content as draft material, not a finished spec. Gaps and ambiguity are why this skill runs.

## Workflow overview

```
Phase 1: ask 5 high-level questions → wait for answers → first-pass markdown
Phase 2: ask 5 deeper questions → wait for answers → final markdown file
```

Do not skip phases. Do not write the final file until phase 2 answers are in. Do not ask all 10 questions at once.

---



## Phase 1 — high-level review

Ask **exactly 5 questions** in one message. Number them. Wait for all five answers before continuing.

Tailor each question to the input. Cover these five themes — one question per theme:

1. **Problem and why** — What problem does this solve, and for whom? What happens today without it?
2. **Desired outcome** — What does "done" look like from the user's perspective? One concrete success scenario.
3. **Scope boundary (in)** — What is explicitly included in this feature? Which surfaces, roles, or flows?
4. **Scope boundary (out)** — What related work is *not* part of this feature, even if it sounds adjacent?
5. **Affected systems** — Which parts of the stack are involved (e.g. frontend, ruby-api, call-handler)? Any known constraints or dependencies?

After the human answers, confirm your understanding in two or three sentences, then produce a **first-pass draft** using the output format below. Label it clearly as a draft. Gaps and assumptions you still have should be noted inline or in a short "Open questions" block after the draft — do not hide uncertainty.

Stop. Do not start phase 2 in the same turn.

---



## Phase 2 — deeper finalizing

Ask **exactly 5 more questions** in one message. Number them 6–10. Wait for all five answers before writing the final file.

Tailor each question to the draft and phase 1 answers. Cover these themes — one question per theme:

1. **Edge case or failure mode** — What should happen when input is invalid, empty, concurrent, or partially failed?
2. **Edge case or boundary** — What happens at limits (permissions, empty states, first use, duplicates, timeouts)?
3. **Scope confirmation** — Restate the boundary; ask the human to confirm or correct one thing that still feels fuzzy.
4. **Out of scope confirmation** — Name something tempting to include but excluded; ask the human to confirm or add exclusions.
5. **Design ideas (always last, verbatim prompt):** "Are there any ideas or suggestions for the design?" — open-ended, not required. "No" and "n/a" are valid responses.

After the human answers, write the **final markdown file** using all ten answers. Resolve or drop the "Open questions" from the first pass unless something remains genuinely unresolved — then list it under Product Constraints or Out of scope, not as a dangling question.

---



## Output format

Write the final artifact as a markdown file. Default path: `feature-spec.md` in the workspace root unless the human specifies another path.

Use this structure exactly:

```markdown
# Problem

<High-level summary of the problem and why this work is needed. 50 words max.>

# Acceptance Criteria

<BDD Given / When / Then scenarios. One block per scenario.>

Given [context],
When [action],
Then [outcome]

# Test Plan

<Numbered steps mapped to acceptance criteria.>

# Out of scope

<Explicit exclusions.>

# Product Constraints

<Constraints only when necessary; omit section body if none.>

# Approaches to consider

<Brief notes on 2–3 directions worth exploring — not a chosen approach. Enough for a planner to generate real options. Do not pick one.>
```



### Section rules

**Problem**

- Why it matters, not how to build it.
- Hard limit: 50 words.

**Acceptance Criteria**

- BDD Given / When / Then for every behavior the feature must have.
- Observable outcomes only — not implementation steps.
- Add scenarios until the feature is fully covered, including error and permission cases surfaced in phase 2.

**Test Plan**

- Numbered steps. Each step names which AC it covers (e.g. "covers AC2, AC4").
- **Unit tests** — include for almost every AC that can be tested in isolation.
- **Integration tests** — include when they are not prohibitively expensive and they prove cross-layer behavior.
- **E2E / acceptance** — include only when the human explicitly requested end-to-end or acceptance-level verification, or when behavior cannot be proven any other way.
- Do not invent a validation command here. **jira-ticket-creating** adds that when the spec is turned into a Jira ticket.

**Out of scope**

- Explicit exclusions to prevent scope creep. Pull from phase 1 question 4 and phase 2 question 9.

**Product Constraints**

- Include only when the human confirmed constraints, or when a hard technical/product limit came out of the Q&A.
- Do not invent constraints. If none, keep the heading and write `None.`

**Approaches to consider**

- Short bullets or mini-summaries of 2–3 viable directions — not a final choice.
- Incorporate the human's answer to question 10 when they provided ideas; otherwise note standard options implied by the spec.
- This section replaces **jira-ticket-creating**'s `# Approach` until a planner or human picks one.

---

## Anti-patterns

- Do not ask all 10 questions in one message.
- Do not write the final file after phase 1 only.
- Do not choose an approach in **Approaches to consider**.
- Do not add implementation detail (file paths, class names, hooks) unless the human supplied it in the Q&A.
- Do not create or update Jira from this skill.

