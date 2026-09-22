---
name: ruby-api-tdd-env
description: >
  Warm the local Dockerized Rails API so RSpec can prove red/green without a
  cold-start tax. Use before dispatching Tester or Implementer on Ruby API
  work, when entering a TDD loop that needs `just api rspec`, or whenever an
  agent would otherwise skip specs because Compose is down. Prefer this over
  inventing docker/rspec commands. Do not use for GraphQL/OAuth e2e checks
  (ruby-api-tester) or migrations/rails runner (ryans-rails).
---

# Ruby API TDD environment

Pay the Docker / `rails-api` boot cost **once**, then hand workers a proven run
command. Unwarmed stacks cause Tester to skip (no red proof) and Implementer to
eat the cold start alone.

Work from the **product repo root** (the monorepo that owns `just api` and
`apps/ruby/api/`).

## When this applies

Job or change touches the Ruby API (paths under `apps/ruby/api/`, RSpec under
that tree, or approach that says ruby-api). Skip for pure Go, frontend-only, or
docs-only work.

## Procedure

Run in order. Stop and report if a step fails — do not dispatch Tester /
Implementer on a half-ready stack.

### 1. Docker is reachable

```bash
docker info
```

If this fails, the daemon (e.g. OrbStack) is down or the shell cannot reach the
socket. Fix that before continuing; request unsandboxed / Docker permissions if
the harness blocks the socket.

### 2. `rails-api` can exec

```bash
just dc-exec rails-api true
```

Exit 0 means the service is up enough to run commands. If it fails, start or
heal the stack the way this repo usually does (`just` / Compose up for
`rails-api`), then retry until `true` succeeds.

Optional stronger check when specs have been flaky on a fresh boot: run a no-op
or short `just api rspec` path you already trust, or wait until the container
is healthy per Compose — record what worked in [Growth notes](#growth-notes).

### 3. Emit the handoff

Give Tester and Implementer the **same** one-liner. Substitute the real spec
paths for this Job:

```text
Compose is ready; run:
just api rspec <spec-paths>
```

Example:

```text
Compose is ready; run:
just api rspec spec/services/foo_spec.rb
```

If the exact paths are not known yet (Tester still writing files), pass the
ready signal plus the recipe shape:

```text
Compose is ready; run via: just api rspec <paths-under-apps/ruby/api>
```

## After handoff

- **Tester:** When Compose is ready, run the given command (or the new specs
  via that recipe) and leave a real red/pending proof. Soft-skipping because
  “no Docker” is wrong after a successful warmup.
- **Implementer:** Reuse the same command; do not re-warm unless exec fails.
- **Parent / orchestrator:** Warm once per `TDD_LOOP` entry (and again after a
  long idle or a failed exec). Pass the handoff string into both workers.

## Related skills

| Need | Skill |
|------|--------|
| Migrations, `migrate-spec-db`, `rails runner` via `tmp/` | **ryans-rails** |
| Authenticated GraphQL / HTTP against a running API | **ruby-api-tester** |
| How to write the tests themselves | **testing-philosophy** |

## Growth notes

Keep this skill thin. After live factory runs, append short bullets here (date +
bottleneck + change that helped). Promote repeated fixes into the procedure;
delete notes that no longer apply.

<!-- Live feedback accumulates below.
- YYYY-MM-DD: …
-->
