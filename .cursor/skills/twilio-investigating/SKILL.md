---
name: twilio-investigating
description: Investigates Twilio voice and messaging issues by reading Twilio docs (MCP) and running matching CLI commands against live account data. Use when the user asks about Twilio calls, CallSids, phone numbers, webhooks, TwiML, transfers, call status, notifications, recordings, or telephony root-cause analysis.
---

# Twilio investigating

**Canonical path:** `.cursor/skills/twilio-investigating/SKILL.md` (this repo).

Use Twilio **docs** (MCP) to understand the problem, then the **CLI** to pull live data. MCP is docs-only; it cannot fetch calls or logs.

## When to use

Whenever the question involves **Twilio telephony or messaging** — CallSids, phone numbers, call status, webhooks, TwiML, transfers, or what Twilio recorded vs our app.

## Tools

| Tool | Role |
|------|------|
| **Twilio MCP** (`twilio__search`, `twilio__retrieve`) | Docs, error codes, TwiML, API operations and parameters |
| **Twilio CLI** (local) | Run those API operations against the account |

## MCP → CLI translation

Use `twilio__search` and `twilio__retrieve` to find the REST API operation and its parameters, then run the matching `twilio api:...` command (e.g. `FetchCall` → `twilio api:core:calls:fetch`). Prefer `-o json`.

## CLI setup

```bash
twilio profiles:use ryanw-nonemergency-prod
twilio config list   # confirm activeProfile
```

| Setting | Value |
|---------|--------|
| CLI profile | `ryanw-nonemergency-prod` |
| Subaccount | NonEmergency Prod (configured in the CLI profile) |

Use this profile for Prepared non-emergency production telephony unless the user specifies another account.

## Common starting commands

Adapt flags from `twilio__retrieve` — these are typical entry points, not an exhaustive list.

```bash
# Single call record
twilio api:core:calls:fetch --sid CAxxxxxxxx -o json

# Webhook + TwiML timeline for a call
twilio api:core:calls:events:list --call-sid CAxxxxxxxx -o json

# Delivery / error notifications
twilio api:core:calls:notifications:list --call-sid CAxxxxxxxx -o json

# Calls in a time window (by caller or called number)
twilio api:core:calls:list \
  --from +1XXXXXXXXXX \
  --start-time-after "2026-05-11T19:40:00Z" \
  --start-time-before "2026-05-11T20:05:00Z" \
  -o json

# Child or related leg after transfer/dial
twilio api:core:calls:fetch --sid CAyyyyyyyy -o json
```
