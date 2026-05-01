---
name: commit-formatting
description: Produces well-formed git commit messages—50/72 rule, imperative subject, body explaining what and why (not how). Use when committing, drafting messages for review, or pairing with refactor commits; align with team policies in AGENTS.md when they add constraints beyond this template.
---

# Skill: Commit Formatter

## Purpose
Produce well-formed git commit messages that communicate what changed and why — not how.

---

## The 50/72 Rule

**Subject line:** 50 characters max
- Imperative mood: "Add", "Fix", "Remove", "Update" — not "Added" or "Adding"
- No period at the end
- Capitalize the first word
- No scope prefix required, but use one if it helps clarity (e.g., `call-handler: Fix timeout on dropped calls`)

**Body:** 72 characters per line max
- Blank line between subject and body
- Explain **what** changed and **why** — not how (the diff shows how)
- Wrap at 72 characters — hard wrap, not soft
- **ANET ticket** line appears in the body **before** any **signature** (e.g. `Signed-off-by`, `Co-authored-by`, `Made-with:`) as **plain text**: `ANET-1234 - {Linear title}` (see [ANET ticket in the body](#anet-ticket-in-the-body-plain-text))

---

## What to Write

**Good subject lines:**
```
Fix call handler timeout on dropped connections
Add ruby-api endpoint for call transcription status
Remove deprecated legacy webhook handler
Update integration test to cover concurrent sessions
```

**Bad subject lines:**
```
fix bug                          # too vague
Fixed the timeout issue in the call handler service  # too long, past tense
WIP                              # not a commit message
Changes per review               # meaningless
```

**Good body:**
```
Calls were silently timing out when the remote party dropped
without sending a FIN packet. The handler was relying on the
TCP stack to surface this, but our infrastructure has a 30s
keepalive that masked it.

Added explicit read deadline to surface the error earlier and
allow the retry logic to kick in correctly.
```

**Bad body:**
```
Changed the timeout value from 0 to 30 and added error handling
in the read loop to catch the error and return it.
```
(This describes how, not why.)

---

## When There's No Meaningful Body
Not every commit needs a body. Single-purpose changes are fine with just a subject:
```
Remove unused import in call_handler.go
```

Use a body when:
- The reason for the change isn't obvious from the subject
- There's important context (a bug root cause, a constraint, a tradeoff)
- You're making a non-obvious decision that future-you will question

---

## Anti-patterns (agents and stacked commits)

These show up when the model treats the commit message as a mini PR
description. Avoid them.

- **Ticket in the subject only.** Do not use `[ANET-1234] …` in the
  subject as a substitute for the body line `ANET-1234 - {title}`.
  Bracket IDs burn the 50-character subject budget and skip the
  autolinked body format this skill requires before trailers.
- **Inventory bodies.** Do not list every new file, export, styled
  component, prop, or spec example. Do not paste symbol lists or
  “coverage includes …” catalogs. The diff shows names; the commit
  should say *why* the change exists and *what* outcome matters.
- **How-to walkthroughs.** Step-by-step file edits, dependency graphs,
  and “then we re-export X so imports keep working” belong in the PR
  (if anywhere), not in the commit body.
- **Unbounded length.** If the wrapped body is more than a few short
  paragraphs, split the work into another commit or move detail to the
  PR description.

**Refactors and extractions:** One or two sentences of intent is
enough (e.g. shared model for reuse across surfaces; behavior
unchanged). Skip re-export compatibility laundry lists unless a human
explicitly asked for them in the message.

---

## Quick checklist before `git commit`

- Subject ≤ 50 characters, imperative, no trailing period.
- Body lines ≤ 72 characters, hard-wrapped.
- Body explains what/why, not file-by-file how.
- Exactly one `ANET-1234 - {Linear title}` line (from `get_issue`) after
  the narrative and before any trailer (`Made-with:`, `Co-authored-by:`,
  etc.).
- No long inventories: if you are typing lists of symbols, stop.

---

## Applying This Skill
When committing, produce the full commit message before running `git commit`. Present it for review if the change is significant. For routine commits, apply the rules and proceed.

## ANET ticket in the body (plain text)

Place the ticket **in the body**, **after** the descriptive lines and **before** any **signature** block (Git trailers such as `Signed-off-by:` or `Co-authored-by:`, or footers like `Made-with:`).

This repo’s GitHub is integrated with Linear: the issue id in the commit body is **autolinked**. You do **not** need markdown links, raw URLs, or HTML—use a single plain-text line.

**Shape:** `{identifier} - {title}`

Use **`identifier`** and **`title`** from Linear **`get_issue`** (same wording as the ticket title).

**Example:**

```
ANET-2421 - Developers and product can review logs for Deepgram language detect responses
```

**Example full message:**

```
Adds logging for Deepgram response

Log parse latency from the websocket payload. Warn when the
stream drops mid-utterance.

ANET-2421 - Developers and product can review logs for Deepgram language detect responses
```
