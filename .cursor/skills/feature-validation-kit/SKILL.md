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



## Files

- **setup**: puts the environment into a known state for the cases.
- **runner(s)**: exercise the feature and show whether it behaved as expected.
- **README**: what the feature does, how to run the kit, and what the kit does not cover.

A `setup` or `runner` can be any executable: bash and Ruby scripts are preferred. But other options include `just` commands, python scripts, etc.

## Principles

- **Idempotent.** Setup and runners are safe to rerun. To test another configuration, write another setup script. It can share the same runner with different flags or arguments.
- **Small and focused.** Each script does one job, and scripts combine to do more.
- **Compose with pipes.** If it's necessary or useful to pass data between scripts, prefer to write results to stdout so the next one can read them. For example, setup prints the IDs it created, and a runner reads them from stdin.
- **Parameterize.** Setup configures the environment for one aspect of the feature, and runners take arguments to exercise that aspect (`inside`, `border`, `outside`).

