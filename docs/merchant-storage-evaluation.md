# Merchant durable storage evaluation

**Issue:** [#19](https://github.com/joeycast/BitLocal/issues/19)  
**Date:** 2026-07-16  
**Decision:** **Keep single-file JSON** (`btcmap_elements_v4.json`) for now. Revisit SQLite when cold load or file size crosses the thresholds below.

## What we store today

| Artifact | Path (Caches) | Role |
|----------|---------------|------|
| Merchant catalog | `btcmap_elements_v4.json` | Full mapped `[Element]` after snapshot + incremental sync |
| Sync state | `btcmap_v4_sync_state.json` | Incremental anchor, last successful sync, schema version |
| CDN bootstrap | Network only | Thin snapshot: `id`, `lat`, `lon`, `icon` (+ optional boost/comments) |

Encode/decode is off a utility queue (`app.bitlocal.btcmap-cache-writes`). UI gets an in-memory array/`MerchantElementStore` after load.

## Measured baseline (2026-07-16)

### CDN snapshot (`places.json`)

| Metric | Value |
|--------|-------|
| Download size | **~2.0 MB** (gzip/CDN edge; raw file ~2.0 MB) |
| Records | **~28,900** |
| Fields | `id`, `lat`, `lon`, `icon` only |
| JSON parse (Python) | **~15 ms** |
| Avg bytes/record | **~71 B** |

### Local Element cache (simulator, post-sync)

| Metric | Value |
|--------|-------|
| File size | **~20 MB** |
| Elements | **~24,900** |
| Avg bytes/element | **~843 B** |
| File read (Python) | **~4 ms** |
| JSON parse (Python) | **~176 ms** |
| JSON re-encode (Python) | **~93 ms** |

Top-level keys observed: `id`, `uuid`, `osm_json`, `tags`, `created_at`, `updated_at`, `v4_metadata`.  
Nested `osm_json` accounts for a large share of size (~400 B average in a 500-record sample).

> Swift `JSONDecoder`/`JSONEncoder` for `Element` is expected to be **somewhat slower** than these Python numbers (more typed decoding). Treat ~0.2–1.0 s cold decode on device as the order of magnitude to watch with DEBUG timing logs.

## Options considered

### A. Keep single JSON file (current) — **chosen**

**Pros**

- Zero dependencies; matches “no external deps” product constraint
- Simple atomic write (`Data.write(options: .atomic)`)
- Merge semantics already unit-tested (`BTCMapRepository.mergeElements`)
- 20 MB is acceptable on modern iPhones; not in the multi-hundred-MB range

**Cons**

- Full catalog decode on cold start (no partial load)
- Full re-encode on each successful sync page finalization
- Peak memory ≈ file size + object graph

### B. SQLite (e.g. GRDB / raw SQLite)

**Pros**

- Partial reads by bbox / id
- Incremental upserts without rewriting 20 MB
- Scales past 50k–100k merchants more gracefully

**Cons**

- Schema migration + dual-read window during cutover
- Either add a dependency or hand-roll SQL
- More code for merge/delete/sync anchors
- Map still needs a substantial in-memory working set for annotations (viewport-filtered, but search/communities may need broader access)

### C. Chunked JSON / MessagePack / protobuf

**Pros**

- Smaller files / faster encode than pretty nested JSON
- Chunks could parallelize decode

**Cons**

- Still full-catalog mental model unless chunks are spatial
- Custom formats increase ops risk with little win at 20 MB

## Decision criteria (when to leave JSON)

Revisit SQLite (or another store) if **any** of the following holds for two consecutive releases:

1. **File size** regularly exceeds **40 MB** on device  
2. **Cold load** of `loadV4Elements` exceeds **1.0 s** median on iPhone-class hardware (DEBUG `sync` timings)  
3. **Merchant count** exceeds **~50,000** with merge/write jank visible on main-thread hops  
4. Product needs **true offline spatial queries** without loading the full array

## Near-term optimizations (stay on JSON)

These are lower risk than a storage migration:

1. **Stop encoding unused fields** — e.g. regenerating `uuid` (if still present) adds noise without value  
2. **Omit empty optionals** via custom encode or leaner DTO for disk  
3. **Log size + duration** on every load/save (instrumentation added alongside this doc)  
4. **Avoid intermediate full re-saves** during multi-page incremental sync when possible (final page only is ideal; intermediate saves already exist for crash resilience—trade carefully)

## Instrumentation

`BTCMapRepository` load/save paths log:

- element count  
- byte size  
- wall time in milliseconds  

Category: `sync` via `Debug.logTiming` / `Debug.logCache`.

## Summary

| Question | Answer |
|----------|--------|
| Is JSON still fine? | **Yes** at ~25k merchants / ~20 MB |
| Should we migrate now? | **No** |
| What would force a change? | 40 MB, 1 s cold load, 50k merchants, or query-shaped product needs |
| Next action | Monitor timing logs; consider leaner encode before SQLite |
