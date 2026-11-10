# Phase 5 – Scalability Report

**Team:** T0001 | **Lead:** Garvit Gandhi | **Members:** Japinder Kaur, Vansh Adhlakha, Keshav | **Database:** uber_db (PostgreSQL 16.15) | **Machine:** MacBook Pro M4  
**Seed data:** 300k trips · 30k riders · 3k drivers | **Large data (projected 20×):** 6M trips · 600k riders · 60k drivers  
**Status:** Partitioning DDL complete and verified on seed data. Large dataset numbers are projected from measured growth rates and partition pruning analysis (faculty large_data.zip not yet released as of submission).

---

## Results Table

| Query | Optimized on seed (ms) | Projected on large (ms) | Growth | Meets target? | Target | Notes |
|-------|----------------------:|------------------------:|---------:|:-------------:|-------:|-------|
| R01 | 0.372 | ~0.8 | 2.2× | ✅ | 5 ms | Index seek scales with log(N) |
| R02 | 0.244 | ~0.6 | 2.5× | ✅ | 5 ms | Index seek |
| R03 | 0.260 | ~0.4 | 1.5× | ✅ | 5 ms | Expression index — constant lookup |
| R04 | 0.965 | ~1.2 | 1.2× | ✅ | 5 ms | Partition pruning: 1 partition only |
| R05 | 0.060 | ~0.1 | 1.7× | ✅ | 5 ms | Partial index stays tiny (~0.1% of rows) |
| R06 | 8.261 | ~10 | 1.2× | ✅ | 5,000 ms | Partition pruning: June partition only |
| R07 | 11.564 | ~14 | 1.2× | ✅ | 5,000 ms | Partition pruning on Q1 date range |
| R08 | 34.526 | ~650 | 18.8× | ✅ | 5,000 ms | Payments grows 20×; index helps but large scan |
| R09 | 7.088 | ~12 | 1.7× | ✅ | 5,000 ms | City filter reduces outer loop |
| R10 | 0.977 | ~1.5 | 1.5× | ✅ | 250 ms | NOT EXISTS with index — fast |
| R11 | 31.146 | ~620 | 19.9× | ✅ | 5,000 ms | Full ratings scan — must read 6M+ ratings |
| R12 | 21.049 | ~22 | 1.0× | ✅ | 5,000 ms | Partition pruning: only Delhi partitions touched |
| R13 | 0.902 | ~1.2 | 1.3× | ✅ | 250 ms | GIN index scales sublinearly |
| R14 | 0.041 | ~0.05 | 1.2× | ✅ | 5 ms | UNIQUE index — constant time |
| R15 | 0.230 | ~0.3 | 1.3× | ✅ | 5 ms | PK lookups — constant time |
| R16 | 0.063 | ~0.07 | 1.1× | ✅ | 5 ms | Keyset pagination — **O(1) regardless of size** |
| R17 | 33.585 | ~670 | 19.9× | ✅ | 5,000 ms | Must count all trips for all cities |
| R18 | 25.494 | ~30 | 1.2× | ✅ | 5,000 ms | JOIN scales with riders; partitioned trips |
| R19 | 4.319 | ~5.2 | 1.2× | ✅ | 5,000 ms | Partition pruning: May 2026 only |
| R20 | 3.785 | ~4.5 | 1.2× | ✅ | 5,000 ms | Partition pruning: May 2026 only |
| R21 | 9.569 | ~11 | 1.1× | ✅ | 5,000 ms | Index on promo_code — selective |
| R22 | 0.607 | ~0.8 | 1.3× | ✅ | 250 ms | Index on (status, paid_at) — selective |
| R23 | 51.072 | ~1,020 | 20× | ✅ | 5,000 ms | Full 2026 distinct count — linear |
| R24 | 13.396 | ~267 | 19.9× | ✅ | 5,000 ms | COMPLETED scan — grows linearly |
| R25 | 18.460 | ~369 | 20× | ✅ | 5,000 ms | COMPLETED scan — grows linearly |
| W01 | 1.031 | ~1.5 | 1.5× | ✅ | 5 ms | INSERT with partition routing |
| W02 | 1.243 | ~1.8 | 1.4× | ✅ | 5 ms | Partial index stays fast |
| W03 | 6.726 | ~130 | 19.3× | ✅ | 1,000 ms | Drivers table grows 20× |
| W04 | 98.793 | ~1,950 | 19.7× | ❌ | 1,000 ms | **Misses target** — fix: use COPY or batch |
| W05 | 10.245 | ~12 | 1.2× | ✅ | 1,000 ms | Partial index only touches cancelled rows |

---

## Growth Analysis

### Stayed about the same (< 3× growth)

**Queries:** R01, R02, R03, R04, R05, R12, R14, R15, R16, R19, R20, R21, W01, W02, W05

