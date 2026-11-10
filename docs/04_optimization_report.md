# Phase 4 – Optimization Report

**Team:** T0001 | **Database:** uber_db (PostgreSQL 16.15) | **Machine:** MacBook Pro M4  
**Indexes file:** `sql/05_indexes.sql` | **Optimized queries:** `sql/06_optimized_queries.sql`  
**Benchmark command:** `./benchmarks/run_benchmark.sh uber_db optimized 3 sql/06_optimized_queries.sql`

---

## Optimization Table (all 30 queries)

| Query | Before (ms) | Plan problem | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------------:|------------------------------|----------------------|----------:|------------:|:------------:|
| R01 | 15.471 | Seq Scan 300k trips | Composite index `(rider_id, requested_at DESC)` | 0.372 | **97.6% (41×)** | ✅ |
| R02 | 14.591 | Seq Scan + `DATE()` wrapper blocks index | Sargable range + composite index `(driver_id, status, requested_at)` | 0.244 | **98.3% (60×)** | ✅ |
| R03 | 7.687 | Seq Scan — `LOWER(email)` can't use UNIQUE index | Expression index `ON riders (LOWER(email))` | 0.260 | **96.6% (30×)** | ✅ |
| R04 | 10.235 | Seq Scan 300k trips | Index on `requested_at` (range seek) | 0.965 | **90.6% (11×)** | ✅ |
| R05 | 16.793 | Seq Scan — 300 active rows out of 300k | Partial index `WHERE status IN (...)` — 300-row index | 0.060 | **99.6% (280×)** | ✅ |
| R06 | 12.505 | Seq Scan trips | Partial index on COMPLETED trips + `requested_at` | 8.261 | **33.9% (1.5×)** | ✅ |
| R07 | 13.881 | Seq Scan all three tables | COMPLETED partial index; city join (10 rows) stays seq scan | 11.564 | **16.7% (1.2×)** | ✅ |
| R08 | 27.650 | Seq Scan payments; `EXTRACT(YEAR)` blocks index | Sargable date range + `(payment_status, paid_at)` index | 34.526 | −24.9% (slower) | ✅ |
| R09 | 20.277 | Seq Scan; `NOT IN` (wrong-result bug) | `NOT EXISTS` rewrite + `idx_trips_requested_at` | 7.088 | **65.0% (2.9×)** | ✅ |
| R10 | 14.471 | `NOT IN` returns wrong answer (0 rows!) | `NOT EXISTS` rewrite — **bug fixed** | 0.977 | **93.2% (15×)** | ✅ (fixed) |
| R11 | 30.263 | Seq Scan 307k ratings | Index `(rated_by, trip_id)` on ratings | 31.146 | −2.9% (no change) | ✅ |
| R12 | 54.361 | Seq Scan all trips for Delhi | Bitmap Index Scan via `idx_trips_city_status_requested` | 21.049 | **61.3% (2.6×)** | ✅ |
| R13 | 6.339 | Seq Scan; leading wildcard ILIKE | GIN trigram index (`pg_trgm`) | 0.902 | **85.8% (7×)** | ✅ |
| R14 | 0.033 | Already Index Scan (UNIQUE existed) | No change needed | 0.041 | (baseline already fast) | ✅ |
| R15 | 6.891 | Seq Scan payments for trip_id | Index on `payments(trip_id)` | 0.230 | **96.7% (30×)** | ✅ |
| R16 | 25.530 | OFFSET 200000 — reads/discards 200k rows | Keyset pagination (`WHERE trip_id <= anchor`) | 0.063 | **99.8% (405×)** | ✅ |
| R17 | 23.774 | Full scan to compute cancel rates | Must read all trips to count — acceptable seq scan | 33.585 | −41.3% (slower) | ✅ |
| R18 | 20,451.223 | Correlated subquery: 3,000 × 300k = 900M rows | Rewrite to `LEFT JOIN … GROUP BY` | 25.494 | **99.9% (802×)** | ✅ |
| R19 | 12.776 | Seq Scan drivers + trips | `idx_trips_completed_requested` for date filter | 4.319 | **66.2% (3×)** | ✅ |
| R20 | 14.127 | Seq Scan; `::date` cast blocks index | Sargable TIMESTAMPTZ range + COMPLETED partial index | 3.785 | **73.2% (3.7×)** | ✅ |
| R21 | 20.288 | Seq Scan trips for promo join | Index on `trips(promo_code)` | 9.569 | **52.8% (2.1×)** | ✅ |
| R22 | 6.860 | Seq Scan payments | `(payment_status, paid_at)` index + `payments(trip_id)` | 0.607 | **91.1% (11×)** | ✅ |
| R23 | 53.751 | Seq Scan all trips for DISTINCT count | Index on `requested_at` helps range filter | 51.072 | **5.0% (1.05×)** | ✅ |
| R24 | 12.650 | Seq Scan; OR condition on distance/duration | Still seq scan — partial index not chosen by planner | 13.396 | −5.9% (no change) | ✅ |
| R25 | 17.923 | Seq Scan; expression on fare/distance | Still seq scan — planner prefers seq for this selectivity | 18.460 | −3.0% (no change) | ✅ |
| W01 | 0.645 | — (INSERT, already fast) | No change | 1.031 | −59.8% (overhead) | ✅ |
| W02 | 30.531 | Seq Scan for min(trip_id) ONGOING | Partial index `WHERE status='ONGOING'` | 1.243 | **95.9% (24×)** | ✅ |
| W03 | 4.850 | Seq Scan 3k drivers | Small table — acceptable | 6.726 | −38.7% (overhead) | ✅ |
| W04 | 29.864 | Bulk insert via generate_series | No change possible — overhead from new indexes | 98.793 | −231% (overhead) | ✅ |
| W05 | 19,091.247 | Full scan DELETE 300k trips | Partial index `WHERE status LIKE 'CANCELLED%'` | 10.245 | **99.9% (1,864×)** | ✅ |
| **Total** | **~40,014 ms** | | | **~397 ms** | **99.0%** | |

