---
name: pr-review-feedback
description: Renders code-reviewing findings in a local web UX to collect per-finding human disposition and an explicit review stance, returning structured disposition JSON. Use whenever PR findings need human disposition before commenting or voting — after code-reviewing produces findings and before posting PR comments or setting an approve / request-changes stance.
---

# PR Review Feedback

Render plus collect only. Shows each finding for human disposition and returns a structured envelope. It never posts comments or sets a stance.

# Inputs

- **findings**: exact **code-reviewing** output array — `[{finding, location, type, severity}]` in that skill's `# Outputs` format
- **pr**: PR metadata for context and SHA-pinned links — `{url, number, head_sha, head_ref, base_ref}`

# Outputs

Structured envelope with index references, split verdict plus comment action, optional disagree reason, and tristate decision.

## Format

```json
{
  "pr": {"url": "string — PR URL", "head_sha": "string — reviewed commit SHA"},
  "dispositions": [
    {
      "index": "number — position in the input findings array",
      "verdict": "agree | disagree",
      "comment": "none | inline | general",
      "reason": "string — optional free text, only meaningful on disagree, logged not posted"
    }
  ],
  "review_decision": {"decision": "approve | request_changes | no_action", "note": "string — optional free text"}
}
```

Rules:

- Reference findings by array `index`, not copied text or generated IDs.
- `verdict`: `agree | disagree`; `comment`: `none | inline | general`.
- `reason`: optional free text, only meaningful on disagree, logged not posted.
- `review_decision.decision`: `approve | request_changes | no_action`, defaults to `no_action`.



## Example

```json
{
  "pr": {"url": "https://github.com/org/repo/pull/123", "head_sha": "abc123..."},
  "dispositions": [
    {"index": 0, "verdict": "agree", "comment": "inline", "reason": ""},
    {"index": 1, "verdict": "disagree", "comment": "none", "reason": "already handled in helper"}
  ],
  "review_decision": {"decision": "no_action", "note": ""}
}
```



# Collecting dispositions

Write the inputs to files, serve the viewer, wait for submit, then stop:

1. Write `findings.json` (findings array) and `pr.json` (PR metadata) to the workspace.
2. Run `python3 review_server.py --findings findings.json --pr pr.json --output feedback.json` from this skill's directory. It opens the viewer, re-renders from in-memory findings on refresh, and auto-saves drafts on change.
3. Poll `feedback.json` until `status` is `complete`, then kill the server and return the envelope (`pr`, `dispositions`, `review_decision`).