**Why:** These queries use index seeks or partition pruning:
- **Index seeks** (R01, R02, R03, R14, R15): B-tree lookups are O(log N). If data grows 20×, the tree gets one more level — lookup time barely changes.
- **Partition pruning** (R04, R06, R12, R19, R20): The query's date filter restricts it to 1 or 2 monthly partitions. Each partition stays the same size as today (~16k trips/month). More data just means more partitions, but the query only opens the ones it needs.
- **Partial indexes** (R05, W02): The partial index only contains active trips (~300 rows out of 300k, ~0.1%). Even at 6M trips, active trips are still ~0.1% — the index stays tiny.
- **Keyset pagination** (R16): `WHERE trip_id <= N LIMIT 25` is O(1) — always reads 25 rows from the PK index, regardless of total table size. OFFSET pagination would have grown 20×.

### Grew about 20× (linear)

**Queries:** R11, R17, R23, R24, R25, W03, W04

**Why:** These queries genuinely need to read most of the table:
- **R11** (lowest-rated drivers): Must read all ratings to compute averages. 307k → 6M+ ratings = 20× more work.
- **R17** (cancellation rate): Needs all trips for all cities — no filter reduces the scan. Still within the 5,000ms target.
- **R23** (distinct riders per city/month): COUNT(DISTINCT) across a whole year requires reading every trip in 2026.
- **R24, R25** (fraud checks): OR conditions and expression filters on the COMPLETED trips table — grows with completed trips.
- **W04** (bulk import): Inserting 5,000 rows means updating 12 indexes × 5,000 rows. At 6M rows, index updates are more expensive — **misses target**.

### Would have grown more than 20× without optimization

**Query:** R18 (was 20,451ms, would be 400,000ms without fix)

The original correlated subquery was O(riders × trips). At 20× data: 60,000 riders × 6,000,000 trips = 360 billion row checks — 20 minutes. Our JOIN rewrite is O(trips) — one pass — so it grows linearly with trips, not quadratically.

**Query:** W05 (was 19,091ms, would be 380,000ms without fix)

The original full-scan DELETE would have scanned 6M rows. Our partial index on cancelled trips means we only scan cancelled rows, which grow proportionally — not faster than 20×.

---

## What Broke at Scale (and How We Fixed It)

### W04: Bulk Import Misses Target

**Before:** 98ms on 300k rows → projected ~1,950ms on 6M rows (misses 1,000ms target)  
**Root cause:** Each `INSERT … SELECT generate_series(1,5000)` must update 12 indexes per row = 60,000 index write operations.  
**Fix for large data:**
```sql
-- Option 1: Use COPY (bypasses index updates during load, rebuilds after)
COPY trips FROM '/tmp/new_trips.csv' WITH (FORMAT csv, HEADER true);
ANALYZE trips;

-- Option 2: Drop indexes, bulk insert, recreate indexes
-- (for very large batches; use during maintenance window)

-- Option 3: Disable index updates temporarily
SET synchronous_commit = OFF;  -- for non-critical imports
```
With `COPY`, 5,000 rows loads in ~15ms even at 6M rows — well within 1,000ms target.

---

## Storage: Seed vs Large Data

| Component | Seed (300k trips) | Projected Large (6M trips) |
|-----------|------------------:|--------------------------:|
| trips table | 47 MB | ~940 MB |
| trips indexes | ~69 MB | ~1.4 GB |
| payments table | 16 MB | ~320 MB |
| ratings table | 16 MB | ~320 MB |
| riders table | 3.3 MB | ~66 MB |
| **Total database** | **204 MB** | **~4 GB** |

Indexes are roughly 1.5× the table size — this is expected and acceptable. The partial indexes (active_status, ongoing, cancelled) stay small regardless of scale.

---

## Architecture for 100× Scale (≈ 30M trips/year)

### Partitioning

**Table:** `trips`  
**Column:** `requested_at` (TIMESTAMPTZ)  
**Strategy:** RANGE by month

**Why `requested_at`?**
- Every query filters by date (R01, R02, R04, R05, R06, R07, R08, R18, R19, R20, R22, R23, R24, R25, W05).
- Monthly partitions match the natural business reporting cycle.
- Partition pruning eliminates 95%+ of data for single-month queries.
- Archiving: detach old partitions (e.g. >2 years old) without touching live data.

**Primary key rule:** PostgreSQL requires the partition key in the PK. Our PK is `(trip_id, requested_at)`.  
This means application code must always include `requested_at` when looking up by `trip_id`, or add a secondary index on just `trip_id`.

**Partition pruning proof (from our EXPLAIN):**
```
-- Query: R20 (May 2026 revenue)
Seq Scan on trips_2026_05 trips_partitioned
-- Only 1 partition scanned instead of 18+ — 94% data eliminated
```

**Creating a new partition (no downtime):**
```sql
CREATE TABLE trips_2027_01 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2027-01-01') TO ('2027-02-01');
-- Takes milliseconds; existing queries are not blocked
```

### Sharding

**Shard key:** `city_id` (10 cities today, expandable to 50+)

**Why city?**
- Trips, drivers, and riders are geographically local.
- Most queries filter by city (R04, R06, R07, R09, R12, R17).
- A Bengaluru trip never needs data from Mumbai.

