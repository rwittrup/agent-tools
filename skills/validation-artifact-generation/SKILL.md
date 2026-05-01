---
name: validation-artifact-generation
description: Validation-before-implementation—plan, tests with minimal compile stubs, one runnable artifact (prefer integration/API-level checks when practical plus unit tests), red run and pause unless the plan is unit-test-only; aligned with implementer-v2.
---

# Skill: Validation Artifact Generator

## Purpose
Produce a complete, runnable validation artifact from a Linear ticket **before** the real implementation lands. The artifact is the TDD contract — fail first on red, pass when the feature is done.

Stay aligned with **implementer-v2** (`.cursor/agents/implementer-v2.md`): same sequencing, the **unit-test-only** shortcut below, and **Artifact storage** (ticket-scoped files under `.artifacts/`).

---

## Workflow order (use with implementer-v2)

1. **Validation plan** — §1; maps ACs to checks. Persist **`validation-plan.md`** under **`.artifacts/{LINEAR_TICKET}/`** when the plan is ready (see **Artifact storage**).
2. **Tests from the plan** — §2; write all tests; production code only **minimal stubs** so the project compiles/builds (not a working feature).
3. **Artifact** — §4; one entrypoint that runs tests **plus** any other validation commands the plan needs. Mirror that entrypoint into **`.artifacts/{LINEAR_TICKET}/`** as **`validation-artifact.sh`** or **`validation-artifact.md`**.
4. **Red + pause** — Run the artifact, confirm expected failures, **stop** for human review (they may re-run the artifact).  
   **Exception:** If the plan is **unit-test-only** (see below), skip pre-implementation artifact run and pause; implement with commits as appropriate, then run artifact + unit tests at the end.
5. **Implement** until green; **small, logical commits** per commit-formatting. When green, add **`implementation-summary.md`** under **`.artifacts/{LINEAR_TICKET}/`** (ticket-scoped summary of what changed).

---

## Unit-test-only shortcut

If the validation plan consists **solely** of unit tests (no integration tests, no queries against a running API/service, no multi-step shell script beyond invoking those tests), the agent **does not** need to run the artifact or pause before implementing. It should implement with commits when appropriate, then run the **artifact and unit tests** at the end to prove completion.

---

## Testing depth

- Prefer **higher-level** assertions in the artifact when practical: integration-style tests on **call-handler**, HTTP/GraphQL requests to a **running** Ruby API, etc.
- **Unit** tests (Go `testing`, RSpec, RTL) are **always** in scope when they are not prohibitively expensive—they cheaply lock behavior and edge cases.

---

## Inputs
- Linear ticket (full schema)
- Component layer: `call-handler` (Go) | `ruby-api` (Ruby) | `frontend` (React)

---

## Artifact storage (required)

At the **repository root**, maintain a durable copy of validation materials under **`.artifacts/{LINEAR_TICKET}/`** using the Linear issue key (e.g. `ANET-2636`). Create the directory if it does not exist. This matches **implementer-v2** and pairs with planner / validator / reviewer outputs in the same folder.

| File | Contents |
|------|----------|
| `validation-plan.md` | The numbered plan from §1 (steps, AC mapping, tools, pass criteria). |
| `validation-artifact.sh` **or** `validation-artifact.md` | The **single** consolidated runnable artifact from §4: a small script (executable when appropriate) **or** one markdown file with the exact copy-paste shell block, script paths, and `just` invocations—enough to re-run without the chat transcript. |
| `implementation-summary.md` | After implementation is complete and the artifact is green: short bullet summary of what changed and why (scoped to this ticket). |

If the canonical runnable script lives under **`dev/scripts/`** or next to the feature, keep it there for CI/repo conventions and **also** copy or reference it from **`validation-artifact.md`** under **`.artifacts/`** so the entrypoint is obvious.

**Related agent outputs** in the same **`.artifacts/{LINEAR_TICKET}/`** directory: planner (`plan.md`, `linear-tickets.md`), validator (`validation-report.md`, `validation-handoff.json`), reviewer (`review-notes.md`) — see `.cursor/agents/planner-v2.md`, `validator-v1.md`, `reviewer-v1.md`.

**Git:** `.artifacts/` is in the repository root **`.gitignore`**; these copies stay local unless that ignore rule is changed.

