#!/usr/bin/env bash
# Checks that must pass before any `just api` / `just dc-start` command, because those commands
# block on an interactive prompt when one of them fails.
#
# Usage: preflight.sh
# Exit: 0 ok | 1 not in a linked worktree | 2 Docker is not running | 3 AWS SSO session missing or expired
#
# Exit 3 is the one that matters: `just` runs `aws sso login`, which opens a browser and waits, and a
# background or buffered run looks hung until it times out. The login is the user's to do; this
# script prints the exact command and never starts it.

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

profile="${AWS_PROFILE:-prepared-dev}"

git_dir="$(git rev-parse --git-dir)"
git_common_dir="$(git rev-parse --git-common-dir)"
if [[ "${git_dir}" == "${git_common_dir}" ]]; then
  say "PREFLIGHT: ${ROOT_DIR} is the main checkout; these scripts are for linked worktrees."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  say "PREFLIGHT: Docker is not running. Start OrbStack, then rerun."
  exit 2
fi

if ! aws sts get-caller-identity --profile "${profile}" >/dev/null 2>&1; then
  say "PREFLIGHT: the AWS SSO session for profile '${profile}' is missing or expired."
  say "Ask the user to run this in the prompt, approve the browser sign-in, then rerun:"
  say "  ! aws sso login --profile ${profile}"
  exit 3
fi

say "PREFLIGHT: OK (worktree $(basename "${ROOT_DIR}"), docker up, aws profile ${profile})"
