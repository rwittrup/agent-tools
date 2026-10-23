---
name: acceptance
description: Run the validation kit, set up services, and walk the user through story acceptance interactively. Use when the user asks to accept a story, run acceptance, or work through acceptance criteria.
---

# Setup

Find the story's validation kit (`docs/<area>/validation/<feature-slug>/`) and read its README, including "Services needed".

1. Call `git-worktree-setup`, then `start-worktree-services`. They own ports, services and 1Password.
2. Run `just` commands directly. 1Password prompts the user out of band; wait for the command to finish.
3. Start the union of the kit's "Services needed" and these defaults: ruby api, dispatch, locations, good jobs, AnyCable, rbac.
4. Seed with the kit's `setup.sh`, using the Configuration values below.

Setup is done when every started service shows running in `docker compose ps`, the API `/healthz` returns 200, and `curl` on the Dispatch port returns 200.

Print a port table from `just worktree-info` (API, Dispatch, DB). Build every URL you give the user from that table.

# Acceptance

Run the kit's automated validation first. Then work through acceptance together:

1. Give the user numbered steps. Before each step, state the expected result and whether a reload is needed.
2. The user replies with what they see in the UX.
3. Judge each AC against their observation. On a failure, read service logs (`docker compose logs <service>`) before asking more questions, then investigate or fix.
4. Record open questions as they come up.

Acceptance is done when every AC has a row in a results table: criterion, user's observation as evidence, pass or fail.

# Configuration

Use these when seeding. Use them as given.

- email: rwittrup@prepared911.com
- dispatch center: Engineering PD
- LaunchDarkly flags in dev are already on. Do not override them unless the kit says so.
