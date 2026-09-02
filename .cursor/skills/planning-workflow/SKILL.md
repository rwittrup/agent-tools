---
name: planning-workflow
description: Defines commit and delivery workflow for implementation—small commits, no broken states, PR-ready backwards-compatible changes, LaunchDarkly toggles. Use when implementing features or following the planning workflow.
---

# Planning Workflow

Workflow:
- Complete the work in small, well-defined commits using /commit-formatting
- No commit should leave the app in a broken state
- Each commit should be able to be converted to a PR, to make the review process easier by frequent small commits merged into dev and prod. This means all work needs to be backwards compatible. A common approach is to use LaunchDarkly, and gate new work and features behind a toggle.
