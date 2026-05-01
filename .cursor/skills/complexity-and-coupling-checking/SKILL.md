---
name: complexity-and-coupling-checking
description: Identifies hidden complexity and tight coupling via co-change frequency, cyclomatic complexity, package coupling, and file-size signals; outputs a structured report for planning and redesign. Use before multi-file changes, when a PR feels oversized, for periodic component health checks, or when failures surface in unexpected places.
---

# Skill: Complexity & Coupling Checker

## Purpose
Identify areas of the codebase that are accumulating hidden complexity or tight coupling — before they become problems. Output feeds back into the Planner as redesign candidates.

---

## When to Use
- Before planning a change that touches multiple files
- When a PR feels larger than it should be
- As a periodic health check on a component
- When something keeps breaking in unexpected places

---

## Analysis 1: Co-Change Frequency

Files that change together frequently are often more tightly coupled than the architecture suggests.

**How to run:**
```bash
# Files that changed together in the last 90 days
git log --since="90 days ago" --name-only --pretty=format: | \
  sort | uniq -c | sort -rn | head -40
```

```bash
# Pairs of files that changed in the same commit
git log --since="90 days ago" --name-only --pretty=format:"COMMIT" | \
  awk '/COMMIT/{if(files) for(f in files) for(g in files) if(f<g) print f"|"g; delete files; next} {files[$0]=1}'| \
  sort | uniq -c | sort -rn | head -20
```

**What to look for:**
- Files in different packages/layers changing together → likely hidden dependency
- A single file appearing in most commits → potential god object
- Test files and implementation files that aren't paired → missing coverage or dead code

---

## Analysis 2: Cyclomatic Complexity

**Go:**
```bash
# Install if needed
go install github.com/fzipp/gocyclo/cmd/gocyclo@latest

# Check for high-complexity functions (threshold 10 is a reasonable starting point)
gocyclo -over 10 ./...
```

**Ruby:**
```bash
# Using flog
gem install flog
flog app/

# Using rubocop
bundle exec rubocop --only Metrics/CyclomaticComplexity,Metrics/MethodLength
```

**What to look for:**
- Functions with cyclomatic complexity > 10 are candidates for decomposition
- Methods over 30 lines usually have multiple responsibilities
- High complexity in a file that also has high co-change frequency is a strong refactor signal

---

## Analysis 3: Package / Module Coupling

**Go — identify import fan-in (things everything depends on):**
```bash
# List all imports across the codebase and count references
grep -r '"' --include="*.go" -h | grep -oP '(?<=")\S+(?=")' | sort | uniq -c | sort -rn | head -20
```

**What to look for:**
- Internal packages with high fan-in that aren't utilities → likely doing too much
- Circular dependencies (Go will error, but Ruby won't — check manually)
- A domain package importing from an infrastructure package → layer violation

---

## Analysis 4: File Size as a Signal

Large files aren't always a problem, but they're worth examining:

```bash
# Largest files by line count
find . -name "*.go" -o -name "*.rb" | xargs wc -l | sort -rn | head -20
```

Flag files over 300 lines for review. Over 500 lines almost always warrants decomposition.

---

## Output Format

Produce a structured report for the Planner:

```markdown
## Complexity & Coupling Report
**Date:** [date]
**Scope:** [component or full codebase]

### High-Frequency Co-Changes
| Files | Commits Together | Signal |
|---|---|---|
| `file_a.go` + `file_b.go` | 14 | Hidden dependency — consider explicit interface |

### High-Complexity Functions
| File | Function | Complexity | Recommendation |
|---|---|---|---|
| `handler.go` | `ProcessCall` | 18 | Decompose — multiple responsibilities |

### Coupling Concerns
- `internal/callhandler` imports from `internal/db` directly — should go through a repository interface
- `TranscriptionService` referenced by 7 packages — candidate for interface extraction

### Refactor Candidates
Ranked by risk/reward:
1. **`ProcessCall` in `handler.go`** — high complexity, high change frequency, no interface boundary
2. ...
```

---

## Feeding Back to the Planner
This report is an input to the Planner's design phase — not a mandate. Flag patterns, let the Planner decide whether to include refactor work in the current plan or create separate tickets.
