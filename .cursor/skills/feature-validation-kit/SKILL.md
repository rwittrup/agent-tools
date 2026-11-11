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

Before writing a workflow, entity or setup step, read the cheat sheet in `docs/uncad/validation/README.md`: it lists every existing workflow and entity with its flags, and the action you need is often there already. When you add or extend a shared piece, update that cheat sheet and the layout in `DESIGN.md` in the same change.

- **Source every workflow at the top of a script, before the first `expect_` call.** Each workflow sources `lib/expect.sh`, which resets the results table and the failure count; a workflow sourced mid-run drops earlier rows and can turn an earlier FAIL into exit 0. `scripts/kit-run.sh` lints for this.
- **Measure each asynchronous transition before choosing a timeout.** Poll with timestamps and print each state change, then put the measured lag in the README. A guessed timeout was wrong in RSP-288: a stopped call stayed LIVE for about 148 seconds before reading ENDED.

## Simulated calls

A kit that needs a real call (call audio, transcript, live updates) uses the audio demo, not a factory chatroom: `workflows/start-audio-demo` starts a scripted call and prints `chatroom_id`; `workflows/get-chatroom-audio --wait live|ended|recorded` reads its state; `workflows/stop-audio-demo` ends it. Start it without the API's own CFS (the default): that CFS is CAD-owned, and Prepared911 refuses to assign units to it. Give the call a CFS a responder can work with `create-cfs`, then `entities/link-cfs-chatroom --id <cfs> --chatroom <chatroom_id>`, then `assign-cfs`. The environment needs `start-worktree-services/scripts/services-up.sh --audio`. `docs/uncad/validation/responder-my-call-audio-graphql/` is the worked example: opt-in `KIT_AUDIO_DEMO=1` cases in `validate.sh` and `KIT_LIVE_CALL=1` in `setup.sh`, so the default run stays fast and needs no audio pipeline.

## Running a kit

Run `validate.sh` through `bash ~/.claude/skills/feature-validation-kit/scripts/kit-run.sh <kit-dir>`, with any `KIT_*` opt-ins in the environment. It lints the kit's scripts, runs `validate.sh`, and cross-checks the PASS/FAIL lines against the results table and the exit code. Its last line is the verdict: `KIT-RUN: OK`, `FAIL`, or `INCONSISTENT REPORT` (a FAIL could be hidden behind exit 0; exit 7). A lint failure exits 6 before anything runs.

## Files

- **setup**: puts the environment into a known state for the cases.
- **runner(s)**: exercise the feature and show whether it behaved as expected.
- **README**: what the feature does, how to run the kit, and what the kit does not cover. Include a **Services needed** list (for example `rails-goodjob`, `locations-api`, `rails-ws`), and, for each manual step, the expected result and whether a reload is needed.

A `setup` or `runner` for a Prepared911 API feature is a bash script that composes `workflows/` and, only where no HTTP path exists, `entities/` (see Two tiers above). For other layers (gRPC, a service outside the Rails API), `just` commands or python scripts are fine.

## Principles

- **Idempotent.** Setup and runners are safe to rerun. To test another configuration, write another setup script. It can share the same runner with different flags or arguments.
- **Small and focused.** Each script does one job, and scripts combine to do more.
- **Compose with pipes.** If it's necessary or useful to pass data between scripts, prefer to write results to stdout so the next one can read them. For example, setup prints the IDs it created, and a runner reads them from stdin.
- **Take the user from the environment, never hardcode one.** Prepared911 API kits resolve personas from the engineer's own seeded users (`KIT_USER_EMAIL`, default `git config user.email`) and use the seeded Engineering PD (`KIT_CENTER_ID` overrides); they take no email arguments. Kits for other layers take the login email and center as arguments with no personal defaults. Units and other identifiers come from the run tag or arguments. A hardcoded user or unit strands the person doing acceptance.
- **Parameterize.** Setup configures the environment for one aspect of the feature, and runners take arguments to exercise that aspect (`inside`, `border`, `outside`).

