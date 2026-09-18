# Goal
Periodically improve ANET auto-language detection in call-handler.
Desired outcome: exactly one small, focused PR — or nothing.

Product: ANET
Feature: auto-language detection
Primary service: call-handler
Known hotspots (start here, then follow dependencies):
- apps/go/call-handler (feature flags / wiring for auto language detection)
- apps/go/pkg/agent/prepared/langdetect
- apps/go/call-handler/datadog/language-detection
- related conversation/language-switch paths under apps/go if execution traces there

# Hard constraints
- Prefer zero change over a mediocre change. If nothing clearly helps growth, safety, or clarity — stop. Do not open a PR.
- At most one PR per run. Scope must be small and reviewable in one sitting.
- No drive-by refactors unrelated to language detection.
- Stay backwards-compatible across staggered deploys; do not flip production behavior via LD without strong evidence and tests.
- Do not remove an LD flag unless unused or a single value is effectively the permanent default and callers/tests prove it.
- If a finding needs a product decision, skip it this run (log it in the run summary) rather than guessing.

# Skills / philosophies to follow (by name)
When available in this environment, read and follow:
- feature-flags (LD keys, safe defaults, testing both sides)
- go-design-philosophy (idiomatic Go; test packages; no test-only exports)
- complexity-and-coupling-checking (co-change, complexity, coupling signals before choosing work)
- plan-3-approaches (three labeled approaches + Recommendation)
- planning-workflow (only the parts that apply to Go/backend; ignore frontend/turbo checklists)
- implementation-philosophy (prefer extract-then-implement / improve existing types over new branching)
- testing-philosophy / testing-principles (TDD; prefer integration-style when cheap)
- design-philosophy (composition; clear package boundaries)
- refactoring (behavior-preserving refactors separate from bugfixes)
- commit-formatting + graphite-branching + graphite + pr-formatting
- code-reviewing (high-level gate, then behavioral/quality/polish in parallel, then validator)

If a named skill is missing, follow the embedded rules below instead of inventing a new process.

# Embedded decision rules (always apply)
Worth shipping if ANY is true:
1. Makes the code easier to grow
2. Makes the code less likely to break
3. Makes the code easier to understand

Not worth shipping: speculative rewrites, cosmetic renames, “while I’m here” cleanups, large multi-concern PRs, removing dead-looking code without a reference/usage proof.

# Phase 1 — Map the feature
1. Map main components starting in call-handler auto-language detection wiring.
2. Follow imports into langdetect and other packages (e.g. agent).
3. Sketch the main execution paths: config/LD → detector/strategies → switch/decision → metrics/logging.
4. Optionally run complexity-and-coupling-checking scoped to those paths; treat results as candidates, not mandates.

# Phase 2 — Parallel opportunity scan
Use subagents in parallel (prefer cheap/auto models) to hunt only within the mapped paths:
A) Dead code / unused exports (including test-only references)
B) Impossible or unreachable branches
C) Obsolete LD flags / defaults that became permanent (use feature-flags conventions)
D) Edge-case bugs and likely regressions (nil, empty audio, unsupported languages, racey buffers, strategy ordering)

Each subagent returns concrete findings: file paths, why it matters, suggested tiny fix shape, confidence.

# Phase 3 — Select work
Gather findings. Pick at most one opportunity that meets the “worth shipping” bar and is safely completable in this run.
If none qualify: write a short run summary of top skipped candidates and exit without a branch/PR.

# Phase 4 — Plan
For the chosen finding only:
1. Produce three approaches using plan-3-approaches (Staff/Architect, Quick and Dirty, Wild Card) with Idea / Shape / Tradeoffs.
2. Recommend one approach or a small combination.
3. Align the plan with implementation-philosophy, testing-philosophy, design-philosophy, go-design-philosophy.

Pause briefly in the run log with the chosen approach before coding.

# Phase 5 — Implement
- TDD where practical: add/adjust tests first, then make them pass.
- Small commits via commit-formatting; keep the app green (failing new tests that drive the change are OK until green).
- Refactors must not mix bugfixes in the same commit (refactoring skill).
- Branch/PR mechanics via graphite-branching + graphite when available; otherwise equivalent git/gh flow.
- PR body via pr-formatting (Summary, Context, Changes, Acceptance/Validation).

# Phase 6 — Review before opening/updating the PR
Run code-reviewing on the branch diff vs main.
- If any high-severity directional issues: fix or abandon the PR.
- Address remaining high-confidence findings that are in scope; leave true nitpicks.

# Phase 7 — Outcome
- If still valuable after review: open/update exactly one draft PR and stop.
- If not: delete the branch / leave no PR and summarize why.

# Run summary (always)
End with:
- Mapped entrypoints
- Findings considered (one line each)
- Chosen work or “none”
- PR URL or “no PR”
