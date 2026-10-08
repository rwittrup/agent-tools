#!/usr/bin/env bash
# Seeds the local locations-db with one active polygon layer (two adjacent
# "beats") tagged RESPONDERS_FILTER for a throwaway dispatch center.
# Idempotent: re-running wipes and recreates the RSP-186 test layer.
# Run from the repo root after `just dc-start locations-migration locations-api`.
set -euo pipefail

DC_ID="11111111-1111-4111-8111-111111111186"
LAYER_EXT_ID="rsp-186-test-beats"

docker compose exec -T locations-db psql -U postgres -d locations -v ON_ERROR_STOP=1 <<SQL
BEGIN;

-- Clean up any previous run
DELETE FROM dispatch_center_layer_associations
 WHERE dispatch_center_id = '${DC_ID}';
DELETE FROM layer_polygon_features
 WHERE layer_id IN (SELECT id FROM layer_metadata WHERE external_id = '${LAYER_EXT_ID}');
DELETE FROM layer_metadata WHERE external_id = '${LAYER_EXT_ID}';

-- The layer
INSERT INTO layer_metadata (name, feature_type, layer_status, source, external_id)
VALUES ('RSP-186 Test Beats', 'polygon', 'active', 'manual', '${LAYER_EXT_ID}');

-- Two side-by-side beats (Denver area), authored in WGS84, stored in 3857:
--   Beat 101: lng -105.00..-104.98   Beat 102: lng -104.98..-104.96   (lat 39.73..39.75)
INSERT INTO layer_polygon_features (layer_id, name, source, external_id, geom)
SELECT lm.id, v.name, 'manual', v.external_id,
       ST_Multi(ST_Transform(ST_MakeEnvelope(v.min_lng, 39.73, v.max_lng, 39.75, 4326), 3857))
FROM layer_metadata lm
CROSS JOIN (VALUES
  ('Beat 101', 101::bigint, -105.00, -104.98),
  ('Beat 102', 102::bigint, -104.98, -104.96)
) AS v(name, external_id, min_lng, max_lng)
WHERE lm.external_id = '${LAYER_EXT_ID}';

-- Attach to the dispatch center as its responders-filter layer
INSERT INTO dispatch_center_layer_associations (dispatch_center_id, layer_id, boundary_usage)
SELECT '${DC_ID}', id, ARRAY['responders_filter']::layer_boundary_usage[]
FROM layer_metadata WHERE external_id = '${LAYER_EXT_ID}';

COMMIT;

SELECT lm.id AS layer_id, f.external_id, f.name FROM layer_metadata lm
JOIN layer_polygon_features f ON f.layer_id = lm.id
WHERE lm.external_id = '${LAYER_EXT_ID}' ORDER BY f.external_id;
SQL

cat <<EOF

Seeded dispatch center ${DC_ID}. Try docs/uncad/validation/derive-cfs-beats-locations-rpc/grpcurl.sh
EOF
