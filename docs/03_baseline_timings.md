# Phase 3 – Baseline Query Timings

**Team:** T0001 | **Database:** uber_db (PostgreSQL 16.15) | **Machine:** MacBook Pro M4  
**Method:** `EXPLAIN (ANALYZE, BUFFERS)` · 3 runs each · average reported · write queries inside `BEGIN … ROLLBACK`  
**Data:** 300,000 trips · 30,000 riders · 3,000 drivers · 3,300 vehicles · 245,839 payments · 307,214 ratings  
**Indexes present:** Only those automatically created by PRIMARY KEY and UNIQUE constraints. No extra indexes.

Raw plan files: `benchmarks/results/baseline/R01.txt` … `W05.txt`  
Summary CSV: `benchmarks/results/baseline/summary.csv`

---

## Timing Table (all 30 queries)

| Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|-------|------|----------:|----------:|----------:|------------:|
| R01: Rider's last 20 trips | READ | 25.253 | 11.914 | 9.245 | **15.471** |
| R02: Driver's March 2026 earnings | READ | 13.078 | 14.497 | 16.197 | **14.591** |
| R03: Login by email (case-insensitive) | READ | 11.167 | 6.235 | 5.659 | **7.687** |
| R04: Bengaluru trips on 10 May 2026 | READ | 9.497 | 10.091 | 11.118 | **10.235** |
| R05: Oldest in-progress trips (dispatch) | READ | 15.309 | 17.104 | 17.965 | **16.793** |
| R06: Completed trips per city, June 2026 | READ | 12.200 | 12.656 | 12.658 | **12.505** |
| R07: Top 10 earning drivers in Mumbai, Q1 2026 | READ | 13.218 | 13.645 | 14.780 | **13.881** |
| R08: Revenue per payment method per month, 2026 | READ | 26.417 | 27.582 | 28.950 | **27.650** |
| R09: Bengaluru riders inactive since April 2026 | READ | 20.210 | 20.261 | 20.360 | **20.277** |
| R10: Active drivers with no trip since 25 June 2026 | READ | 13.911 | 14.745 | 14.756 | **14.471** |
| R11: 20 lowest-rated drivers | READ | 29.979 | 30.176 | 30.633 | **30.263** |
| R12: Average surge by hour in Delhi | READ | 34.693 | 35.499 | 92.892 | **54.361** |
| R13: Search riders by surname | READ | 6.291 | 6.318 | 6.408 | **6.339** |
| R14: Vehicle + driver by registration number | READ | 0.026 | 0.035 | 0.039 | **0.033** |
| R15: Trip receipt | READ | 6.586 | 7.038 | 7.048 | **6.891** |
| R16: Admin panel page 8,001 | READ | 22.608 | 24.219 | 29.764 | **25.530** |
| R17: Cancellation rate per city | READ | 23.625 | 23.708 | 23.990 | **23.774** |
| R18: Last trip date of every Pune rider | READ | 19,811.564 | 20,463.742 | 21,078.364 | **20,451.223** |
| R19: Top 3 drivers per city, May 2026 | READ | 12.091 | 12.837 | 13.399 | **12.776** |
| R20: Daily revenue + running total, May 2026 | READ | 13.570 | 13.853 | 14.958 | **14.127** |
| R21: Promo code usage | READ | 19.959 | 20.098 | 20.806 | **20.288** |
| R22: Failed payments, last 7 days | READ | 6.271 | 6.517 | 7.793 | **6.860** |
| R23: Distinct active riders per city per month | READ | 53.265 | 53.287 | 54.700 | **53.751** |
| R24: Unusually long trips | READ | 12.541 | 12.663 | 12.747 | **12.650** |
| R25: Trips charging more than ₹100/km | READ | 17.631 | 18.054 | 18.085 | **17.923** |
| W01: Request a new trip | WRITE | 0.531 | 0.551 | 0.852 | **0.645** |
| W02: Complete the oldest ongoing trip | WRITE | 28.965 | 29.534 | 33.093 | **30.531** |
| W03: Suspend low-rated drivers | WRITE | 4.665 | 4.772 | 5.112 | **4.850** |
| W04: Bulk import of 5,000 trips | WRITE | 27.907 | 28.219 | 33.465 | **29.864** |
| W05: Purge cancelled trips from Jan 2025 | WRITE | 18,608.304 | 19,153.977 | 19,511.460 | **19,091.247** |
| **Total (sum of all 30)** | | | | | **~40,014 ms** |

---

## Scan Type and Why Each Query is Slow or Fast

