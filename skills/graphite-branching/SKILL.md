---
name: graphite-branching
description: Create Graphite branches for Ryan's work using the rwittrup/LINEAR-TICKET-description naming convention and the gt CLI. Use when starting work on a Linear ticket, creating a branch from trunk, or setting up multiple parallel trunk branches for separate components (e.g. backend and frontend) during planning. Always include the Linear ticket in the branch name. Pair with the graphite skill for stacks, submit, restack, and troubleshooting.
---

# Graphite Branching (rwittrup)

Create Graphite branches for Ryan Wittrup's work.

## Use This Skill vs the `graphite` Skill

| Use **`graphite-branching`** (this file) | Use **`graphite`** (`.agent/skills/graphite/SKILL.md`) |
|------------------------------------------|--------------------------------------------------------|
| Branch name format `rwittrup/TICKET-desc` | Navigating the stack (`gt up`, `gt down`, `gt top`, `gt bottom`) |
| Creating branches from `main` (`gt create`) | Creating a stacked PR sequence after the first branch |
| Multi-trunk vs stacked branching decisions | Untracked-branch workflow (`gt branch info`, re-parent, restack) |
| `gt track -p main` for naming/setup | `gt modify`, `gt move`, `gt rename`, reset/re-stack commits |
| Quick verification with `gt ls` | `gt submit`, PR titles via `gh pr edit`, validation before submit |
| | `gt restack`, surgical `git rebase`, troubleshooting, `gt delete` |

**Rule:** After branches exist, follow **`graphite`** for everything else (submitting, modifying the stack, rebasing, CI-safe PR titles). Do not duplicate those workflows here.

## Branch Naming Convention

**Format:** `rwittrup/LINEAR-TICKET-rough-description-here`

**Always** include the Linear ticket. Description is short, kebab-case, and rough.

| Part | Value |
|------|-------|
| Prefix | `rwittrup` (always) |
| Linear ticket | `ANET-2577`, `CALL-1162`, etc. |
| Description | short kebab-case slug |

### Examples

```
rwittrup/ANET-2577-agent-thoughts
rwittrup/CALL-1162-geofence-sync
rwittrup/ANET-1921-hide-transfer-button
```

---

## Single Branch Workflow

When the work is one cohesive change:

```bash
git checkout main && git pull
gt create rwittrup/ANET-2577-agent-thoughts
```

If you have uncommitted changes:

```bash
git add <files>
gt create rwittrup/ANET-2577-agent-thoughts -m "subject line"
```

If the current branch is untracked, run `gt track -p main` first. For the full untracked-branch and worktree flow (including re-parenting the first branch onto `main`), see **`graphite`** → *Creating a Stack* → *Handle Untracked Branches*.

---

## Multi-Trunk Workflow (planner)

When the planner identifies **multiple independent components** (e.g. backend + frontend, proto + go + ruby), create **separate trunk branches** off `main` — one per component. This keeps PRs atomic and independently mergeable.

**Each trunk branch is parented on `main`, not on each other.** They are siblings, not stacked.

### Steps

1. Start from a clean `main`:

   ```bash
   git checkout main && git pull
   ```

2. Create the first trunk:

   ```bash
   gt create rwittrup/ANET-2577-backend-changes
   ```

3. Return to `main` and create the next trunk:

   ```bash
   git checkout main
   gt create rwittrup/ANET-2577-frontend-changes
   ```

4. Verify both branches are parented on `main`:

   ```bash
   gt ls
   ```

   You should see both branches branching directly off `main`, e.g.:

   ```
   ◯ rwittrup/ANET-2577-frontend-changes
   │ ◯ rwittrup/ANET-2577-backend-changes
   ├─┘
   ◉ main
   ```

### Naming Multi-Trunk Branches

Use the same ticket on every trunk; vary the description to identify the component:

```
rwittrup/ANET-2577-backend-changes
rwittrup/ANET-2577-frontend-changes
rwittrup/ANET-2577-proto-changes
```

### When to Stack Instead

If component B **depends** on component A's changes (e.g. frontend consumes a new GraphQL field added in backend), stack them instead of creating parallel trunks:

```bash
git checkout main && git pull
gt create rwittrup/ANET-2577-backend-changes
# make backend changes, then:
gt create rwittrup/ANET-2577-frontend-changes
# frontend branch is now stacked on backend branch
```

Use multi-trunk only when the components are **independent**.

---

## Tracking an Existing Branch

If a branch already exists locally and isn't tracked by Graphite:

```bash
git checkout rwittrup/ANET-2577-agent-thoughts
gt track -p main
```

---

## Quick Reference

| I want to... | Command |
|--------------|---------|
| Create new trunk branch off main | `git checkout main && gt create rwittrup/TICKET-desc` |
| Create another trunk for a separate component | `git checkout main && gt create rwittrup/TICKET-other-desc` |
| Track an untracked branch onto main | `gt track -p main` |
| See the branch tree | `gt ls` |

---

## Related Skills

- **`graphite`** — primary skill for Graphite after branching: stacks, `gt submit`, `gt restack`, PR body/title workflow, troubleshooting. Path: `.agent/skills/graphite/SKILL.md`
- **`ryans-anet-ticket-branch`** — Linear-ticket-driven branch creation flow
- **`ryans-anet-pr`** — opening draft PRs after branch work (often after **`graphite`** submit)
- **`anet-ticket-branch-pr`** — combined ticket → branch → PR flow
