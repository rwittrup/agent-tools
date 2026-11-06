#!/usr/bin/env bash

# Replace .env's GOOGLE_CLIENT_SECRET with the value live-dev's live-api uses.
#
# Since SEC-562 Rails exchanges the Google code itself, so local Google login needs a secret
# Google accepts for the dispatch client. The 1Password value behind .env.1pass was rejected
# (invalid_client) while dev/api/dispatch_google_client in AWS Secrets Manager works.
#
# Never prints the value. On any failure, warns and keeps whatever .env already has.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

secret="$(aws secretsmanager get-secret-value --secret-id dev/api/dispatch_google_client \
  --query SecretString --output text 2>/dev/null | jq -r '.client_secret // empty' 2>/dev/null)"

if [[ -z "${secret}" || "${secret}" == "CHANGEME" ]]; then
  echo "inject-dev-google-secret: could not read dev/api/dispatch_google_client (aws sso login?); keeping .env's GOOGLE_CLIENT_SECRET, Google login may fail with invalid_client" >&2
  exit 0
fi

env_tmp="$(mktemp)"
grep -v '^GOOGLE_CLIENT_SECRET=' .env > "${env_tmp}" || true
printf 'GOOGLE_CLIENT_SECRET="%s"\n' "${secret}" >> "${env_tmp}"
mv "${env_tmp}" .env

echo "inject-dev-google-secret: GOOGLE_CLIENT_SECRET set from AWS (sha256 $(printf %s "${secret}" | shasum -a 256 | cut -c1-12))"
