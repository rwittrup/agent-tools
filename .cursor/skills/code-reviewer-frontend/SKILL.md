---
name: code-reviewer-frontend
description: Findings-only UI review. Use when a diff touches React, TSX, SCSS, or frontend styling. Loads the product UI skills and emits JSON findings in the code-reviewing shape. Does not edit code.
---

# Code reviewer — frontend

Review a UI diff and return findings. Do not edit files. The rules live in the product skills below. This skill decides which of them apply and turns violations into findings.

## Skills to load

Load each of these by name when it is present in the repo under review. Skip any that are not present. Do not restate their rules here.

- **react-ui-implementation**
- **css-best-practices**
- **mcp-usage**
- **react-best-practices**
- **core-engineering-principles**
- **typescript-style**
- **javascript-style**
- **react-localization**
- **react-cleanup-patterns**

## Workflow

1. If the diff does not touch UI (`.tsx`, `.ts` components, `.scss`, styling), return an empty array.
2. Load the skills above that are present.
3. Review the diff against those skills. A missing product skill is not itself a finding.
4. Emit one finding per violation. High severity means the change breaks the design system, localization, or a stated frontend rule in a way a reviewer would send back. Low severity is drift worth fixing that does not block.

# Inputs

- **code**: the diff to review
- **branch**: the branch/ref being reviewed, and its base

# Outputs

A JSON array in the same shape **code-reviewing** produces. Use `type` of `styling`, `convention`, `design`, or `maintainability`.

```json
[
  {
    "finding": "string — the violation, specific enough to act on",
    "location": "string 'path/to/file.ext:line' or null",
    "type": "styling | convention | design | maintainability",
    "severity": "high | low"
  }
]
```
