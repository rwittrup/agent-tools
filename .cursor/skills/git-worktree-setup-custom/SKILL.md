---
name: git-worktree-setup-custom
description: Custom git-worktree-setup (scripts live in agent-tools, not the repo) that also gives each worktree its own Dispatch port. Set up a new git worktree so just api, docker, rspec and Dispatch work in it. Use when starting work in a new git worktree, especially one stacked on an unmerged branch, before running any just api, docker compose or spec command.
---

# Git worktree setup (custom)

Copy of `git-worktree-setup` that runs this skill's `scripts/` instead of the repo's `just worktree-setup` / `just worktree-info`, so port changes can be validated before they merge into prepared911. Differences: `DISPATCH_PORT` (`3002 + PORT_OFFSET`), offsets that skip Chrome-blocked ports, a worktree-local Dispatch config pointing at the worktree's API, and host ports that `docker-compose.yaml` hard-codes republished on free ones (`compose-ports.sh`, below). Use `git-worktree-setup` for a worktree that must match the repo exactly.

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

`.env` is regenerated from 1Password by `worktree-setup.sh` and by every `just` recipe that depends on `_root-env` (`dc-start`, `reset-db` and others), which drops `DISPATCH_PORT` and the AWS-sourced `GOOGLE_CLIENT_SECRET`. `bash ~/.claude/skills/git-worktree-setup-custom/scripts/restore-env.sh` puts them back without touching Docker or 1Password (exit 4 if the secret cannot be read from AWS; it uses the `prepared-dev` profile unless `AWS_PROFILE` is set). Run it after any such recipe; `start-worktree-services/scripts/services-up.sh` does so for you. `worktree-setup.sh` calls it too.

Dispatch: from inside the worktree run `bash ~/.claude/skills/git-worktree-setup-custom/scripts/dispatch-run.sh`. It serves on `DISPATCH_PORT` with `--strictPort` (a taken port fails instead of hopping) and refuses to start without the worktree-local config. Do not use `just dispatch run`: it hard-codes 3002.

## Host ports

`PORT_OFFSET` moves only the ports `docker-compose.yaml` builds from variables. It publishes many more as literals (grafana 15301, otelcol 8126 and 514, rbac-api 50056, rails-ws 8080 ...), so two worktrees' stacks collide on them. `compose-ports.sh` fixes that without touching the repo: it writes a git-excluded `docker-compose.override.yaml` that republishes each literal port on a free one (`!override`, host side only; services still reach each other by compose DNS).

Run from inside the worktree: `SCRIPTS=~/.claude/skills/git-worktree-setup-custom/scripts`.

- `bash $SCRIPTS/compose-ports.sh write [--repair PORT]` regenerates the override. It keeps the port it chose last time (a rerun never recreates containers), else stock + `PORT_OFFSET`, else the next free port. A port is free when nothing is bound to it, Chromium allows it, and nothing else in the stack publishes it. `restore-env.sh` and `services-up.sh` run it; a main checkout is left alone.
- `compose-ports.sh list` shows what moved (`worktree-env.sh --status` includes it).
- `compose-ports.sh port <service> <container-port>` prints the host port a service really listens on. Use it instead of a stock port from a kit's README or script (the `derive-cfs-beats-locations-rpc` kit's `localhost:50055` becomes `localhost:$(compose-ports.sh port locations-api 50051)`).
- `compose-ports.sh self-check` runs the planner's assertions without Docker. Rerun it after editing `compose-ports.py`.

`restore-env.sh` also writes `API_WEBSOCKET_URL` (rails-ws) and `CALL_HANDLER_URL` (call-handler) into Dispatch's gitignored `.env.local.local`, so the browser reaches the shifted ports. Delete `docker-compose.override.yaml` to return to the stock ports.

Related: `ruby-database-best-practices` (migration versions), `rails-testing` (writing specs).

## Known problems

Add one entry per problem: symptom → cause → fix.

- `LoadError: cannot load such file -- /app/spec/...` → the command ran in the main stack's container → run `worktree-setup.sh`.
- `docker compose up --wait` hangs or fails on `rails-db-replica` → first-run replica standby sync during `worktree-setup.sh` → do not hand-roll partial `docker compose up` or copy env from another checkout; re-run `worktree-setup.sh` (idempotent). If it still fails after one retry, stop and ask the user — do not debug replica issues as ticket work.
- `.env` or `.env.local` edited by hand → `.env` is regenerated and the pins are read from `.env.local` → pin `COMPOSE_PROJECT_NAME` / `PORT_OFFSET` in `.env.local` only, then re-run setup.
- `DISPATCH_PORT` missing from `.env`, or `inject-dev-google-secret: could not read dev/api/dispatch_google_client` → a `just` recipe regenerated `.env`, or the SSO session for `prepared-dev` expired → `aws sso login --profile prepared-dev`, then `restore-env.sh`.
- New migration, spec fails on schema → the test DB is not migrated → `docker compose exec -T rails-api env RAILS_ENV=test SKIP_POSTGIS_DB_SETUP=true bundle exec rake db:migrate`. Use a unique 14-digit version.
- Annotate, `apps/ruby/api/db/structure.sql`, PostGIS model `# Database name:` lines, or Go mock files modified after migrate or startup → generated churn → `git restore` those paths before committing.
- `parallel:spec` reports duplicate pending migrations on `live-api-test*` after `parallel:migrate` → local parallel test DB drift, usually unrelated to the feature branch → do not loop migrate/rerun; use `just api rspec <paths>` for proof and leave full parallel suites to CI or a human.
- `Bind for 0.0.0.0:<port> failed: port is already allocated` → another stack holds a host port → `compose-ports.sh write --repair <port>` moves that mapping and `docker compose up` works. A port that follows `PORT_OFFSET` (Rails API, databases) is not movable that way: pin another `PORT_OFFSET` in `.env.local`, delete `.env`, rerun `worktree-setup.sh`. Never stop another worktree's stack for it.
- A trunk rebase adds a literal host port and it collides → the override predates it → `compose-ports.sh write` (`services-up.sh` and `restore-env.sh` already do).
- `Datadog ... otelcol:8126` errors in spec output → the spec-only stack skips the collector → ignore.
- Harness refuses `cd` to the main checkout, `{{...}}` format strings or long pipelines → guardrail → stay in the worktree and use simpler commands.
- Untracked docs exist only in the main checkout → not in the worktree → read them by absolute path.
