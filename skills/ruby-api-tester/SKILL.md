---
name: ruby-api-tester
description: Exercise the local Rails API (GraphQL and HTTP) with a real OAuth token to match dispatch UI auth and validate DB-backed responses. Use when troubleshooting bugs, validating features end-to-end against Postgres, or comparing UI queries to raw API output. Covers token minting via rails runner, curl and script patterns, and GraphQL examples.
---

# Ruby API tester (local GraphQL / HTTP)

**Canonical path:** `.agents/skills/ruby-api-tester/SKILL.md`. Symlinks: `.agent/skills/ruby-api-tester`, `.cursor/skills/ruby-api-tester`, and `.claude/skills/ruby-api-tester` → this directory (same pattern as `commit-formatting`).

Use this workflow to run **authenticated** requests against the **Prepared Rails API** (`apps/ruby/api/`) the same way the dispatch UI does: **Doorkeeper Bearer token** + `POST /graphql`. This validates what GraphQL resolvers return from the database without guessing from models alone.

## When to use

- Reproduce or narrow a **chatroom / ANET / GraphQL** bug against **local** data
- Confirm a **schema field** or resolver returns what the **UI expects** after a migration or code change
- **Smoke-test** a query or mutation before wiring the client

## Prerequisites

- API reachable (typically `http://127.0.0.1:3000` from the host; GraphQL path is **`POST /graphql`**)
- **Docker** stack with `rails-api` (same as `just api …`)
- A **chatroom id** in the target dispatch center and at least one **approved** `UserDispatchCenter` row for a user on that center (the minter picks the lowest `user_id` among those users)

## Quick reference checklist

- [ ] Pick a `CHATROOM_ID` the test user should be allowed to read (same DC as production-like data you care about)
- [ ] Mint token: `just api rails runner tmp/rails-runner-mint-oauth-access-token.rb` (optional `CHATROOM_ID=…` in the environment **inside** the container—see below)
- [ ] `export ACCESS_TOKEN='…'`
- [ ] Run `curl`, **Python**, **Ruby**, or **Insomnia** against `/graphql` with `Authorization: Bearer`
- [ ] Compare JSON to the dispatch app’s Apollo documents under `turbo/apps/dispatch/` when validating UI parity

---

## Step 1: Mint an OAuth access token (recommended)

**Script (gitignored):** `apps/ruby/api/tmp/rails-runner-mint-oauth-access-token.rb`

Prints **one line**: the raw token string.

```bash
# From repo root — default CHATROOM_ID is embedded in the script; override by editing env in compose or copy script args pattern below.
export ACCESS_TOKEN="$(just api rails runner tmp/rails-runner-mint-oauth-access-token.rb)"
```

**Override chatroom** (any UUID in the target dispatch center):

```bash
# Often forwarded into `docker compose exec` with your local just setup:
CHATROOM_ID='your-chatroom-uuid' just api rails runner tmp/rails-runner-mint-oauth-access-token.rb
```

If `CHATROOM_ID` is unset inside the container, pass it explicitly (service name may match your compose file):

```bash
docker compose exec -e CHATROOM_ID='your-chatroom-uuid' rails-api \
  bundle exec rails runner tmp/rails-runner-mint-oauth-access-token.rb
```

Or temporarily change the default `ENV.fetch("CHATROOM_ID", …)` in the script.

**Properties of the minted token:**

- `resource_owner`: a `User` approved on the chatroom’s dispatch center
- `application_id`: `Doorkeeper::Application` named `prepared_live` (`Authentication::PreparedAuth::APP_NAME`) when present, else first app
- `scopes`: `me` (matches common dispatch authorization code grants)
- `expires_in`: 1 hour

Treat minted tokens like **passwords**; do not commit them or paste them into tickets.

---

## Step 2: Call GraphQL

**URL:** `GRAPHQL_URL` — default in helper scripts is often `http://127.0.0.1:3000/graphql`.

**Headers:**

- `Content-Type: application/json`
- `Authorization: Bearer <ACCESS_TOKEN>`

**Body shape:**

