---
name: pr-comment-handling
description: Triages PR review comments from engineers, agents, or Bugbot—validates whether the issue is real, assesses risk, asks clarifying questions, lets the user decide fix/defer/dismiss, fixes confirmed bugs with TDD (failing test first), and drafts short replies and tracking items. Use when handling PR feedback, review threads, Bugbot findings, or when the user pastes one or more PR comment URLs to review or triage.
---

# PR Comment Handling

The user owns the decision. This skill investigates, recommends, and then waits for the user's disposition before changing code, replying on GitHub, or touching Jira.

## When to use

- User shares one or more PR comment URLs, pasted review text, or Bugbot findings
- User asks to review, triage, address, or fix feedback on a pull request
- User wants to know whether a comment is a real concern, or whether recent commits already address it

## Inputs

Gather as much context as available:

1. **Comment text** — pasted directly or fetched from GitHub (one or many)
2. **Location** — file, line, and diff hunk if present
3. **Author** — engineer, agent, or Bugbot (affects tone, not validity)
4. **PR context** — PR number, branch, related changes, linked Jira ticket. Use what the user provides; otherwise derive from the PR and branch name. Ask only if it affects the decision.

### Fetching from GitHub

For a URL like `https://github.com/org/repo/pull/123#discussion_r456` (or `/changes#r456`):

```bash
# Extract PR number and comment id from the URL, then:
gh api repos/{owner}/{repo}/pulls/{pr}/comments \
  --jq '.[] | select(.id == {comment_id}) | {body, path, line, diff_hunk, user: .user.login}'
```

For review comments on the PR overall (not inline), use the reviews or issue-comments endpoints as appropriate.

### Multiple comments or PRs

Triage each comment independently, then present results together, grouped by PR. Do not merge findings across comments.

---

## Workflow

Copy this checklist and track progress:

```
- [ ] 1. Understand the comment
- [ ] 2. Validate — is the issue real?
- [ ] 3. Risk assessment
- [ ] 4. Recommend + ask questions → STOP for user decision
- [ ] 5. (If fix) TDD implementation
- [ ] 6. Disposition: replies, tracking items, push
- [ ] 7. Report outcome
```

### Step 1: Understand the comment

- Read the comment, diff hunk, and surrounding code
- Classify intent: correctness bug, error handling, edge case, style/nit, design suggestion, question, or off-topic
- For Bugbot comments: parse severity, description, and location markers; ignore Fix-in-Cursor/Web links and boilerplate
- If the user asks whether the comment is already addressed, check commits on the branch since the comment was posted

### Step 2: Validate — is the issue real?

Confirm or refute the claim with evidence:

- Trace the code path the comment describes
- Check whether the described state or failure mode can actually occur
- Look for existing tests that already cover or contradict the claim
- Distinguish **factual bugs** from **preferences** (naming, comment length, alternative designs)
- Identify the **root cause**, not just the symptom

**If not real:** say so with specific code references.

### Step 3: Risk assessment

Score the issue when it is real (or plausibly real):

| Factor | Higher risk | Lower risk |
|--------|-------------|------------|
| Reviewer signal | "Must fix", "blocking", pre-merge requirement | Nit, optional, "consider" |
| Failure mode | Data loss, crash, security, silent wrong behavior | Cosmetic, unlikely race, theoretical state |
| Likelihood | Common path, production-reachable | Requires impossible or deprecated state |
| Blast radius | Core flow, many users | Isolated UI, dev-only |

**Negligible risk** examples: stylistic nits, comments the team doesn't require, edge cases that cannot occur in production given current invariants.

**Non-negligible risk** examples: unhandled rejections, missing error handling on user-facing flows, logic bugs on common paths, issues a reviewer marked as required before merge.

### Step 4: Recommend, ask, and stop

Present for each comment: finding, root cause, validation, risk, and a **recommended** outcome:

| Outcome | When |
|---------|------|
| **Fix now** | Real issue + non-negligible risk |
| **Defer** | Real but negligible risk, or better as a follow-up ticket |
| **Dismiss** | Not a real issue |

**Ask clarifying questions** whenever the answer could change severity or the decision (production reachability, intended invariants, whether a later PR in the stack covers it). Do not guess at risk the user can resolve in one sentence.

If the user asks for options (e.g. "propose 3 fixes"), give distinct approaches with tradeoffs, and answer follow-up probes about them before proceeding.

