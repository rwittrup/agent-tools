---
name: start-worktree-services
description: Start the API, seeded database, Dispatch and, for simulated calls, the audio pipeline inside a linked git worktree so a feature-validation-kit can run against a live app. Use after git-worktree-setup-custom has passed, before running any validation kit setup.sh/validate.sh, driving Dispatch in a browser, starting a simulated audio call, or hitting GraphQL on a worktree stack.
---

# Start worktree services

`git-worktree-setup-custom` leaves a **spec-only** stack: databases and `rails-api`, no Redpanda, no seed data, no Dispatch. Validation kits need a live app. `scripts/services-up.sh` brings it up in the order that works and verifies it; this file says when to run it and what to do when it stops.

Run from inside the worktree. `SWS=~/.claude/skills/start-worktree-services/scripts`. Set `GATE_LOG_DIR` to your scratchpad so logs sit with the session's files. Every script exits non-zero on failure, names its log, and its exit status is the gate: read the status from the script itself, never from a trailing `echo $?` or a pipe, which report the wrapper's status.

## Steps

1. **Precondition.** `bash ~/.claude/skills/git-worktree-setup-custom/scripts/worktree-env.sh --status` shows a `COMPOSE_PROJECT_NAME` other than `apps`, a `Dispatch UI:` line and no `WARNING:`. If not, run `git-worktree-setup-custom` first.
2. **Bring the stack up.** `bash $SWS/services-up.sh [--reset] [--audio] [--dispatch]`, in the background: seeding and builds take minutes. Done when it exits 0 and its last lines read `SERVICES: OK`.
   - `--reset` seeds a fresh database (six dispatch centers including "Engineering PD", and the `rwittrup+*@prepared911.com` users). Use it the first time in a worktree and whenever the data is dirty. Never create a center with FactoryBot: `versions` and `dispatch_center_settings` foreign keys make it undeletable.
   - `--audio` when the kit's "Services needed" or README mentions simulated calls, `start-audio-demo`, `KIT_AUDIO_DEMO`, `KIT_LIVE_CALL` or recordings. See "Audio".
   - `--dispatch` when the kit is driven in a browser.
   - `--extra "incident-search"` for the Triage or ANET lists; drop a service only if the kit's README excludes it.
3. **When it stops, read the exit code.** 1 not a linked worktree, 2 Docker down, 3 AWS SSO expired, 4 Google secret not from AWS, 5 Dispatch port held by another process, 11/12/13 reset-db / API start / audio start failed, 14 `rails-api` has the wrong Google secret, 15 a service will not start, 16 `/healthz` is not 200. Exit 3: ask the user to run `! aws sso login --profile prepared-dev` and rerun. Never run the login yourself: it opens a browser and waits.
4. **Hand off.** Only after you have seen `SERVICES: OK` and, for a UI kit, the Dispatch login page rendering in a real browser with no `Failed to fetch` (claude-in-chrome tools if available, otherwise ask the user to open it). curl passing is not a browser check. Then give the kit's README the API port, Dispatch URL and a seeded login. Print the port table from `just worktree-info` and add the browser-facing Dispatch URL; do not hand-build it. Report what you saw, not what you expected.

`services-up.sh` runs preflight, `compose-ports.sh write` (free host ports, see "Host ports"), every `just` command, `restore-env.sh` once, then verifies: services running, `rails-api` holding the same Google secret as `.env` (recreated if not), `/healthz` 200. `just` regenerates `.env` from 1Password on every `dc-start` and `reset-db`, dropping `DISPATCH_PORT` and the AWS Google secret, so restore once after the last one. Services already running are left alone, which skips the rewrite; `--rebuild` forces `dc-start` to pick up code changes. After any `just` recipe you run by hand, run `bash ~/.claude/skills/git-worktree-setup-custom/scripts/restore-env.sh`.

## Audio

Simulated calls (`workflows/start-audio-demo` in the UNCAD kits) need the audio pipeline: `audio-demo-server`, `audio-server`, `audio-transcriber`, `audio-recorder`, `livekit-consumer`, `rails-audio-results-consumer`, `call-transcription-storage-consumer`, `call-transcription-query`, `apps-redis`. `services-up.sh --audio` starts them through `audio-up.sh`, which also makes local recordings possible: the image runs as `nonroot` with no `/audio`, so `audio-recorder` fails every write and a call ends without a recording. Recreating that container resets the fix, so rerun `bash $SWS/audio-up.sh` before any kit run that waits for a recording (`KIT_AUDIO_RECORDING=1`). It is a no-op when nothing needs doing.

