#!/usr/bin/env bash
# Stop call-handler. Pass --all to also stop the Rails/Redpanda compose stack.
cd "$(git rev-parse --show-toplevel)"
pkill -f 'bin/call-handler-api' 2>/dev/null
[[ "${1:-}" == "--all" ]] && just api stop
exit 0
