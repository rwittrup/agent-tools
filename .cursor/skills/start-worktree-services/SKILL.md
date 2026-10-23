---
name: start-worktree-services
description: Start the API, seeded database and Dispatch inside a linked git worktree so a feature-validation-kit can run against a live app. Use after git-worktree-setup has passed, before running any validation kit setup.sh/run.sh, driving Dispatch in a browser, or hitting GraphQL on a worktree stack.
---

# Start worktree services

`git-worktree-setup` leaves a **spec-only** stack: databases and `rails-api`, no Redpanda, no seed data, no Dispatch. Validation kits need a live app. Start it in the order below; every step has a check, and each check is the exit gate for its step.

Run everything from inside the worktree. Each command is a single plain command: the harness refuses heredocs, `for` loops and computed `cd` in a worktree.

## Steps

1. **Precondition.** `just worktree-info` shows a `COMPOSE_PROJECT_NAME` other than `apps` and no `WARNING:`. If not, run `git-worktree-setup` first.
2. **Seed and boot the API.** `just api reset-db`. It starts Redpanda and `rbac-api`, drops, migrates and seeds, which creates six dispatch centers (including "Engineering PD") and the `rwittrup+*@prepared911.com` users. Never create a center with FactoryBot: `versions` and `dispatch_center_settings` foreign keys make it undeletable. Done when the command exits 0.
3. **Start the API.** `just dc-start rails-api rails-grpc rails-goodjob rails-ws rails-ws-rpc locations-api rbac-api incident-search`. `reset-db` stops every `rails-*` service, so restart them all here. Drop a service only if the kit's README "Services needed" excludes it. Done when `curl -s -o /dev/null -w "%{http_code}" http://localhost:<RAILS_API_PORT>/healthz` prints `200`, with the port from `just worktree-info`.
4. **Start Dispatch** only if the kit drives the UI. See "Dispatch" below. Done when `curl` on the Dispatch port prints `200`.
5. **Hand off** to the kit's README with the API port, Dispatch port, and a seeded login from step 2.

Skip step 4 for API-only kits. The API runner scripts need only steps 1–3.

## Dispatch

`just dispatch run local` binds Vite to `DISPATCH_PORT` (`3002 + PORT_OFFSET`) and points it at this worktree's API port, both read from the worktree `.env`. `just worktree-info` prints the `Dispatch UI:` URL.

- A worktree set up before `DISPATCH_PORT` existed has no `DISPATCH_PORT` in `.env`, so Vite falls back to 3002 and the main checkout's API. Re-run `just worktree-setup` (idempotent) and confirm `just worktree-info` prints a `Dispatch UI:` line.
- If the re-run still writes no `DISPATCH_PORT` (an old branch), write `API_BASE_URL=http://127.0.0.1:<RAILS_API_PORT>` to the gitignored `turbo/apps/dispatch/.env.local.local`, then run `CONFIG_ENV=local node scripts/loadConfig.js` and `pnpm exec vite --host=0.0.0.0 --port=<free port>` in the background.
- Vite moves to the next port when its port is taken. Read the real port from the Vite log, and give the user that URL.
- Dispatch expects the API on :3000 in some configs. Check the log line `API_BASE_URL=`; it must name this worktree's API port.
- Start it in the background and poll the port: codegen takes about a minute before Vite answers.
- If the port is still taken, `lsof -nP -iTCP:<port> -sTCP:LISTEN` shows the owner. Stop it only after `lsof -a -p <pid> -d cwd -Fn` shows it belongs to a finished worktree.

## 1Password

Run `just` commands directly. 1Password prompts the user out of band; wait for the command to finish. Do not ask the user to run `op signin`. If a command still reports `Failed to automatically sign in`, retry it once after the prompt is answered. Once `.env` exists, plain `docker compose up -d <service>` from inside the worktree is equivalent and works without `op`.

## Known problems

Symptom → cause → fix.

- Dispatch login fails with `Response not successful: Received status code 500` → `locations-api` or `rbac-api` is not running → `just dc-start locations-api rbac-api`, then have the user sign out and sign in again for a fresh token.
- The board only updates after clicking Refresh → `rails-goodjob`, `rails-ws` or `rails-ws-rpc` is down → `docker compose ps`, then start the missing one.

- `rails-api` shows `(unhealthy)` → the collector (`otelcol`) is not part of this stack → ignore; use the `/healthz` curl.
- `rails-migrate-db` exits 1 with `Failed to resolve 'redpanda:9092'`, or hangs → Redpanda is not running → `just dc-start redpanda`, then re-run.
- `Datadog … otelcol:8126` errors in `rails runner` output → no collector → ignore.
- `PG::ForeignKeyViolation` deleting a dispatch center → PaperTrail rows → run `just api reset-db` instead of cleaning by hand.
- `ERR_PNPM_RECURSIVE_EXEC_FIRST_FAIL … SIGABRT` from `tsc` → memory pressure with several worktree stacks running → stop stacks of finished worktrees with `just dc-stop` from their directories.
- `rubocop: command not found` on the host → run it inside the API container.
- Go mocks, `schema.graphql` or `structure.sql` modified after boot → generated churn → `git restore` before committing.

Related: `git-worktree-setup` (provisioning), `feature-validation-kit` (what the kit contains), `ruby-api-tester` (GraphQL with a real token).
