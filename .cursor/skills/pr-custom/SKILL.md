---
name: pr-custom
description: Wraps the mattpocock-skills pr skill with team-specific PR description rules. Use whenever writing a PR body, in place of invoking pr directly.
---

# Skill: PR Custom

Load and follow the **pr** skill (from the mattpocock-skills plugin) to write the PR body. Then apply the additional rules below, which take precedence over **pr** where they conflict.

## Referencing Jira tickets

Do not reference another Jira ticket in the PR description, other than the current Jira ticket associated directly with the PR.

Ex: if we are calling this skill for a branch for Jira ticket RSP-216, then we should not mention any other Jira tickets other than RSP-216 in the PR.

Before finalizing the description, scan it for Jira keys (pattern like `ABC-123`) and remove any that are not the current ticket. This includes keys that appear in commit messages, code comments, or linked specs you are summarizing.