Timings measured locally: after a stop the call reads LIVE for about 148 seconds, then ENDED, then RECORDED about ten seconds later. Test recordings upload to the dev media bucket (`live-media.prepared911.dev`).

## Dispatch

`dispatch-up.sh` (run by `services-up.sh --dispatch`) starts `git-worktree-setup-custom/scripts/dispatch-run.sh` in the background on `DISPATCH_PORT` (`3002 + PORT_OFFSET`) with `--strictPort`, and waits until `appConfig.json` shows this worktree's API port. It does nothing if that is already true, and exits 5 when another process holds the port. Never use `just dispatch run`: its package.json scripts hard-code `--port=3002`, and Vite hops to the next free port when 3002 is taken.

- Google sign-in redirects to Dispatch's own origin (`src/utils/oauth/OAuthProvider.ts` builds the redirect URI from `window.location.host`). It worked from offset ports such as 4802 (RSP-290). If Google rejects a port with `redirect_uri_mismatch`, that port is not registered with the Google client: report the port and ask the user, do not switch ports silently. Tell the user to use `localhost`, not `127.0.0.1`.
- On exit 5, `lsof -nP -iTCP:<DISPATCH_PORT> -sTCP:LISTEN` shows the owner. Stop it only if this session started it (`$GATE_LOG_DIR/dispatch.pid`), or `lsof -a -p <pid> -d cwd -Fn` shows a finished worktree. Kill by pid, never `pkill` by pattern: it can kill other worktrees' servers. If a live worktree owns it, say so and ask the user.
- `dispatch-run.sh` runs `pnpm codegen` from `turbo/` before Vite (gitignored `*.graphql.ts` files go stale per branch). If you run codegen after Vite is already up, restart Vite: it caches the failed `.graphql.ts` resolution and keeps returning 404.

## Host ports

`docker-compose.yaml` publishes many host ports as literals (grafana 15301, otelcol 8126, rbac-api 50056, rails-ws 8080 and more: `compose-ports.sh list` shows them), so `PORT_OFFSET` does not move them and a second worktree's stack collides with the first. `services-up.sh` republishes them on free ports through a git-excluded `docker-compose.override.yaml` (`compose-ports.sh write`, in `git-worktree-setup-custom`), and `run-gate.sh` turns a `port is already allocated` failure into a repair: it moves that one port and reruns the command, up to three times. Another worktree's stack stays up.

To find where a service really listens, run `bash ~/.claude/skills/git-worktree-setup-custom/scripts/compose-ports.sh port <service> <container-port>` (for example `port locations-api 50051`, never the stock 50055). Dispatch's websocket and call-handler URLs follow the shifted ports: `restore-env.sh` writes them to `.env.local.local`.

## 1Password

Run `just` commands directly. 1Password prompts the user out of band; wait for the command to finish. Do not ask the user to run `op signin`. If a command still reports `Failed to automatically sign in`, retry it once after the prompt is answered.

## Known problems

Symptom → cause → fix.

