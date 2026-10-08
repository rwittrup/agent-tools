# RSP-186: touch test for `GetBeatsByCoordinates`

Local validation of the locations-api RPC added on
`feature/derive-beats-from-CFS-RSP-186-locations` (#30429). The Ruby consumer
is #30430, which is not covered here.

## What the feature does

`LocationsService.GetBeatsByCoordinates(dispatch_center_id, lat, lng)` returns
every polygon feature that contains the point, from the dispatch center's
`active` layers tagged `responders_filter`. Each beat is identified by
`layer_id` + `external_id` (the same identity responder check-in uses), plus a
`display_name`. A point in no beat returns an empty list, not an error.

## Files

| File | Purpose |
|---|---|
| `setup.sh` | Seeds locations-db with one layer, two adjacent beats, tagged `responders_filter` on a throwaway dispatch center. Idempotent. |
| `grpcurl.sh` | Calls the RPC at a known point: `inside`, `border` or `outside`. |

Seeded data: dispatch center `11111111-1111-4111-8111-111111111186`, layer
"RSP-186 Test Beats", Beat 101 (lng -105.00..-104.98) and Beat 102
(lng -104.98..-104.96), both at lat 39.73..39.75. They share one layer because
there is a unique index of one `responders_filter` layer per dispatch center.

## How to validate

Requires Docker, `just`, and `grpcurl` (`brew install grpcurl`). Run from the
repo root with the feature branch checked out.

1. Start locations-api. It must be built from the branch, since the RPC does not exist on trunk:

   ```bash
   just dc-start locations-migration locations-api
   ```

2. Seed the data:

   ```bash
   docs/uncad/validation/derive-cfs-beats-locations-rpc/setup.sh
   ```

   Expect `INSERT 0 1`, `INSERT 0 2`, `INSERT 0 1`, `COMMIT`, then a table
   listing Beats 101 and 102 under one `layer_id`.

3. Confirm the RPC is registered:

   ```bash
   grpcurl -plaintext -H 'authorization: local_locations_secret' \
     localhost:50055 list locations.LocationsService | grep Beats
   ```

4. Call it for each case and compare with the expected output below:

   ```bash
   docs/uncad/validation/derive-cfs-beats-locations-rpc/grpcurl.sh inside    # 39.74, -104.99
   docs/uncad/validation/derive-cfs-beats-locations-rpc/grpcurl.sh border    # 39.74, -104.98
   docs/uncad/validation/derive-cfs-beats-locations-rpc/grpcurl.sh outside   # 40.50, -100.00
   ```

5. Optional error case:

   ```bash
   grpcurl -plaintext -H 'authorization: local_locations_secret' \
     -d '{"dispatch_center_id":"nope","lat":1,"lng":1}' \
     localhost:50055 locations.LocationsService/GetBeatsByCoordinates
   ```

To exercise other behavior, edit `setup.sh` and re-run it. For example set the
layer's `layer_status` to something other than `active`, or drop the
`responders_filter` tag, and the same calls should return `{}`.

In a linked worktree the host port is offset. Check `just worktree-info` and
edit the port in `grpcurl.sh`.

## Results

| Step | Result | Verdict |
|---|---|---|
| `just dc-start locations-migration locations-api` | Migration exited cleanly; `locations-api` healthy; image built from this branch | ✅ |
| `setup.sh` | Inserted 1 layer, 2 beats, 1 association; committed. Layer `43fb8386-…` with Beats 101 and 102 | ✅ |
| Reflection (`list`) | `locations.LocationsService.GetBeatsByCoordinates` is registered | ✅ |
| `inside` (39.74, -104.99) | Beat 101 only, correct `layerId` | ✅ |
| `border` (39.74, -104.98) | Beats 101 and 102 (`ST_Covers` includes the edge) | ✅ |
| `outside` (40.50, -100.00) | `{}`, an empty list and not an error | ✅ |
| Bad UUID (`"nope"`) | `InvalidArgument: invalid dispatch_center_id format` | ✅ |

Sample `inside` output:

```json
{
  "beats": [
    { "layerId": "43fb8386-6e10-49dd-9bd3-1582e734c830", "externalId": "101", "displayName": "Beat 101" }
  ]
}
```

Notes:

- `externalId` prints as a string (`"101"`) because grpcurl renders int64 as a JSON string. The proto field is `int64`.
- The bad-UUID call makes grpcurl exit 67. That is expected.
- `layerId` varies per run because `setup.sh` generates a new one each time.

## Not covered

The Ruby half (#30430): `Cfs::DeriveBeats` and `cadIncident { beats }`.
