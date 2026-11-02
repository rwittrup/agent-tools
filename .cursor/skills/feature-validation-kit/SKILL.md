---
name: feature-validation-kit
description: Builds a validation kit for a feature, a directory of small setup and runner scripts that confirm the feature works as expected through a high-level happy path. Use when a story or PR needs a way to accept, smoke-test or regression-test a feature, after implementing (from the diff) or before (from the acceptance criteria).
---

# Feature validation kit

A **kit** is a directory of small scripts and a README that confirm a feature works as expected. Aim for a high-level happy path: a few named cases that show the feature doing its job, such as a point `inside`, on the `border` of, and `outside` a boundary.

`references/worked-example/` is a kit to copy the feel of.

## Naming and storage

- Store kits at `docs/<area>/validation/<feature-slug>/`.
- Name the slug for the feature and the layer under test (`derive-cfs-beats-locations-rpc`). The ticket key goes in the README title.
- Use paths relative to the kit, so it keeps working if the directory moves.



## Two tiers (Prepared911 API features)

For features reached through the Rails API (UNCAD/CFS and similar), build the kit from two tiers. The design is `docs/uncad/validation/DESIGN.md` and ADR 0001 (`docs/adr/0001-validation-kits-drive-state-over-the-api.md`); the shared pieces are in `docs/uncad/validation/{lib,entities,workflows}` and its README lists them. Copy a sibling kit (for example `cfs-unassign-unit-graphql`).

- **Workflow actions** (`workflows/`, bash + `curl` + `jq`): HTTP, GraphQL for dispatcher actions, REST for the CAD side. They create, transition and read state, and may call each other. All setup beyond the bare minimum, every state transition and every assertion goes through them. A missing action is added to `workflows/`, not written inline.
- **Entity operations** (`entities/`, Ruby via `rails runner`): direct DB writes, a last resort for setup that no HTTP path reaches. Each file opens with one line saying why no HTTP path exists. Never use one to make a transition, and never call a workflow from one.
- Personas (`persona dispatcher|supervisor|responder|superadmin`) are the engineer's own seeded users (`KIT_USER_EMAIL`, default `git config user.email`). Kits never create users or centers. Reruns create new rows tagged with the run tag and delete nothing; `just api reset-db` is the full reset.
- In-process assertions (query counts, job queues, stubbed flags, subscription recording) belong in RSpec, not a kit. List them under "Not covered".
- Flags are the engineer's to set. The README declares the flags the cases need; flag-off behavior is a documented re-run variant.

A kit is `README.md`, `setup.sh` (walkthrough state plus what to look at in Dispatch) and `validate.sh` (cases that each build their own CFS, PASS/FAIL per case, exit 1 on any FAIL, ending with a `Step | Result | Verdict` table to paste into the ticket). Print `key=value` on stdout and prose on stderr.

## Files

- **setup**: puts the environment into a known state for the cases.
- **runner(s)**: exercise the feature and show whether it behaved as expected.
- **README**: what the feature does, how to run the kit, and what the kit does not cover. Include a **Services needed** list (for example `rails-goodjob`, `locations-api`, `rails-ws`), and, for each manual step, the expected result and whether a reload is needed.

A `setup` or `runner` for a Prepared911 API feature is a bash script that composes `workflows/` and, only where no HTTP path exists, `entities/` (see Two tiers above). For other layers (gRPC, a service outside the Rails API), `just` commands or python scripts are fine.

## Principles

- **Idempotent.** Setup and runners are safe to rerun. To test another configuration, write another setup script. It can share the same runner with different flags or arguments.
- **Small and focused.** Each script does one job, and scripts combine to do more.
- **Compose with pipes.** If it's necessary or useful to pass data between scripts, prefer to write results to stdout so the next one can read them. For example, setup prints the IDs it created, and a runner reads them from stdin.
- **Take the user as arguments.** `setup` takes the login email and dispatch center (defaults: `rwittrup@prepared911.com`, `Engineering PD`), and any unit or identifier the cases use. Hardcoded users or units strand the person doing acceptance.
- **Parameterize.** Setup configures the environment for one aspect of the feature, and runners take arguments to exercise that aspect (`inside`, `border`, `outside`).