---

## Before/After EXPLAIN Plans — Top 5 Improvements

### R18: Correlated Subquery → LEFT JOIN (20,451ms → 25ms, 802× faster)

**Before:** For each Pune rider, runs a separate `SELECT max(requested_at) FROM trips WHERE rider_id = ?` — a full 300k-row scan 3,000 times.

**After:** Single pass — `LEFT JOIN trips ON t.rider_id = r.rider_id WHERE r.home_city_id = 6 GROUP BY rider`.  
Plan changes from: `Seq Scan on riders → Nested Loop → Seq Scan on trips (300,000 loops)`  
To: `Bitmap Index Scan on idx_riders_home_city → Hash Join → Seq Scan on trips (1 pass)`

---

### W05: Full Scan DELETE → Partial Index (19,091ms → 10ms, 1,864× faster)

**Before:** `DELETE WHERE status LIKE 'CANCELLED%' AND requested_at < '2025-02-01'` scanned all 300,000 rows.

**After:** `idx_trips_cancelled_requested` is a partial index containing only cancelled trips. The planner does an Index Scan on ~1,200 rows matching January 2025 cancelled trips and deletes only those.

---

### R16: OFFSET Pagination → Keyset (25ms → 0.063ms, 405× faster)

**Before:** `ORDER BY trip_id DESC OFFSET 200000 LIMIT 25` — PostgreSQL must traverse 200,025 index entries to return 25 rows.

**After:** `WHERE trip_id <= 100001 ORDER BY trip_id DESC LIMIT 25` — single index seek, returns 25 rows immediately. The client remembers the last `trip_id` seen.

---

### R05: Full Scan → Partial Index (16.8ms → 0.06ms, 280× faster)

**Before:** Scanned all 300,000 trips to find 300 active ones.

**After:** `idx_trips_active_status` is a 352 kB partial index containing only 300 rows. The planner does an Index Scan returning 50 rows in 0.06ms — essentially instantaneous.

---

### R01: Rider Trip History (15.5ms → 0.37ms, 41× faster)

**Before:** Full 300k-row scan to find 20 trips for one rider.

**After:** `idx_trips_rider_requested (rider_id, requested_at DESC)` — direct seek to the rider's rows, already sorted in reverse order. No sort step, no extra scan.

---

## The Wrong-Result Query: R10

**What was wrong:** R10 uses `NOT IN (SELECT driver_id FROM trips WHERE ...)`. Some trips have `driver_id = NULL` (cancelled trips before a driver was assigned). When a subquery returns any NULL, `NOT IN` evaluates to `UNKNOWN` for every row in the outer query — **so the entire outer query returns zero rows.**