```json
{
  "query": "query Q($id: ID!) { chatroom(id: $id) { id label } }",
  "variables": { "id": "CHATROOM_UUID" }
}
```

**Auth note:** In development, **only** queries whose text includes the substring `Introspect` skip `psap_actors_authorize!`. Normal operation queries (e.g. `chatroom`, `nonemergencyCallTimeline`) **require** a valid Bearer token.

---

## Step 3: Example — ANET transcript timeline (UI parity)

The dispatch UI can show ANET conversation text from timeline transcript events. The API exposes a JSON string at:

`nonemergencyCallTimeline(chatroomId: ID!)`

**Reference script:** `dev/scripts/graphql_anet_chatroom_transcript.py`

- Reads `ACCESS_TOKEN` and optional chatroom id argv
- Parses timeline JSON and prints **caller** (`source: user`) vs **agent** (`source: agent`) transcript turns

```bash
export ACCESS_TOKEN="$(just api rails runner tmp/rails-runner-mint-oauth-access-token.rb)"
python3 dev/scripts/graphql_anet_chatroom_transcript.py YOUR_CHATROOM_UUID
```

Use the same field in **Insomnia** or **curl** to compare raw JSON to the UI.

---

## Patterns: compose a full check

| Approach | Pros | Cons |
|----------|------|------|
| **Bash + curl + jq** | No deps beyond jq | Escaping GraphQL strings |
| **Python** (`urllib`) | Easy JSON, one file | Need `python3` |
| **Ruby** `rails runner` + `Net::HTTP` or `Faraday` | Same process as models; can mint token in-process | Heavier boot; keep scripts in `tmp/` |

**Export token to a child script (bash):**

```bash
export ACCESS_TOKEN="$(just api rails runner tmp/rails-runner-mint-oauth-access-token.rb)"
./dev/scripts/your_check.sh
```

**One-liner curl:**

```bash
curl -sS -X POST "$GRAPHQL_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"query":"query { __typename }"}'
```

(`__typename` still requires a valid token unless the query string contains `Introspect`.)

---

## Step 4: Align with the UI

1. Find the **operation** in dispatch: search `turbo/apps/dispatch` for the GraphQL document name or field (e.g. `nonemergencyCallTimeline`, `chatroom(`).
2. Run the **same** selection set against local API with a minted token.
3. If results differ, trace: **LD flags**, **authorization** (`validate_read_chatroom!`), **purged** chatroom, **missing** `Nonemergency::Call`, or **replica** lag (Doorkeeper checks token on replica first).

---

## Rails runner discipline

Do **not** pass long Ruby strings to `just api rails runner "…"` from the shell (quoting breaks). Per `apps/ruby/AGENTS.md` / **ryans-rails** skill:

- Put ad-hoc code in `apps/ruby/api/tmp/*.rb`
- Run: `just api rails runner tmp/your-script.rb`

---

## Verification

- HTTP **200** and `errors` absent or understood
- `data` matches expectations for the chatroom/user you minted against
- For UI parity: same variables and fields as the client query

---

## Common mistakes

1. **No token** — `401` / `invalid_token`; mint again.
2. **Wrong dispatch center user** — minter user must be **approved** on the chatroom’s DC; otherwise chatroom query may 403 or return null where policy hides data.
3. **GraphQL string not escaped** in shell — use a `variables` file or Python/ruby script.
4. **Assuming introspection is anonymous** — only queries containing `Introspect` skip auth in dev.

---

## File quick reference

| Path | Purpose |
|------|---------|
| `.agents/skills/ruby-api-tester/SKILL.md` | This skill (edit here); `.agent` / `.cursor` / `.claude` skills trees symlink this folder |
| `apps/ruby/api/tmp/rails-runner-mint-oauth-access-token.rb` | Print one-line OAuth token for local API testing |
| `dev/scripts/graphql_anet_chatroom_transcript.py` | Example: GraphQL timeline transcript dump |
| `apps/ruby/api/app/controllers/graphql_controller.rb` | Auth gating for `/graphql` |
| `apps/ruby/api/config/routes.rb` | `post "graphql"` |
| `turbo/apps/dispatch/src/**/__generated__/**` | Client shapes to mirror |