- `reset-db` or `dc-start` hangs, or exits 255, with `aws sso login` and a browser URL in its log → the SSO session for `prepared-dev` expired and the recipe is waiting on a browser → `preflight.sh` catches this first (exit 3); ask the user to run `! aws sso login --profile prepared-dev`.
- `Bind for 0.0.0.0:<port> failed: port is already allocated` → another worktree's stack (or any process) holds a host port → `run-gate.sh` repairs it: `GATE …: host port N was taken; moved it and retrying`. When it prints `PORT CONFLICT … compose-ports.sh could not move it`, the port follows `PORT_OFFSET` (Rails API, databases, Redpanda) or a non-compose process holds it → pin another `PORT_OFFSET` in `.env.local`, delete `.env`, rerun `worktree-setup.sh`. By hand: `compose-ports.sh write --repair <port>`.
- `dc-start` exits 1 with `container ...grafana... is unhealthy` → the observability sidecar's Pyroscope crash-loops → `run-gate.sh` retries twice; if it persists, rerun later. Nothing in the kit needs it.
- `rails-db-replica` exits 137 → memory pressure → `services-up.sh` starts missing services once more; if it repeats, stop finished worktrees' stacks.
- A simulated call ends but never reaches RECORDED, and `audio-recorder` logs `error creating recording file: open audio/<chatroom>/...: no such file or directory` → no writable `/audio` → `bash $SWS/audio-up.sh`.
- Dispatch shows `Failed to fetch`, Google login shows `Login error. Try again or contact support.`, curl to the API is 200 with correct CORS, API logs show no browser requests, opening the API URL in Chrome gives an error page → the API port is on Chromium's restricted list (`net/base/port_util.cc` `kRestrictedPorts`; ERR_UNSAFE_PORT). Offset +3000 puts Rails on 6000 (X11). Nearby ports on the list: 5060, 5061, 6000, 6566, 6665-6669, 6697, 10080, plus most well-known service ports below 1024 → preferred fix: pin a different `PORT_OFFSET` in `.env.local`, re-run `just worktree-setup` (see `git-worktree-setup`). Fallback without recreating the stack: run a pass-through proxy on a safe port in the background (6000 → 6100 here):

  ```js
  require('http').createServer((q, r) => {
    const u = require('http').request({host: '127.0.0.1', port: 6000, path: q.url, method: q.method, headers: q.headers},
      p => { r.writeHead(p.statusCode, p.headers); p.pipe(r); });
    q.pipe(u);
  }).listen(6100, '127.0.0.1');
  ```

  Then set `API_BASE_URL=http://127.0.0.1:6100` in `turbo/apps/dispatch/.env.local.local`, run `CONFIG_ENV=local node scripts/loadConfig.js` from `turbo/apps/dispatch`, and hard-reload. `public/config/appConfig.json` is read at runtime, so Vite needs no restart; the websocket (`API_WEBSOCKET_URL`) is unaffected.
- Dispatch login shows `Login error. Try again or contact support.`, `rails-api` logs `Google authorization code exchange refused` with `invalid_client` on `POST /auth/google/token` → `rails-api` is running with the 1Password `GOOGLE_CLIENT_SECRET`, which Google rejects → `services-up.sh` detects and recreates it; by hand: `restore-env.sh` (needs the SSO session), then `docker compose up -d --force-recreate --no-deps rails-api`.
- `dispatch-run: no DISPATCH_PORT in .env` or `DISPATCH: no DISPATCH_PORT in .env` → a `just` recipe regenerated `.env` → `restore-env.sh`.
- Dispatch stays on `Loading Prepared...`, console shows 404 for `*.graphql.ts` (e.g. `/DispatchCenterChatbotRelayMode.graphql.ts`), Vite log shows `Pre-transform error: Failed to load url ... .graphql.ts` → generated GraphQL files are stale or missing and Vite cached the failure → run `pnpm codegen` from `turbo/`, kill the Vite pid from `$GATE_LOG_DIR/dispatch.pid`, rerun `dispatch-up.sh`, then hard-reload.
- A kit's `setup.sh` stops with `PREFLIGHT: personas need setup ... Run: entities/ensure-personas` → personas missing → run `docs/uncad/validation/entities/ensure-personas` (it modifies the local DB: grants a permission on the Engineering PD responder role), re-run `setup.sh`, and tell the user you did it.
- Dispatch login fails with `Response not successful: Received status code 500` → `locations-api` or `rbac-api` is not running → rerun `services-up.sh`, then have the user sign out and sign in again for a fresh token.
- The board only updates after clicking Refresh → `rails-goodjob`, `rails-ws` or `rails-ws-rpc` is down → rerun `services-up.sh`.
- `rails-migrate-db` exits 1 with `Failed to resolve 'redpanda:9092'`, or hangs → Redpanda is not running → `just dc-start redpanda`, then re-run.
- `rails-api` shows `(unhealthy)` → the collector (`otelcol`) is not part of this stack → ignore; use the `/healthz` curl.
- `Datadog … otelcol:8126` errors in `rails runner` output → no collector → ignore.
- `PG::ForeignKeyViolation` deleting a dispatch center → PaperTrail rows → run `just api reset-db` instead of cleaning by hand.
- `ERR_PNPM_RECURSIVE_EXEC_FIRST_FAIL … SIGABRT` from `tsc` → memory pressure with several worktree stacks running → stop stacks of finished worktrees with `just dc-stop` from their directories.
- `rubocop: command not found` on the host → run it inside the API container.
- Go mocks, `schema.graphql`, `structure.sql` or `queue_structure.sql` modified after boot → generated churn → leave them out of commits, or `git restore` them.

Related: `git-worktree-setup-custom` (provisioning, ports, `restore-env.sh`), `feature-validation-kit` (what the kit contains, `kit-run.sh`), `ruby-api-tester` (GraphQL with a real token).