```sql
-- This returns 0 rows — wrong!
WHERE d.driver_id NOT IN (SELECT t.driver_id FROM trips t WHERE t.requested_at >= '2026-06-25')
--                        ^^^^^ subquery includes NULLs → entire NOT IN = UNKNOWN
```

**The fix:** Use `NOT EXISTS` instead. `NOT EXISTS` checks for the absence of matching rows and handles NULLs correctly.

```sql
-- This returns 978 rows — correct
AND NOT EXISTS (SELECT 1 FROM trips t WHERE t.driver_id = d.driver_id AND t.requested_at >= '2026-06-25')
```

**Verification:** `NOT IN` → 0 rows. `NOT EXISTS` → 978 rows. The correct answer is 978 (confirmed by checking the underlying data).

**Note:** R09 has the same `NOT IN` pattern. In the seed data, all riders have non-NULL `rider_id` so R09 happens to return correct results (893 rows both ways), but we rewrote it to `NOT EXISTS` anyway — it's the correct pattern and it's also faster.

---

## Write Overhead from Indexes

| Write Query | Before (ms) | After (ms) | Slower by | Why | Acceptable? |
|-------------|------------:|----------:|----------:|-----|-------------|
| W01 | 0.645 | 1.031 | +0.4ms | More indexes to maintain on INSERT | Yes — still <2ms |
| W03 | 4.850 | 6.726 | +1.9ms | idx_drivers_active partial index update | Yes — still <10ms |
| W04 | 29.864 | 98.793 | +69ms | Bulk insert of 5,000 rows must update 12 trip indexes | Acceptable — batch op |
| W05 | 19,091.247 | 10.245 | **−19,081ms** | Partial index makes DELETE 1,864× faster | Huge win |

W02's write overhead is negligible (still <2ms). The only notable overhead is W04 (bulk import): 12 indexes on trips × 5,000 new rows = expected overhead. In production this would use `COPY` with index rebuild or deferred constraint checks.

---

## Index Storage Summary

| Index | Table | Index size | Table size | Ratio |
|-------|-------|----------:|----------:|------:|
| idx_trips_driver_status_requested | trips | 13 MB | 47 MB | 28% |
| idx_trips_city_status_requested | trips | 12 MB | 47 MB | 26% |
| idx_trips_rider_requested | trips | 9.3 MB | 47 MB | 20% |
| idx_trips_completed_requested | trips | 5.4 MB | 47 MB | 11% |
| idx_payments_status_paid_at | payments | 7.6 MB | 16 MB | 48% |
| idx_payments_trip_id | payments | 5.4 MB | 16 MB | 34% |
| idx_ratings_rated_by_trip | ratings | 9.5 MB | 16 MB | 59% |
| idx_trips_active_status | trips | 352 kB | 47 MB | 0.7% |
| idx_trips_cancelled_requested | trips | 1.2 MB | 47 MB | 2.5% |
| idx_riders_name_trgm | riders | 720 kB | 3.3 MB | 22% |
| **Total new indexes** | | **~97 MB** | **204 MB DB** | ~48% overhead |

The partial indexes (active_status, ongoing, cancelled) are tiny because they only index a subset of rows — this is the power of partial indexing.

---

## Queries That Could Not Be Sped Up

| Query | Why it couldn't be faster |
|-------|--------------------------|
| R08 | Payments index helps but 233k SUCCESS rows in 2026 must all be read for the GROUP BY. It's a full analytics scan by nature. |
| R11 | Must read all 307k ratings to compute average stars per driver. Minimum work for this aggregate. |
| R17 | Cancellation rate needs all trips for all cities — no way to avoid reading everything. |
| R23 | COUNT(DISTINCT rider_id) across all 2026 trips requires touching ~270k rows. DISTINCT is inherently expensive. |
| R24, R25 | OR condition `(distance_km > 43 OR duration_min > 150)` — planner chose seq scan because the selectivity is similar to scanning. The expression index wasn't chosen because the OR makes bitmap merging less efficient than a seq scan at this data size. |

These queries are "honest sequential scans" — they genuinely need most of the table. On partitioned data (Phase 5), they'll only scan the relevant time partitions.
