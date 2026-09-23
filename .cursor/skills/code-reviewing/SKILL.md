---
name: code-reviewing
description: Runs a parallel code review on any set of changes — a feature branch, staged/uncommitted local work, or a diff handed to it by an agent using a high-level directional gate, three independent domain reviews (behavioral, quality, polish) fanned out in parallel, and a high-signal confidence filter, then aggregates every JSON finding into one deduped array. Takes code+branch, returns findings — it does not decide what to do with them.
---

# Code reviewing (parallel pipeline)

This is the core review engine. It doesn't know or care whether the change under review is going to become a GitHub PR, is a teammate's branch, or is your own staged changes you want checked before you commit — it just reviews a diff against its stated intent and returns findings. It does not decide what to do with those findings, get human sign-off, or take any action (posting comments, approving, blocking promotion) — that is for whatever **agent** invokes it.

## Component skills

Each of these is its own skill with a uniform input contract (code + branch) and a uniform JSON output contract (an array of findings — see each skill's own `SKILL.md` for its `# Inputs` / `# Outputs` sections):

1. **code-reviewer-high-level** — directional gate, runs first alone.
2. **code-reviewer-behavioral**, **code-reviewer-quality**, **code-reviewer-polish** — three independent domain reviews, run **in parallel** once high-level clears. None of them read each other's output or high-level's — every skill gets the same code+branch input directly.
3. **code-reviewer-validator** — confidence filter, runs on the pooled `severity: "high"` candidates from the other four.



## Step 0: Establish what "the change" is

Figure out what diff and what intent you're reviewing before anything else. This varies by how the skill was invoked:

- **Invoked directly by a user** ("review my branch," "check my staged changes before I open a PR," "review the diff between this branch and main"): work out the right `git diff` yourself — `git diff` (unstaged), `git diff --staged`, or `git diff <base>...<head>` for a branch comparison. Ask the user only if it's genuinely ambiguous which comparison they mean.
- **Invoked by an agent** that already gathered a diff and description: use exactly what was handed to you — don't re-derive it.

For **intent** (what problem this solves, why): use whatever is available — a PR description, a ticket, commit messages on the branch, or the user's own one- or two-line explanation. If none of that exists and it's not obvious from the diff itself, ask the user for a short description rather than guessing.

This diff, plus the branch/base refs, is the **code + branch** input every component skill below receives — gather it once here, not five times.

## Flow

1. **High-level pass (gate)** — Invoke the **code-reviewer-high-level** skill with the code+branch input. Inspect its JSON output: if **any** finding has `"severity": "high"`, stop — surface those findings to the user before deeper passes, and resume only after realignment. If every finding (or there are none) is `"severity": "low"`, proceed, carrying those findings into the final aggregate.
2. **Parallel domain passes** — Once high-level clears, run **code-reviewer-behavioral**, **code-reviewer-quality**, and **code-reviewer-polish** together, in parallel. Since these are skills (not a registered agent type), get real parallelism by launching three subagents (e.g. `general-purpose`) in a single message, one per skill — instruct each subagent to invoke that specific skill by name via the Skill tool, hand it the same code+branch input, and return its raw JSON findings array. Do not chain their outputs into each other — every skill reviews the same material independently, off the same input.
3. **Pool high-severity candidates** — Collect every finding with `"severity": "high"` across all four passes (high-level's low-severity findings don't need re-checking, but include any high-level finding that didn't trigger the stop in step 1 — there shouldn't be any, since any high-level high-severity finding stops the pipeline — so in practice this pool comes from behavioral/quality/polish). Leave `"severity": "low"` findings aside — they skip the confidence filter and go straight into the final aggregate.
4. **Confidence filter** — Invoke the **code-reviewer-validator** skill with the code+branch input plus the pooled high-severity candidates from step 3. It returns the same findings, each either kept at high severity, downgraded to low, or dropped.
5. **Aggregate** — Merge into one deduped JSON array: the validator's output, plus every `"severity": "low"` finding from every pass (high-level included). Two findings from different passes describing the same underlying issue (e.g. a deploy-coupling note from high-level and a related bug from behavioral) should be merged into one entry rather than listed twice — prefer the more specific/actionable wording.



# Inputs

- **code**: the diff to review — gathered in Step 0, either derived from git yourself or handed to you by the caller
- **branch**: the branch/ref being reviewed, and its base



# Outputs

A summary of findings, as JSON — the aggregate from Step 5 above, in the exact same format each `code-reviewer-*` skill produces. This is the complete output of this skill: it's structured and file-writable so it's easy to eval, diff against a previous run, or benchmark. Anything beyond this array (posting comments, approve/reject stances, prose framing for a human, deciding which findings to act on) is the job of whatever agent invoked this skill, not this skill itself.

## Format

```json
[
  {
    "finding": "string — the issue or observation, specific enough to act on",
    "location": "string 'path/to/file.ext:line' or 'path/to/file.ext:start-end', or null if not tied to a specific line",
    "type": "direction | scope | deploy-coupling | design | correctness | testing | readability | maintainability | convention | styling",
    "severity": "high | low"
  }
]
```



## Example

```json
[
  {
    "finding": "The ActiveRecord transaction wrapping an external S3 delete call has no comment explaining the rollback-on-failure intent — a future reader could 'fix' this by moving the S3 call out, silently breaking the rollback. Checked this repo's AGENTS.md/CLAUDE.md files: no documented rule requires such comments, so this stays low severity rather than blocking.",
    "location": "app/services/delete_document.rb:24-27",
    "type": "maintainability",
    "severity": "low"
  },
  {
    "finding": "Two same-filename uploads racing the unique index can leave S3 bytes attributed to the wrong uploader with no checksum or detection. This is explicitly documented as an accepted tradeoff in the PR's own architecture doc, not a hidden defect, but only in a markdown file — worth a one-line callout in the PR description itself.",
    "location": null,
    "type": "design",
    "severity": "low"
  }
]
```
