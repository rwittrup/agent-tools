---
name: setup-call-handler-tests
description: Bring up Rails and call-handler on a laptop and run an ANET text-sim scenario YAML end to end, without asking the user to do the setup. Use when asked to run a scenario / scenario-headless proof locally, or when a text sim needs a live call-handler. Laptop only; Cloud is anet-cloud-proof. For YAML format and the harness map see anet-text-sim.
---

# Set up call-handler and run a scenario (laptop)

You can do all of this yourself. The only human steps are the 1Password approval prompt and `aws login`. Do not ask the user to start services.

## Run it

Run from the prepared911 repo root; `S` is this skill's `scripts/` directory:

```bash
$S/up.sh          # Docker, AWS check, Rails+Redpanda (if down), call-handler (always rebuilt)
just call-handler scenario-headless cmd/text-conversation/feature_scenarios/<name>.yaml > out.jsonl
$S/summarize.py [output_dir] [--grep 'type/name regex']   # newest run by default
$S/down.sh [--all]   # stop call-handler; --all also stops Rails (just api stop)
```

`up.sh` exit codes: `0` ready; `2` needs the user (it prints which: `! aws login`, or approve the 1Password prompt / `! op signin`, then rerun); `1` failed (it prints the log tail). First Rails build takes minutes, so run `up.sh` with a long timeout or in the background. Logs: `$TMPDIR/call-handler-tests/`.

## Things you would not guess

- Do not pre-check 1Password with `op whoami`: your shell reports "not signed in" even when the recipes can sign in. Just run the recipes.
- Rails readiness is `:3000/healthz` (not `/up`); call-handler is `:7002/healthz`. Cloud `run-cloud*` recipes do not apply on a laptop.
- call-handler injects its own secrets (`LD_SDK_KEY` etc.) from `.env.1pass`; set no env vars.
- It `go build`s from the working tree on every start, so any Go change (or reverting a temporary edit) needs a restart. `up.sh` does this by default.
- Anything needing Docker, including `go test ./apps/go/call-handler/cmd/api/anet/` (testcontainers), panics with "rootless Docker not found" when OrbStack is off. `up.sh` starts it, or run `orb start`.
- Some agent environments block foreground `sleep`; wait with a background `until` loop. A background shell command that `&`-launches a process completes immediately, so that completion notice says nothing about the service.

## Gotchas that change the result

- **`success_count` / `results.json` `success` only mean the conversation completed.** The verdict is `post_call.verdict`; `summarize.py` prints it. Then confirm the events the ticket cares about occurred in the timeline.
- **Location scenarios need `verified_location_enabled: true`** in the YAML `defaults` (local DB default is false). Otherwise `verify_location`/`confirm_location` never run and the location is saved `ANET_UNVERIFIED`.
- **Unreleased LaunchDarkly flags are unknown locally** (warning "unknown feature key", default returned). To exercise a flag-gated path, temporarily hardcode the value in its getter in `cmd/api/anet/feature_flags.go`, rerun `up.sh`, run, then `git checkout` the file. Never commit the hardcode.
- A Vertex 400 followed by `llm_fallback_activated` (Bedrock) is benign here.