**Stop here.** Do not edit code, post replies, or create tickets until the user states a disposition per comment (e.g. "Comment 1: defer", "go with option 3", "only reply to X's comment"). The recommendation does not authorize action. If the user asked for a plan ("if significant, create a plan to fix"), produce the plan at this step and still wait.

---

## Step 5: TDD fix (user chose fix, or confirmed latent bug)

A confirmed latent bug must be proven fixed by a test, not by inspection. Always in this order:

1. **Write a failing unit test** that reproduces the bug at its root cause (prefer integration-style when cheap; see **testing-philosophy**)
2. **Run it and see it fail**, and confirm it fails for the expected reason, not a setup error
3. **Make the fix** — minimal production change, only what is needed to pass; follow **implementation-philosophy**
4. **Run it again and see it pass** — this is the validation that the bug is fixed
5. **Refactor** only if needed; do not expand scope
6. **Run related tests** to check for regressions

Iterate if the test still fails. If the bug truly cannot be reproduced in a test, say so and explain how it was validated instead.

When the user asks for one fix per comment, use one commit per fix. Commit with **commit-formatting** when the user asks to commit; push only when asked.

---

## Step 6: Disposition

Carry out only what the user requested, per comment.

### Replies on the PR thread

- **Keep every reply to 50 words or fewer.** No exceptions unless the user sets a different limit.
- Fixed: one or two sentences on what was implemented.
- Deferred: why it is being deferred, and where it is tracked (ticket key).
- Dismissed: the evidence in one or two sentences.
- Reply only on the threads the user names.
- When posting several comments, or when the user asks, **preview first** as a table (`PR #` | `Comment`) and wait for approval before posting. A reply on a Bugbot comment is a thread reply; a "general comment on the PR" is a top-level comment, not a line comment. Use whichever the user specifies.

### Tracking items (deferred work)

- If the user asks, add a comment to the named Jira tickets noting what to account for, and/or create a ticket in the named project with the named status (e.g. backlog).
- Do not create or comment on Jira items the user did not name.

### Push

Push only when the user says to, normally together with posting replies.

---

## Step 7: Report outcome

Use this template per comment; group by PR when there are several:

```markdown
## PR comment triage

**PR:** [#number]
**Comment:** [one-line summary]
**Source:** [author / Bugbot]
**Location:** [file:line]

### Validation
[Real / Not real / Partially real / Already addressed] — [evidence]

### Root cause
[why it happens]

### Risk
[Non-negligible / Negligible] — [why]

### Recommendation
[Fix now / Defer / Dismiss] — [one line]

### Questions
[Anything that would change the recommendation, or "none"]

### Done (after user disposition)
- Test: [failing test added, failed for expected reason, now passes]
- Fix: [minimal change summary]
- Reply: [posted text, ≤50 words]
- Tracking: [ticket keys commented on / created]
```

Omit "Done" items that did not happen.

---

## Examples

### Bugbot — real, recommend fix

**Comment:** `refetchFirstPage` uses `void refetch()` so refresh errors become unhandled rejections instead of reaching the error handler.

**Validation:** Real — `void` discards the promise; caller's `await onSuccess` cannot catch failures.

**Risk:** Non-negligible — failed refresh after delete is user-visible and bypasses existing error logging.

**Recommendation:** Fix now. After the user agrees: failing test that a refresh failure reaches the handler (red), return/await `refetch()` (green), test passes.

### Bugbot — real, user defers

**Comment:** Beat coordinates are not recomputed when only the polygon changes.

**Recommendation:** Defer — rare path, covered by a later ticket in the stack.

**User:** "defer; reply in under 50 words and comment on RSP-187."

**Reply (≤50 words):** "Valid, but only reachable when a beat polygon is edited in place, which no current flow does. Deferring; tracked in RSP-187 so the recompute is handled with the assignment-change work."

### Engineer — real preference, defer

**Comment:** Block comment is unnecessarily long.

**Validation:** Real preference, not a bug. **Risk:** Negligible. **Recommendation:** Defer or fix at the user's call.

---

## Related skills

- **testing-philosophy** — TDD and integration-style tests
- **implementation-philosophy** — minimal, sustainable changes
- **commit-formatting** — commit messages after fixes
- **review-bugbot** — run Bugbot review (separate from addressing individual findings)
