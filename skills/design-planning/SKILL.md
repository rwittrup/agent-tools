---
name: design-planning
description: Produces three genuinely distinct design options with tradeoffs, complexity, reversibility, and a clear recommendation so a human can choose before planning or tickets. Use when exploring approaches for a problem; wait for human choice before handoff to ticket creation or implementation.
---

# Skill: Design

## Purpose
Produce clear, opinionated design options for a given problem so a human can make an informed choice. Used by the Planner before breaking work into tickets.

---

## Process

### 1. Understand the Problem
Before generating options, make sure you understand:
- What is the actual problem being solved? (not the proposed solution)
- What are the constraints? (performance, consistency, backward compatibility, timeline)
- What does the existing architecture look like in the affected area?
- What's the failure mode if this is done wrong?

If any of these are unclear, ask before proceeding.

### 2. Generate Three Approaches
Produce three meaningfully distinct options. Don't generate a good option and two strawmen — each approach should be genuinely viable. If only two real options exist, say so.

For each approach:

```markdown
### Option [N]: [Short Name]

**Summary**
What this approach does and how it solves the problem.

**Key Design Decisions**
The two or three choices that define this approach.

**Tradeoffs**
| | |
|---|---|
| ✅ | [Strength] |
| ✅ | [Strength] |
| ⚠️ | [Weakness or risk] |
| ⚠️ | [Weakness or risk] |

**Complexity**
Low / Medium / High — and why.

**Reversibility**
Easy / Hard to undo if wrong — and why.

**Best when**
The conditions under which this is the right choice.
```

### 3. Recommendation
After presenting all three, give a clear recommendation with your reasoning. Don't hedge — if one option is better, say so and explain why. The human makes the final call, but they should know what you'd pick.

```markdown
### Recommendation
Option [N] — [Short Name]

[2-3 sentences explaining why, referencing the specific constraints of this problem]
```

---

## Design Quality Bar

**Avoid:**
- Options that differ only in naming or minor implementation detail
- Approaches that ignore real constraints (e.g., "rewrite the whole service" when the timeline is 2 weeks)
- Tradeoffs that are all positive
- Vague summaries that don't explain the actual mechanism

**Aim for:**
- Options that represent genuinely different tradeoffs (e.g., simpler vs. more scalable, faster to ship vs. more maintainable)
- Tradeoffs that are honest — every approach has real weaknesses
- A recommendation you'd actually defend in a review

---

## Output
Present all three options and the recommendation in a single response. Wait for the human to choose before handing off to the Planner for ticket creation.