| Query | Scan Type | Why slow / fast |
|-------|-----------|-----------------|
| R01 | Seq Scan on trips | No index on `(rider_id, requested_at)`. Scans all 300,000 trips to find 20 for one rider. |
| R02 | Seq Scan on trips | No index on `(driver_id, status, requested_at)`. Full scan to filter one driver's March trips. |
| R03 | Seq Scan on riders | `LOWER(email) = ?` cannot use the UNIQUE index on `email` (different expression). Full scan of 30,000 riders. |
| R04 | Seq Scan on trips, cities | No index on `(city_id, requested_at)`. Full scan of trips then filter by date range. |
| R05 | Seq Scan on trips | No partial index on active statuses (REQUESTED/ACCEPTED/ONGOING = only 300 rows out of 300,000). Full scan. |
| R06 | Seq Scan on trips, cities | Same as R04 — no index on `(city_id, status, requested_at)`. |
| R07 | Seq Scan on trips, drivers, cities | No composite index. Three-table join, all sequential. |
| R08 | Seq Scan on payments | No index on `(payment_status, paid_at)`. Scans all 245,839 payments. |
| R09 | Seq Scan on riders, trips | `NOT IN (subquery)` with no index on `requested_at`. Subquery scans all trips; outer scans all riders. |
| R10 | Seq Scan on drivers, trips | Same pattern as R09 with `NOT IN`. |
| R11 | Seq Scan on trips, ratings | No index on `(rated_by, trip_id)` in ratings. Scans 307,214 ratings and 300,000 trips. |
| R12 | Seq Scan on trips, cities | No index on `(city_id, requested_at)`. Scans all trips to find Delhi ones and extract hour. |
| R13 | Seq Scan on riders | `ILIKE '%sharma%'` cannot use a B-tree index (leading wildcard). Scans all 30,000 riders. |
| R14 | **Index Scan** (vehicles UNIQUE, drivers PK) | UNIQUE index on `registration_no` already exists. Tiny: 0.033 ms. This is what fast looks like. |
| R15 | Index Scan (trips/riders/drivers/vehicles PK), Seq Scan payments | PK lookups are fast. Payments has no index on `trip_id` — sequential scan but only 245k rows so still fast. |
| R16 | Index Scan (trips PK) | PK index used to ORDER BY trip_id DESC, but `OFFSET 200000` forces reading and discarding 200,000 rows. Slow at high page numbers. |
| R17 | Seq Scan on trips, cities | No index; full scan to compute cancellation counts for all cities. |
| R18 | **Seq Scan on trips (correlated subquery)** | **WORST QUERY: 20 seconds.** For every Pune rider (~3,000), the correlated subquery `SELECT max(requested_at) FROM trips WHERE rider_id = ?` runs a full 300,000-row scan. That's 3,000 × 300,000 = 900 million row checks. |
| R19 | Seq Scan on trips, drivers | No index on `(driver_id, status, requested_at)`. Full scans for window function. |
| R20 | Seq Scan on trips | No index on `(status, requested_at)`. Scans trips to group May 2026 revenue by day. |
| R21 | Seq Scan on trips, promo_codes | No index on `trips.promo_code`. Full scan to count promo usage. |
| R22 | Seq Scan on payments, Index Scan on trips/riders | Payments scanned fully despite date filter because no index on `(payment_status, paid_at)`. |
| R23 | Seq Scan on trips | No index on `(city_id, requested_at)`. Scans all trips for 2026 distinct-rider count. |
| R24 | Seq Scan on trips | No index on `distance_km` or `duration_min`. Full scan to find outlier trips. |
| R25 | Seq Scan on trips | No index for `fare_amount / distance_km > 100` expression. Full scan. |
| W01 | (no scan — INSERT) | Direct INSERT by PK. Fast: 0.645 ms. |
| W02 | Index Scan (trips PK) | `WHERE trip_id = (SELECT min(...))` — uses PK, fast lookup. But the subquery `SELECT min(trip_id) WHERE status='ONGOING'` does a seq scan. |
| W03 | Seq Scan on drivers | Full scan of 3,000 drivers to find active ones rated below 3.5. Small table, fast enough. |
| W04 | (no scan — INSERT … SELECT generate_series) | Bulk insert of 5,000 rows via function, no table scan. |
| W05 | **Seq Scan on trips** | **SECOND SLOWEST: 19 seconds.** `DELETE … WHERE status LIKE 'CANCELLED%' AND requested_at < '2025-02-01'` scans all 300,000 trips. No index on `(status, requested_at)`. On large data this will be catastrophic. |

---

## Key Observations

1. **R18 (20.5 s) is the catastrophic query.** Correlated subquery runs once per rider — O(riders × trips). Will scale to 3 minutes on 20× data.

2. **W05 (19 s) is the second worst.** Full table scan DELETE. On 6M trips it becomes a 6-minute operation.

3. **Almost everything does a Seq Scan on trips.** The 300,000-row trips table is scanned fresh for every single query because there are zero non-PK indexes. This is the #1 fix for Phase 4.

4. **R14 is already fast (0.033 ms)** because the UNIQUE constraint on `registration_no` auto-created an index. This shows exactly what well-placed indexes can do.

5. **R18 also contains a potential wrong-result bug** — the `NOT IN` pattern in R09 returns zero rows if any `rider_id` in the subquery is NULL (SQL NULL semantics). This is the wrong-result query we will fix in Phase 4.