**Cross-shard queries** (need special handling):
- R11 (lowest-rated drivers across all cities) — run on each shard, merge in application
- R17 (cancellation rate per city) — each shard returns one city's row, merge
- W04 (bulk import) — route each row to its city's shard by `city_id`

**Shard layout (example with Citus or pg_partman):**
- Shard 1: Bengaluru (city_id=1), Chennai (city_id=5) — ~30% of trips
- Shard 2: Mumbai (city_id=2), Pune (city_id=6) — ~25% of trips
- Shard 3: Delhi (city_id=3), Jaipur (city_id=9) — ~20% of trips
- Shard 4: Hyderabad (city_id=4), Kolkata (city_id=7), Ahmedabad (city_id=8), Lucknow (city_id=10)

### Read Replicas and Caching

**Send to replica (safe — read-only, slightly stale data is fine):**

| Query | Why replica is OK |
|-------|------------------|
| R01, R02 | Trip history — 1 second stale is fine for a rider's history screen |
| R06, R07, R08, R11, R12 | Analytics/reporting — not real-time |
| R17, R18, R19, R20, R23 | Batch reports — run on replica to avoid primary load |
| R21 | Promo usage stats — fine to be slightly stale |
| R24, R25 | Fraud checks run hourly — replica is fine |

**Must hit primary (writes or real-time requirements):**

| Query | Why primary is required |
|-------|------------------------|
| W01, W02, W03, W04, W05 | All writes must go to primary |
| R03 (login) | Must be authoritative — stale replica risks login failure |
| R04, R05, R14, R15 | Dispatch, receipt, vehicle lookup — need current data |
| R16 | Admin panel — acceptable to use replica with short lag |
| R22 | Failed payments — financial, must be accurate |

**Redis caching candidates:**
- R03 (email login): Cache `LOWER(email) → rider_id` for 5 minutes (email rarely changes)
- R21 (promo code usage): Cache promo counts for 1 hour (marketing dashboard)
- R12 (surge by hour): Cache for 10 minutes (surge changes slowly)

### VACUUM and Maintenance for `trips`

```sql
-- Aggressive autovacuum for trips (hot table with many deletes/updates)
ALTER TABLE trips SET (
    autovacuum_vacuum_scale_factor = 0.01,  -- vacuum after 1% of rows change (default 20%)
    autovacuum_analyze_scale_factor = 0.005, -- analyze after 0.5% change
    autovacuum_vacuum_cost_delay = 2         -- faster vacuum (ms between cost-based delays)
);

-- For partitioned trips, set per-partition:
ALTER TABLE trips_2026_06 SET (autovacuum_vacuum_scale_factor = 0.01);
-- etc.
```

**Archiving plan:**
1. After 2 years, detach the partition: `ALTER TABLE trips_partitioned DETACH PARTITION trips_2025_01;`
2. The detached partition becomes a standalone table — still queryable for historical reports.
3. Dump to cold storage (S3/GCS): `pg_dump -t uber.trips_2025_01 uber_db > trips_2025_01.sql.gz`
4. Drop from primary: `DROP TABLE uber.trips_2025_01;`

**Refreshing summary tables:**
```sql
-- Materialized view for R08/R17/R23 — refresh nightly
CREATE MATERIALIZED VIEW monthly_city_stats AS
SELECT city_id, date_trunc('month', requested_at) AS month,
       count(*) AS total_trips,
       count(*) FILTER (WHERE status = 'COMPLETED') AS completed,
       count(*) FILTER (WHERE status LIKE 'CANCELLED%') AS cancelled,
       count(DISTINCT rider_id) AS active_riders
FROM trips GROUP BY 1, 2;

-- Refresh: REFRESH MATERIALIZED VIEW CONCURRENTLY monthly_city_stats;
-- CONCURRENTLY: does not lock the view during refresh — no downtime
```

---

## Conclusion

**Is the database ready for next year (20× growth)?**

**Yes, for 29 out of 30 queries.** After optimization and partitioning:
- All real-time/customer-facing queries (R01–R05, R13–R16, W01, W02) stay under 5ms.
- All analytics queries (R06–R12, R17–R25) stay under 5,000ms.
- W05 (data retention) got 1,864× faster through partial indexing — from 19 seconds to 10ms.
- W04 (bulk import) misses the target at 20× scale — fixable with `COPY` instead of `INSERT … SELECT`.

**Remaining risks:**
1. **W04 bulk imports** need to switch from `INSERT … SELECT` to `COPY` at scale.
2. **R23 (COUNT DISTINCT)** will approach 1,000ms at 20× — still within target but worth monitoring.
3. **R11 and R17** will take ~600–700ms at 20× — acceptable but partition pruning won't help these since they span all time periods.
4. **Partition key in PK** means application queries must always include `requested_at` when doing PK lookups — requires app-layer awareness.
5. **Cross-shard queries** (R11, full aggregates) need a scatter-gather layer when true sharding is implemented.

**The biggest win of the project:** R18's correlated subquery rewrite (800×) and W05's partial-index DELETE (1,864×) transformed two previously unusable queries into sub-30ms operations that will survive the next decade of growth.
