---
name: pr-comment-handling
description: Triages and resolves PR review comments from engineers, agents, or Bugbot—validates whether the issue is real, assesses risk, and fixes non-negligible issues with TDD. Use when handling PR feedback, review threads, Bugbot findings, or when the user pastes a PR comment URL or suggestion to address.
---

# PR Comment Handling

## When to use

- User shares a PR comment URL, pasted review text, or Bugbot finding
- User asks to address, triage, or fix feedback on a pull request
- User wants to decide whether a review comment warrants a code change

## Inputs

Gather as much context as available:

1. **Comment text** — pasted directly or fetched from GitHub
2. **Location** — file, line, and diff hunk if present
3. **Author** — engineer, agent, or Bugbot (affects tone, not validity)
4. **PR context** — branch, related changes, linked ticket

### Fetching from GitHub

When given a PR comment URL like `https://github.com/org/repo/pull/123#discussion_r456`:

```bash
# Extract PR number and comment id from the URL, then:
gh api repos/{owner}/{repo}/pulls/{pr}/comments \
  --jq '.[] | select(.id == {comment_id}) | {body, path, line, diff_hunk, user: .user.login}'
```

For review comments on the PR overall (not inline), use the reviews or issue-comments endpoints as appropriate.

---

## Workflow

Copy this checklist and track progress:

```
- [ ] 1. Understand the comment
- [ ] 2. Validate — is the issue real?
- [ ] 3. Risk assessment
- [ ] 4. Decide: fix / defer / dismiss
- [ ] 5. (If fix) TDD implementation
- [ ] 6. Report outcome
```

### Step 1: Understand the comment

- Read the comment, diff hunk, and surrounding code
- Classify intent: correctness bug, error handling, edge case, style/nit, design suggestion, question, or off-topic
- For Bugbot comments: parse severity, description, and location markers; ignore Fix-in-Cursor/Web links and boilerplate

### Step 2: Validate — is the issue real?

Confirm or refute the claim with evidence:

- Trace the code path the comment describes
- Check whether the described state or failure mode can actually occur
- Look for existing tests that already cover or contradict the claim
- Distinguish **factual bugs** from **preferences** (naming, comment length, alternative designs)

**If not real:** stop the fix path. Explain why with specific code references. Offer a brief reply the author can post if useful.

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

### Step 4: Decide

| Outcome | When | Action |
|---------|------|--------|
| **Fix now** | Real issue + non-negligible risk | Proceed to Step 5 (TDD) |
| **Defer** | Real but negligible risk, or better as follow-up ticket | Explain tradeoff; suggest reply or ticket |
| **Dismiss** | Not a real issue | Explain evidence; suggest reply if helpful |

Do not implement a fix when risk is negligible unless the user explicitly overrides.

---

## Step 5: TDD fix (fix-now path only)

If this issue needs fixed, first write a test to validate the failure, TDD-style
- Run that test, see it fail
- Then make the necessary changes to get the test to pass - only write what is needed to make the tests pass
- Then run the test, and see it pass

Iterate as necessary if the test still fails

### TDD details

1. **Root cause first** — identify why the bug happens, not just the symptom
2. **Test the root cause** — write a test that fails because of that cause (prefer integration-style when cheap; see **testing-philosophy**)
3. **Red** — run the test; confirm it fails for the expected reason
4. **Green** — minimal production change to pass; follow **implementation-philosophy** (smallest correct diff)
5. **Refactor** — only if needed; do not expand scope
6. **Verify** — run related tests; ensure no regressions

Commit with **commit-formatting** when the user asks to commit.

---

## Step 6: Report outcome

Use this template:

```markdown
## PR comment triage

**Comment:** [one-line summary]
**Source:** [author / Bugbot]
**Location:** [file:line]

### Validation
[Real / Not real / Partially real] — [evidence]

### Risk
[Non-negligible / Negligible] — [why]

### Decision
[Fix now / Defer / Dismiss]

### Changes (if fixed)
- Test: [what was added]
- Fix: [minimal change summary]

### Suggested reply (if not fixing)
[Optional short comment for the PR thread]
```

---

## Examples

### Bugbot — real, fix now

**Comment:** `refetchFirstPage` uses `void refetch()` so refresh errors become unhandled rejections instead of reaching the error handler.

**Validation:** Real — `void` discards the promise; caller's `await onSuccess` cannot catch failures.

**Risk:** Non-negligible — failed refresh after delete is user-visible and bypasses existing error logging.

**Decision:** Fix now with TDD — test that refresh failure is caught/handled; then return or await `refetch()` appropriately.

### Engineer — real, defer

**Comment:** Block comment is unnecessarily long; consider `/deslop`.

**Validation:** Real preference, not a bug.

**Risk:** Negligible — style only, no runtime impact.

**Decision:** Defer — optional cleanup, not required for merge unless team policy says otherwise.

---

## Related skills

- **testing-philosophy** — TDD and integration-style tests
- **implementation-philosophy** — minimal, sustainable changes
- **commit-formatting** — commit messages after fixes
- **review-bugbot** — run Bugbot review (separate from addressing individual findings)
