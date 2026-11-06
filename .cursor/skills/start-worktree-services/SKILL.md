---
name: start-worktree-services
description: Start the API, seeded database and Dispatch inside a linked git worktree so a feature-validation-kit can run against a live app. Use after git-worktree-setup-custom has passed, before running any validation kit setup.sh/run.sh, driving Dispatch in a browser, or hitting GraphQL on a worktree stack.
---

# Start worktree services

`git-worktree-setup-custom` leaves a **spec-only** stack: databases and `rails-api`, no Redpanda, no seed data, no Dispatch. Validation kits need a live app. Start it in the order below; every step has a check, and each check is the exit gate for its step.

Run everything from inside the worktree. Each command is a single plain command: the harness refuses heredocs, `for` loops and computed `cd` in a worktree.

## Steps

1. **Precondition.** `bash ~/.claude/skills/git-worktree-setup-custom/scripts/worktree-env.sh --status` shows a `COMPOSE_PROJECT_NAME` other than `apps`, a `Dispatch UI:` line and no `WARNING:`. If not, run `git-worktree-setup-custom` first.
2. **Seed and boot the API.** `just api reset-db`. It starts Redpanda and `rbac-api`, drops, migrates and seeds, which creates six dispatch centers (including "Engineering PD") and the `rwittrup+*@prepared911.com` users. Never create a center with FactoryBot: `versions` and `dispatch_center_settings` foreign keys make it undeletable. Done when the command exits 0. Never pipe a gate command through `head` or `tail`: that hides its exit status. Write output to a file in the scratchpad and echo the status, e.g. `just api reset-db > <scratchpad>/reset.log 2>&1; echo exit=$?`, or grep the log for the success line. Report what you saw, not what you expected.
   **Then re-run `bash ~/.claude/skills/git-worktree-setup-custom/scripts/worktree-setup.sh`** (idempotent, ends in `SMOKE: PASS`). `reset-db` regenerates `.env` from 1Password, which drops `DISPATCH_PORT` and the AWS-sourced `GOOGLE_CLIENT_SECRET`; setup restores both. Done when `grep -c '^DISPATCH_PORT=' .env` prints `1` and the setup log has `inject-dev-google-secret: GOOGLE_CLIENT_SECRET set from AWS`. If it warns it could not read the secret, run `aws sso login` and re-run.
3. **Start the API.** `just dc-start rails-api rails-grpc rails-goodjob rails-ws rails-ws-rpc locations-api rbac-api incident-search`. `reset-db` stops every `rails-*` service, so restart them all here. Drop a service only if the kit's README "Services needed" excludes it. Done when `curl -s -o /dev/null -w "%{http_code}" http://localhost:<RAILS_API_PORT>/healthz` prints `200`, with the port from `just worktree-info`. Compose reads `.env` only when it creates a container, so a `rails-api` created before the step 2 re-run keeps the 1Password secret: recreate it with `docker compose up -d --force-recreate --no-deps rails-api`. Check with `docker compose exec -T rails-api sh -c 'printf %s "$GOOGLE_CLIENT_SECRET"' | shasum -a 256 | cut -c1-12`; it must equal the sha256 prefix setup printed.
4. **Start Dispatch** only if the kit drives the UI. See "Dispatch" below. Done when `curl` on the Dispatch port prints `200` and `curl -s http://localhost:<DISPATCH_PORT>/config/appConfig.json` shows `API_BASE_URL` on this worktree's API port, not 3000.
5. **Hand off.** Only after you have seen all of these: `reset-db` exit 0 (step 2), `/healthz` 200 on the API port (step 3), served `appConfig.json` pointing at this worktree (step 4), and, for a UI kit, the Dispatch login page rendering in a real browser with no `Failed to fetch` (claude-in-chrome tools if available, otherwise ask the user to open it). curl passing is not a browser check. Then give the kit's README the API port, Dispatch URL and a seeded login. Print the port table from `just worktree-info` output and add the browser-facing Dispatch URL and any proxy; do not hand-build it.

Skip step 4 and the browser check for API-only kits. The API runner scripts need only steps 1–3.

## Dispatch

Run Dispatch with `bash ~/.claude/skills/git-worktree-setup-custom/scripts/dispatch-run.sh` from inside the worktree, in the background. It binds `DISPATCH_PORT` (`3002 + PORT_OFFSET`, printed as `Dispatch UI:` by `bash ~/.claude/skills/git-worktree-setup-custom/scripts/worktree-env.sh --status`) with `--strictPort`, so worktrees run side by side. Never use `just dispatch run`: its package.json scripts hard-code `--port=3002`, and Vite hops to the next free port when 3002 is taken.

- `worktree-setup.sh` writes the gitignored `turbo/apps/dispatch/.env.local.local`, so Dispatch calls this worktree's API. Without it Dispatch calls the main checkout's API on :3000, and login fails with `Login error. Try again or contact support.` `dispatch-run.sh` refuses to start without it.
- Google sign-in redirects to Dispatch's own origin (`src/utils/oauth/OAuthProvider.ts` builds the redirect URI from `window.location.host`). It worked from offset ports such as 4802 (RSP-290). If Google rejects a port with `redirect_uri_mismatch`, that port is not registered with the Google client: report the port and ask the user, do not switch ports silently. Tell the user to use `localhost`, not `127.0.0.1`.
- If `dispatch-run.sh` reports the port is in use, `lsof -nP -iTCP:<DISPATCH_PORT> -sTCP:LISTEN` shows the owner. Stop it only if this session started it, or `lsof -a -p <pid> -d cwd -Fn` shows a finished worktree. Kill by pid, never `pkill` by pattern (the harness blocks it and it can kill other worktrees' servers). If a live worktree owns it, say so and ask the user; do not pick another port silently.
- `dispatch-run.sh` runs `pnpm codegen` from `turbo/` before Vite (gitignored `*.graphql.ts` files go stale per branch). Start it in the background and poll the port: install and codegen take a minute or two. If you run codegen after Vite is already up, restart Vite: it caches the failed `.graphql.ts` resolution and keeps returning 404. Check the log line `API_BASE_URL=` names this worktree's API port.

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
- Dispatch login shows `Login error. Try again or contact support.`, `rails-api` logs `Google authorization code exchange refused` with `invalid_client` on `POST /auth/google/token` → `rails-api` is running with the 1Password `GOOGLE_CLIENT_SECRET`, which Google rejects. `reset-db` rewrote `.env` after setup injected the AWS secret, or `rails-api` started before the re-run → re-run `worktree-setup.sh` (needs `aws sso login`), then `docker compose up -d --force-recreate --no-deps rails-api`, and retry login.
- Dispatch stays on `Loading Prepared...`, console shows 404 for `*.graphql.ts` (e.g. `/DispatchCenterChatbotRelayMode.graphql.ts`), Vite log shows `Pre-transform error: Failed to load url ... .graphql.ts` → generated GraphQL files are stale or missing and Vite cached the failure → run `pnpm codegen` from `turbo/`, stop this session's Vite by task id and restart `dispatch-run.sh`, then hard-reload.
- `dispatch-run: no DISPATCH_PORT in .env` right after `reset-db` → `reset-db` regenerated `.env` → re-run `worktree-setup.sh`.
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

Related: `git-worktree-setup-custom` (provisioning, ports), `feature-validation-kit` (what the kit contains), `ruby-api-tester` (GraphQL with a real token).
