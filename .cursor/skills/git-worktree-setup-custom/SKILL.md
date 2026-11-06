---
name: git-worktree-setup-custom
description: Custom git-worktree-setup (scripts live in agent-tools, not the repo) that also gives each worktree its own Dispatch port. Set up a new git worktree so just api, docker, rspec and Dispatch work in it. Use when starting work in a new git worktree, especially one stacked on an unmerged branch, before running any just api, docker compose or spec command.
---

# Git worktree setup (custom)

Copy of `git-worktree-setup` that runs this skill's `scripts/` instead of the repo's `just worktree-setup` / `just worktree-info`, so port changes can be validated before they merge into prepared911. Differences: `DISPATCH_PORT` (`3002 + PORT_OFFSET`), offsets that skip Chrome-blocked ports, and a worktree-local Dispatch config pointing at the worktree's API. Use `git-worktree-setup` for a worktree that must match the repo exactly.

A fresh worktree has no `.env`, so `just` loads the main checkout's and every `docker compose` call hits the main stack. `worktree-setup.sh` fixes that. Do not hand-roll `.env`, ports or compose commands.

Do **not** run `docker compose -p apps …` from the main checkout with `-v .worktrees/…/apps/ruby/api:/app` or manual mounts for `protos`, `master.key`, or other paths from another checkout. That uses the main stack, ignores the worktree `.env`, and causes repeated spec/debug loops. After `SMOKE: PASS`, run specs only with `just api rspec <paths>` from inside the worktree.

Done when the smoke spec passes.

## Agent rule

Until `worktree-setup.sh` prints `SMOKE: PASS`, run only:

- `bash ~/.claude/skills/git-worktree-setup-custom/scripts/worktree-setup.sh` (and `bash ~/.claude/skills/git-worktree-setup-custom/scripts/worktree-env.sh --status` to verify)
- Re-running `worktree-setup.sh` if it failed

If setup waits on `op` or fails, stop and retry after sign-in — do not start alternate stacks.

Do **not** until `SMOKE: PASS`: explore or implement the ticket, `just api minimal`, `just api run`, ad-hoc `docker compose …`, `just api reset-spec-db`, `just api rspec` (setup runs its own smoke spec), GraphQL schema dump/codegen, or copying `.env` / key files from another checkout.

## Steps

1. Create the worktree **once**. Use the unmerged branch as `<base>` when stacking. If the branch already exists locally, attach the worktree to it instead of creating a second branch or directory for the same ticket:

   ```bash
   git fetch origin
   git worktree add -b <branch> .worktrees/<slug> <base>
   # branch already exists:
   git worktree add .worktrees/<slug> <existing-branch>
   ```

2. `EnterWorktree` with `path=.worktrees/<slug>` and stay inside it. Do not `cd` to the main checkout. `EnterWorktree name=` always branches from `origin/trunk`, so it cannot stack.
3. Run `bash ~/.claude/skills/git-worktree-setup-custom/scripts/worktree-env.sh --status`. If `COMPOSE_PROJECT_NAME` is `apps` or any `WARNING:` line appears, the worktree is not provisioned — continue to step 4; do not run any other `just api` or `docker compose` command.
4. Run `bash ~/.claude/skills/git-worktree-setup-custom/scripts/worktree-setup.sh`.
5. Run `bash ~/.claude/skills/git-worktree-setup-custom/scripts/worktree-env.sh --status` again. The project must not be `apps` and there must be no `WARNING:` line.
6. Setup prints `SMOKE: PASS` at the end of step 4. From then on use `just api rspec <paths>`.

`bash ~/.claude/skills/git-worktree-setup-custom/scripts/worktree-env.sh --status` shows `WARNING:` if the worktree is not set up. Other `just dc-*` and `just api` commands do not check, so run setup first.

Dispatch: from inside the worktree run `bash ~/.claude/skills/git-worktree-setup-custom/scripts/dispatch-run.sh`. It serves on `DISPATCH_PORT` with `--strictPort` (a taken port fails instead of hopping) and refuses to start without the worktree-local config. Do not use `just dispatch run`: it hard-codes 3002.

Related: `ruby-database-best-practices` (migration versions), `rails-testing` (writing specs).

## Known problems

Add one entry per problem: symptom → cause → fix.

- `LoadError: cannot load such file -- /app/spec/...` → the command ran in the main stack's container → run `worktree-setup.sh`.
- `docker compose up --wait` hangs or fails on `rails-db-replica` → first-run replica standby sync during `worktree-setup.sh` → do not hand-roll partial `docker compose up` or copy env from another checkout; re-run `worktree-setup.sh` (idempotent). If it still fails after one retry, stop and ask the user — do not debug replica issues as ticket work.
- `.env` or `.env.local` edited by hand → `.env` is regenerated and the pins are read from `.env.local` → pin `COMPOSE_PROJECT_NAME` / `PORT_OFFSET` in `.env.local` only, then re-run setup.
- New migration, spec fails on schema → the test DB is not migrated → `docker compose exec -T rails-api env RAILS_ENV=test SKIP_POSTGIS_DB_SETUP=true bundle exec rake db:migrate`. Use a unique 14-digit version.
- Annotate, `apps/ruby/api/db/structure.sql`, PostGIS model `# Database name:` lines, or Go mock files modified after migrate or startup → generated churn → `git restore` those paths before committing.
- `parallel:spec` reports duplicate pending migrations on `live-api-test*` after `parallel:migrate` → local parallel test DB drift, usually unrelated to the feature branch → do not loop migrate/rerun; use `just api rspec <paths>` for proof and leave full parallel suites to CI or a human.
- `Datadog ... otelcol:8126` errors in spec output → the spec-only stack skips the collector → ignore.
- Harness refuses `cd` to the main checkout, `{{...}}` format strings or long pipelines → guardrail → stay in the worktree and use simpler commands.
- Untracked docs exist only in the main checkout → not in the worktree → read them by absolute path.
