---
name: start-worktree-services
description: Start the API, seeded database and Dispatch inside a linked git worktree so a feature-validation-kit can run against a live app. Use after git-worktree-setup has passed, before running any validation kit setup.sh/run.sh, driving Dispatch in a browser, or hitting GraphQL on a worktree stack.
---

# Start worktree services

`git-worktree-setup` leaves a **spec-only** stack: databases and `rails-api`, no Redpanda, no seed data, no Dispatch. Validation kits need a live app. Start it in the order below; every step has a check, and each check is the exit gate for its step.

Run everything from inside the worktree. Each command is a single plain command: the harness refuses heredocs, `for` loops and computed `cd` in a worktree.

## Steps

1. **Precondition.** `just worktree-info` shows a `COMPOSE_PROJECT_NAME` other than `apps` and no `WARNING:`. If not, run `git-worktree-setup` first.
2. **Seed and boot the API.** `just api reset-db`. It starts Redpanda and `rbac-api`, drops, migrates and seeds, which creates six dispatch centers (including "Engineering PD") and the `rwittrup+*@prepared911.com` users. Never create a center with FactoryBot: `versions` and `dispatch_center_settings` foreign keys make it undeletable. Done when the command exits 0. Never pipe a gate command through `head` or `tail`: that hides its exit status. Write output to a file in the scratchpad and echo the status, e.g. `just api reset-db > <scratchpad>/reset.log 2>&1; echo exit=$?`, or grep the log for the success line. Report what you saw, not what you expected.
3. **Start the API.** `just dc-start rails-api rails-grpc rails-goodjob rails-ws rails-ws-rpc locations-api rbac-api incident-search`. `reset-db` stops every `rails-*` service, so restart them all here. Drop a service only if the kit's README "Services needed" excludes it. Done when `curl -s -o /dev/null -w "%{http_code}" http://localhost:<RAILS_API_PORT>/healthz` prints `200`, with the port from `just worktree-info`.
4. **Start Dispatch** only if the kit drives the UI. See "Dispatch" below. Done when `curl` on the Dispatch port prints `200` and `curl -s http://localhost:<DISPATCH_PORT>/config/appConfig.json` shows `API_BASE_URL` on this worktree's API port, not 3000.
5. **Hand off.** Only after you have seen all of these: `reset-db` exit 0 (step 2), `/healthz` 200 on the API port (step 3), served `appConfig.json` pointing at this worktree (step 4), and, for a UI kit, the Dispatch login page rendering in a real browser with no `Failed to fetch` (claude-in-chrome tools if available, otherwise ask the user to open it). curl passing is not a browser check. Then give the kit's README the API port, Dispatch URL and a seeded login. Print the port table from `just worktree-info` output and add the browser-facing Dispatch URL and any proxy; do not hand-build it.

Skip step 4 and the browser check for API-only kits. The API runner scripts need only steps 1–3.

## Dispatch

`just dispatch run local` binds Vite to `DISPATCH_PORT` (`3002 + PORT_OFFSET`) and points it at this worktree's API port, both read from the worktree `.env`. `just worktree-info` prints the `Dispatch UI:` URL.

- First run `grep DISPATCH_PORT .env`. If it is set, `just dispatch run local` binds that port and this worktree's API. If it is missing, Vite falls back to 3002 and the main checkout's API (`turbo/apps/dispatch/.env.local` defaults: `API_BASE_URL` 3000, `API_WEBSOCKET_URL` `ws://127.0.0.1:8080/cable`, OAuth redirect 3000). Do not run it.
- Re-running `just worktree-setup` may not write `DISPATCH_PORT` (it did not on RSP-306). Then use the manual path: write `API_BASE_URL=http://127.0.0.1:<RAILS_API_PORT>` to the gitignored `turbo/apps/dispatch/.env.local.local`, run `CONFIG_ENV=local node scripts/loadConfig.js`, then from `turbo/apps/dispatch` run in the background `NODE_ENV=development pnpm exec vite --host=0.0.0.0 --port=3002 --strictPort`.
- Google sign-in works only from `http://localhost:3002`: the redirect URI is built from `window.location.host` (`src/utils/oauth/OAuthProvider.ts`) and only that origin is registered. If the user signs in with Google, serve on exactly 3002 (not 3002 + offset) and tell them to use `localhost`, not `127.0.0.1`.
- If 3002 is taken, `lsof -nP -iTCP:3002 -sTCP:LISTEN` shows the owner. Stop it only if this session started it, or `lsof -a -p <pid> -d cwd -Fn` shows a finished worktree. Kill by pid, never `pkill` by pattern (the harness blocks it and it can kill other worktrees' servers). If a live worktree owns it, say so and ask the user; do not pick another port silently.
- Start Vite in the background and poll the port: codegen takes about a minute. Check the log line `API_BASE_URL=` names this worktree's API port.

## 1Password

Run `just` commands directly. 1Password prompts the user out of band; wait for the command to finish. Do not ask the user to run `op signin`. If a command still reports `Failed to automatically sign in`, retry it once after the prompt is answered. Once `.env` exists, plain `docker compose up -d <service>` from inside the worktree is equivalent and works without `op`.

## Known problems

Symptom → cause → fix.

- Dispatch shows `Failed to fetch`, Google login shows `Login error. Try again or contact support.`, curl to the API is 200 with correct CORS, API logs show no browser requests, opening the API URL in Chrome gives an error page → the API port is on Chromium's restricted list (`net/base/port_util.cc` `kRestrictedPorts`; ERR_UNSAFE_PORT). Offset +3000 puts Rails on 6000 (X11). Nearby ports on the list: 5060, 5061, 6000, 6566, 6665-6669, 6697, 10080, plus most well-known service ports below 1024 → preferred fix: pin a different `PORT_OFFSET` in `.env.local`, re-run `just worktree-setup` (see `git-worktree-setup`). Fallback without recreating the stack: run a pass-through proxy on a safe port in the background (6000 → 6100 here):

  ```js
  require('http').createServer((q, r) => {
    const u = require('http').request({host: '127.0.0.1', port: 6000, path: q.url, method: q.method, headers: q.headers},
      p => { r.writeHead(p.statusCode, p.headers); p.pipe(r); });
    q.pipe(u);
  }).listen(6100, '127.0.0.1');
  ```

  Then set `API_BASE_URL=http://127.0.0.1:6100` in `turbo/apps/dispatch/.env.local.local`, run `CONFIG_ENV=local node scripts/loadConfig.js` from `turbo/apps/dispatch`, and hard-reload. `public/config/appConfig.json` is read at runtime, so Vite needs no restart; the websocket on 8080 is unaffected.
- A kit's `setup.sh` stops with `PREFLIGHT: personas need setup ... Run: entities/ensure-personas` → personas missing → run `docs/uncad/validation/entities/ensure-personas` (it modifies the local DB: grants a permission on the Engineering PD responder role), re-run `setup.sh`, and tell the user you did it.
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
