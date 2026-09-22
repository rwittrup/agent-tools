# Software factory

A ticket-to-PR pipeline. One chat, the orchestrator, holds a `Job` and dispatches five workers. Each worker sees only its slice. You write the spec before the pipeline starts, and you approve at four checkpoints.

## Workers

| Agent | Does | Sees |
|---|---|---|
| Planner | Three approaches, then one recommendation | The spec |
| Tester | Unit and integration tests in the repo | The spec and the approved approach |
| Implementer | Makes those tests pass, then refactors | The failing tests |
| Reviewer | Spec coverage and code review | The spec, the approach, the diff, the test manifest |
| Validator | The higher-level remainder, usually a happy path | The spec and the tester's tests |

The orchestrator creates the branch, tracks status and the circuit breakers, opens the pull request, and files a follow-up ticket when you say `fix later`. `pr-reviewer` is a separate agent for an already-open pull request.

The validator records the procedure it ran. A later regression run replays that recording.

## Circuit breakers

| Breaker | Limit | Result |
|---|---|---|
| Review loop-back | 2 | Commit, report, pull request labeled for you |
| Validation loop-back | 2 | Same |
| Attempts on one test | 10 | That test is marked stuck. The rest of the suite continues. A stuck test blocks validation. |

## How to start

Finalize the spec on the Jira ticket first (description, or an attachment). No agent drafts the spec inside the factory.

Open a new chat in the product repo and select the **orchestrator** agent. Paste:

```text
Ticket: <JIRA-KEY>

Start at PLANNING. Hold the Job in this chat. Dispatch each worker in its own context with only the slice the orchestrator defines. Stop at every human checkpoint and wait for me.
```

The orchestrator uses the current workspace as the product repo and loads `Job.spec` from the ticket (description, or attachment if that is where the spec lives). If the ticket has no usable finalized spec, it stops — it does not invent one.

## Where you step in

Reply in the orchestrator chat.

| Checkpoint | You reply |
|---|---|
| Plan approval | `approve plan` or `reject plan: <guidance>` |
| Validation triage | `fix now: <finding>` or `fix later: <finding>`, per finding |
| Circuit breaker | Read the report on the labeled pull request and decide in the chat. The pipeline will not take another automatic loop. |
| Pull request | Review the open pull request. Reply `merge` in the orchestrator chat when it is merged. |

You are not asked to approve each red/green cycle. You come back at plan approval, validation triage, a tripped circuit breaker, and the final pull request.
