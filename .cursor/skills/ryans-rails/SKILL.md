---
name: ryans-rails
description: Local Prepared Rails API workflows for Ryan. Use when adding or applying database migrations, or when inspecting the Rails app or database from the Dockerized API. Covers just api migrate, test DB prep, and running rails runner via a small script under apps/ruby/api/tmp (avoid inline runner strings).
---

# Ryan’s Rails API (local Docker)

Conventions for the **Ruby API** at `apps/ruby/api/`, run **inside Docker** via `just`. Work from the **repository root** unless a command is explicitly scoped to `apps/ruby/api/`.

---

## Quick reference checklist

**Migrations**

- [ ] After new or updated files under `apps/ruby/api/db/migrate/`, or after pulling migration changes: run `just api migrate` (see below).
- [ ] If you need **test/parallel** DBs in sync with schema: run `just api migrate-spec-db` after migrate (see below).

**Database / Rails inspection**

- [ ] Add a **small Ruby file** under `apps/ruby/api/tmp/` (naming below).
- [ ] Run it with `just api rails runner tmp/<filename>.rb` from the repo root.
- [ ] Do **not** pass multi-word or quoted Ruby as a single `rails runner` argument via `just api rails runner "…"` — that path breaks (see [Why not inline `rails runner`](#why-not-inline-rails-runner)).

---

## 1. Run migrations (`just api migrate`)

**When:** There are new or changed migrations, or you need the local dev DB brought up to date and model annotations refreshed.

**Command (from repo root):**

```bash
just api migrate
```

**What it does (high level):** Starts the `rails-migrate-db` Compose service, streams logs, waits for success, then runs `bundle exec annotate` inside `rails-api`. Requires **Docker** (e.g. OrbStack) and the same **root env / secrets** setup as other `just dc-*` commands (e.g. `_root-env` / 1Password where configured).

**If migration fails:** Read the `rails-migrate-db` log output; fix the migration or local DB state, then re-run.

### Test / parallel databases

**When:** You need the **spec** databases aligned after schema changes (e.g. before `parallel:spec` or integration tests that hit migrated schema).

**Command:**

```bash
just api migrate-spec-db
```

This runs `parallel:prepare` (with `SKIP_POSTGIS_DB_SETUP=true`) inside `rails-api`. Use **in addition** to `just api migrate` when tests need the updated schema.

**Related (do not use for routine “new migration” flow unless you intend these):**

- `just api rollback` — roll back one migration (primary DB).
- `just api rollback_version VERSION=<timestamp>` — migrate down to a specific version.

---

## 2. Inspect DB / Rails with `rails runner` and a `tmp/` script

**When:** You need ad-hoc queries, counts, or Rails console–style checks against the **local** API app and DB — including from an automated agent that cannot use an interactive `just api rails c`.

### Step A — Create a script under `apps/ruby/api/tmp/`

**Directory:** `apps/ruby/api/tmp/` (contents are gitignored except `tmp/.keep`; do not commit inspection scripts).

**Naming:** Use a clear, unique name, for example:

- `rails-runner-<topic>-<YYYYMMDD>.rb`  
  e.g. `rails-runner-user-count-20260410.rb`

Keep scripts **short**, **read-only** unless the task explicitly requires writes, and **idempotent** where possible.

**Example template:**

```ruby
# frozen_string_literal: true

# Ad-hoc inspection — safe to delete after use.
puts "Time.current: #{Time.current.iso8601} (#{Time.zone.name})"

# Example: ActiveRecord (adjust model/table as needed)
# puts "User count: #{User.count}"
```

Use full application context (models, `ActiveRecord::Base.connection`, etc.) as appropriate.

### Step B — Run from the repository root

```bash
just api rails runner tmp/<your-file>.rb
```

Path is relative to the Rails app root as seen in the container (`/app`), which matches `apps/ruby/api` on the host.

**Permissions:** These commands need access to **Docker** (same as other `just dc-exec` / `just api` workflows). In restricted environments, request full permissions so the shell can reach the Docker socket.

### Step C — Cleanup (optional)

Delete the script when finished if you want to avoid clutter; `tmp/` is ignored by git.

---

## Why not inline `rails runner`

The API `just` recipe expands `rails` arguments without shell-style quoting:

```256:258:apps/ruby/api/justfile
@rails *ARGS:
  cd ../../../
  just dc-exec rails-api env RUBY_DEBUG_ENABLE=0 bundle exec rails {{ ARGS }}
```

So `just api rails runner "puts Time.current"` becomes multiple argv tokens after `runner`, not one Ruby program. **A file path works:** `just api rails runner tmp/foo.rb` passes `runner` and `tmp/foo.rb` correctly.

**Do not rely on** long one-liners or semicolon-separated Ruby in the `just` CLI for this recipe.

**Alternatives (advanced):** `docker compose exec rails-api bash -lc 'bundle exec rails runner "...complex..."'` with careful quoting, or `just dc-exec rails-api …` — still prefer a `tmp/` file for clarity and repeatability.

---

## Interactive console (human use)

For an interactive REPL, use:

```bash
just api rails c
```

That is **not** suitable for non-interactive agents; use the `tmp/` + `rails runner` pattern above instead.

---

## Verification

| Goal | Check |
|------|--------|
| Migrations applied | `just api migrate` exits 0; migrate logs show success; annotate runs. |
| Spec DBs updated | `just api migrate-spec-db` exits 0 when needed for tests. |
| Runner script | `just api rails runner tmp/<file>.rb` prints expected output without Ruby argv errors. |

---

## File quick reference

| Path | Role |
|------|------|
| `apps/ruby/api/db/migrate/` | Migration files |
| `apps/ruby/api/tmp/` | Short-lived `rails-runner-*.rb` inspection scripts (gitignored) |
| `apps/ruby/api/justfile` | `migrate`, `migrate-spec-db`, `rails`, etc. |
| Root `justfile` | `just api <cmd>` delegates to `apps/ruby/api/justfile` |
