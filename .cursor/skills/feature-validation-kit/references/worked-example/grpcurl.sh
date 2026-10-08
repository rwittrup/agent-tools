#!/usr/bin/env bash
# Calls GetBeatsByCoordinates against the data seeded by setup.sh.
# Usage: grpcurl.sh [inside|border|outside]   (default: inside)
set -euo pipefail

DC_ID="11111111-1111-4111-8111-111111111186"
case "${1:-inside}" in
  inside)  LAT=39.74; LNG=-104.99 ;;   # expect Beat 101 only
  border)  LAT=39.74; LNG=-104.98 ;;   # expect Beat 101 and Beat 102
  outside) LAT=40.50; LNG=-100.00 ;;   # expect {} (no beats)
  *) echo "usage: $0 [inside|border|outside]" >&2; exit 1 ;;
esac

grpcurl -plaintext -H 'authorization: local_locations_secret' \
  -d "{\"dispatch_center_id\":\"${DC_ID}\",\"lat\":${LAT},\"lng\":${LNG}}" \
  localhost:50055 locations.LocationsService/GetBeatsByCoordinates
