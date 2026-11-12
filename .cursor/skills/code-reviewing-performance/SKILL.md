---
name: code-reviewing-performance
description: Reviews a diff for performance regressions. Use when a diff adds a query, job, subscription or event handler, or loop on a write or request path, or when a reviewer comment questions its cost.
---

# Code Review — Performance

Cost is **multiplier × work per unit**. Review every **hot path** the diff touches: code that runs per write, per event, per request, or per subscriber.

## Questions

1. **Multiplier:** what runs how often? Name it: events/min × subscribers × rows scanned.
2. **Unbounded:** does the work grow with table history (closed, completed, deleted rows) rather than the live set? Bound it to the live set.
3. **Index:** can the planner use an index for every filter and group column, or does it fetch each row from the heap? Rows read should be close to rows returned.
4. **Moved:** when the diff moves work between client and server, or per-viewer to per-event, compare both costs at production volume.
5. **Flagged:** treat a reviewer's performance comment as a finding until measured. Defer it only with a number from production-scale data, never "tables are small".

Done when each query or job added on a hot path has a stated multiplier, a row bound, and an index.

# Inputs

- **code**: the diff to review
- **branch**: the branch/ref being reviewed, and its base

# Outputs

A JSON array of findings in the `code-reviewing` format, with `"type": "performance"`. Return `[]` when the diff touches no hot path. Severity follows the multiplier × row bound at production volume: `"high"` is large enough to load production, `"medium"` is a plausible cost that no one has measured, `"low"` is a small or already-bounded cost.

```json
[
  {
    "finding": "string — the hot path, its multiplier, and why the work is unbounded or unindexed",
    "location": "string 'path/to/file.ext:line' or null",
    "type": "performance",
    "severity": "high | medium | low"
  }
]
```

# Examples

## RSP-338: per-event CFS queue count

**Change:** Calls for Service (CFS) board counts moved from a per-viewer refetch to a count computed on every CFS event. A GoodJob job ran one grouped `COUNT(*)` over the dispatch center's `cad_incidents` for every create and update.

**Root cause:**
- **Multiplier:** every CFS write ran the query, whether or not anyone had the board open. Before, each open board ran two counts after a debounce.
- **Unbounded:** the grouped query had no `workflow_status` filter, so it read the center's whole CFS history. Only pending, active, assigned and on-hold rows count toward a queue. Cost grew with every call the center ever handled.
- **Index:** the partial index on `dispatch_center_id` where not deleted matched the center filter only. The group columns were not in it, so each row cost a heap fetch.
- **Flagged:** review said "N events means N counts". It was triaged as "depends on row count, a few hundred is fine" and deferred. After deploy, database CPU spiked.

**Fix:** a hotfix stopped the per-event count and restored the per-queue count resolver. The forward fix is `workflow_status IN (...)` plus a partial index built with `CREATE INDEX CONCURRENTLY`.