---

## What to Produce

### 1. Validation Plan
A numbered list of steps derived directly from the ticket's Acceptance Criteria.

Each step must include:
- A name
- Which AC it covers
- What will be run or checked
- What tool or method will be used
- What a passing result looks like (specific — not "tests pass" but "3 tests pass, including TestCallHandler_DroppedConnection")

### 2. Tests

Write tests **from the plan**. At artifact time, implement only **stubs** needed for compile/build.

**Go (call-handler):**
- Unit tests using standard `testing` package
- Integration tests in a `_test.go` file with a build tag if they require external services
- Table-driven tests where behavior varies by input
- Name tests descriptively: `TestFeatureName_Condition_ExpectedOutcome`

**Ruby (ruby-api):**
- RSpec unit and request specs
- A standalone Ruby script (`.rb`) for any DB validation that needs to run outside the test suite
- Scripts should be runnable with `ruby script_name.rb` and print clear pass/fail output

**Frontend (React):**
- React Testing Library unit tests for all new or modified components
- Tests should cover: render, user interaction, and edge cases
- Do not test implementation details — test behavior

### 3. SQL Queries
If the ticket's validation involves DB state:
- Write queries as `.sql` files or inline in the validation plan
- Include expected output shape
- Include a cleanup query if the validation inserts test data

### 4. Runnable validation artifact (single thing to run)

Prefer **existing** `just` recipes and project conventions instead of adding a new `validate-[component]` target to a justfile. Wire the plan into commands that already work in this repo (for example `just api …`, `just dc-exec rails-api …`, `go test …`, `pnpm turbo run …`).

The artifact is **not** limited to one test file. It can be any combination that proves the ticket:

- Multiple spec files or `go test -run` patterns
- A `rails runner` script plus HTTP checks (`curl` against a local endpoint)
- Mixed layers in sequence

When several steps are needed, consolidate into **one** deliverable a human or agent can execute without hunting:

- A **small bash script** checked in under `dev/scripts/` or next to the feature (document the path in the plan), or
- A **single fenced block** of shell lines meant to be run in order (copy-paste friendly), or
- One existing `just` invocation if a single recipe covers everything

Regardless of where the script lives in-repo, mirror the **same** entrypoint under **`.artifacts/{LINEAR_TICKET}/`** per **Artifact storage** (`validation-artifact.sh` or `validation-artifact.md`).

**Ruby API example** (reuse `dc-exec`; adjust paths to match the ticket):

```bash
just dc-exec rails-api env RUBY_DEBUG_ENABLE=0 bundle exec rspec \
  spec/models/nonemergency/call_timeline_event_spec.rb \
  spec/services/nonemergency/agent_turn_annotations_resolver_spec.rb \
  spec/graphql/types/nonemergency/agent_turn_annotation_spec.rb \
  spec/graphql/types/chatroom_agent_turn_annotations_spec.rb \
  --format documentation
```

**Multi-step example** (same artifact block — run top to bottom):

```bash
just api rails runner tmp/some_validation.rb
curl -sf http://127.0.0.1:3000/some/path | jq .
go test -run SomeTests ./path/to/package/...
```

**Quality bar:** There must be exactly **one** artifact to run or paste — not scattered instructions without a single entrypoint.

---

## TDD Gate (red run + pause)

After tests and artifact exist, **run** the artifact and confirm **failure** for expected reasons.

**Unless** the **unit-test-only shortcut** applies: **stop** and do not implement the feature yet.

Present the artifact to the human with the **exact** command(s) or script path from section 4, for example:

```
Validation artifact ready. Please run:

    <the consolidated command, script path, or paste block from §4>

Confirm it fails as expected, then give the go-ahead to proceed with implementation.
```

---

## Layer Reference

| Layer | Language | Test Framework | DB Access |
|---|---|---|---|
| call-handler | Go | `testing` + `testify` | Direct via test DB |
| ruby-api | Ruby | RSpec | ActiveRecord / raw Ruby script |
| frontend | React | React Testing Library | N/A |

---

## Quality Bar for Tests
- Tests must test behavior, not implementation
- Each test should have one clear reason to fail
- If a test requires significant setup, that setup belongs in a helper or fixture — not inline
- Integration tests must be runnable in CI without manual intervention
