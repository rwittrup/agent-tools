---
name: acceptance
description: Run the validation kit, set up services, and walk the user through story acceptance interactively. Use when the user asks to accept a story, run acceptance, or work through acceptance criteria.
---

# Setup

Find the story's validation kit (`docs/<area>/validation/<feature-slug>/`) and read its README, including "Services needed".

1. Call `git-worktree-setup-custom`, then `start-worktree-services`. They own ports, services, `.env` and 1Password.
2. Run `bash ~/.claude/skills/start-worktree-services/scripts/services-up.sh --reset --dispatch`, adding `--audio` when the kit's "Services needed" or README mentions simulated calls, call audio or recordings (`KIT_AUDIO_DEMO`, `KIT_LIVE_CALL`). It starts the defaults (ruby api, locations, good jobs, AnyCable, rbac) plus what you ask for. Add the kit's other "Services needed" with `--extra`. If it exits 3, ask the user to run `! aws sso login --profile prepared-dev`.
3. Seed with the kit's `setup.sh`, using the Configuration values below. UNCAD kits take the user from `KIT_USER_EMAIL` (default `git config user.email`) and use the seeded Engineering PD; the API base URL defaults to the worktree's Rails port. For a kit that waits for a recording, run `bash ~/.claude/skills/start-worktree-services/scripts/audio-up.sh` first: recreating `audio-recorder` resets the directory it writes to.

Setup is done when `services-up.sh` ends with `SERVICES: OK` and `curl` on the Dispatch port returns 200.

Print a port table from `just worktree-info` (API, Dispatch, DB). Build every URL you give the user from that table.

# Acceptance

Run the kit's automated validation first, through `bash ~/.claude/skills/feature-validation-kit/scripts/kit-run.sh docs/<area>/validation/<feature-slug>`, with any opt-in `KIT_*` variables from the kit's README in the environment. Its `Step | Result | Verdict` table plus the closing `KIT-RUN: OK` line is the automated evidence. Any other closing line (`FAIL`, `INCONSISTENT REPORT`, a lint failure) means stop and fix before accepting: an inconsistent report can hide a failure behind exit 0. Then work through acceptance together:

1. Give the user numbered steps. Before each step, state the expected result and whether a reload is needed.
2. The user replies with what they see in the UX.
3. Judge each AC against their observation. On a failure, read service logs (`docker compose logs <service>`) before asking more questions, then investigate or fix.
4. Record open questions as they come up.

Acceptance is done when every AC has a row in a results table: criterion, user's observation as evidence, pass or fail.

# Configuration

Use these when seeding. Use them as given.

- email: the engineer's own seeded user, `KIT_USER_EMAIL` (default `git config user.email`). UNCAD kits resolve their personas from it. For a kit that takes an email argument instead, use the account the engineer signs in to Dispatch with.
- dispatch center: Engineering PD (seeded)
- LaunchDarkly flags in dev are already on. Do not override them unless the kit says so.
