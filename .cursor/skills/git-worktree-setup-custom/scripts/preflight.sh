#!/usr/bin/env bash

# Fail fast when the AWS SSO session is gone. root-env.sh would otherwise block on a
# browser `aws sso login` that a non-interactive run can never finish.
#
# Usage: preflight.sh
# Exit:  0 session valid | 3 session missing or expired

set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-prepared-dev}"
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "preflight: no valid AWS SSO session for '${AWS_PROFILE}'." >&2
  echo "preflight: run  ! aws sso login --profile ${AWS_PROFILE}  then rerun." >&2
  exit 3
fi
