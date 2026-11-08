# Phase 1 – Problem Understanding

**Team:** T0001 | **Lead:** Garvit Gandhi | **Date:** November 2026

---

## What is the system?

Uber India runs a ride-hailing service across 10 cities. Every day: riders request rides, drivers accept, trips happen, payments are made, and both sides rate each other. The database that holds all of this was built quickly and has no documented schema — only raw data exports survive. The product teams are complaining about slow queries, wrong results, and timeouts.

Our job is to:
1. Rebuild a clean, correct schema from the data exports.
2. Measure how the 30 key queries perform right now (baseline).
3. Make them fast without changing their results (optimization).
4. Prove the database can handle 20× more data next year (scalability).

---

## Problem-by-Problem Analysis

### P1 — "Your Trips" screen is slow for frequent riders
- **Queries:** R01, R15
- **Stakeholder:** Rider
- **Business need:** When a rider opens their trip history, they expect it to load instantly. Frequent riders have hundreds of trips — if the database scans the whole table every time, the app lags.
- **Type:** Customer-facing / real-time
- **Performance target:** Under 5 ms on large data
- **Root cause (likely):** No index on `(rider_id, requested_at)`, so PostgreSQL does a full sequential scan of 300,000 trips to find 20.

---

### P2 — Driver earnings page is slow
- **Queries:** R02, R07, R19
- **Stakeholder:** Driver
- **Business need:** Drivers check their earnings many times a day. The page should return instantly. Slow earnings pages make drivers distrust the app.
- **Type:** Customer-facing / real-time
- **Performance target:** Under 5 ms on large data
- **Root cause (likely):** No composite index on `(driver_id, status, requested_at)`, forcing a full scan of trips for every driver lookup.

---

### P3 — Login by email fails for capital letters, and the fix made it slow
- **Queries:** R03
- **Stakeholder:** Rider (Identity team)
- **Business need:** Users type their email in any case (UPPERCASE, lowercase, Mixed). Login must work regardless, and it must be fast.
- **Type:** Customer-facing / real-time
- **Performance target:** Under 5 ms on large data
- **Root cause (likely):** A regular index on `email` does not help when the query uses `LOWER(email) = ...`. Need a function-based index on `LOWER(email)`.

---

### P4 — Live dispatch screen refresh takes longer than 3 seconds
- **Queries:** R04, R05, W01, W02
- **Stakeholder:** City operations team
- **Business need:** The dispatch screen shows active trips in real time — it refreshes every 3 seconds. If each refresh takes more than 3 seconds, dispatchers see stale data and cannot assign drivers properly.
- **Type:** Customer-facing / real-time
- **Performance target:** Under 5 ms on large data
- **Root cause (likely):** `WHERE status IN ('REQUESTED','ACCEPTED','ONGOING')` does a full table scan because the common status is COMPLETED (81%). A partial index on these rare statuses would be tiny and fast.

---

### P5 — Monthly finance reports time out
- **Queries:** R08, R20, R22
- **Stakeholder:** Finance team
- **Business need:** Month-end reports aggregate revenue by payment method, compute running totals, and find failed payments. These can't time out — finance depends on them for reconciliation.
- **Type:** Reporting / analytics
- **Performance target:** Under 5,000 ms on large data
- **Root cause (likely):** Full sequential scans on the payments table (245,839 rows) with no index on `(payment_status, paid_at)` or `(paid_at)`.

---

### P6 — Win-back campaign returns wrong or empty results
- **Queries:** R09, R10, R18
- **Stakeholder:** Marketing team, Driver ops
- **Business need:** Marketing needs a list of riders who haven't taken a trip recently. Driver ops needs drivers who've gone inactive. Wrong lists mean money wasted on the wrong people or missing genuinely inactive users.
- **Type:** Reporting / analytics
- **Performance target:** Under 5,000 ms on large data
- **Root cause (likely):** R09 uses `NOT IN (subquery)` — if the subquery returns even one NULL `rider_id`, the whole outer query returns zero rows (SQL's NULL-in-NOT-IN trap). This is the **wrong-result query** mentioned in Phase 4.

---

### P7 — Fraud checks scan the whole table every time
- **Queries:** R24, R25
- **Stakeholder:** Trust & Safety team
- **Business need:** Fraud analysts flag unusually long or overpriced trips. These checks run frequently and must be fast.
- **Type:** Reporting / analytics
- **Performance target:** Under 5,000 ms on large data
- **Root cause (likely):** No index on `distance_km` or `fare_amount` for the fraud thresholds. Full sequential scan every time.

---

### P8 — Admin panel gets slower the further you page
- **Queries:** R16
- **Stakeholder:** Admin team
- **Business need:** Admins browse all trips in a paginated table. Page 8,001 (OFFSET 200,000) requires the database to scan and skip 200,000 rows before returning 25 — this gets worse with every page.
- **Type:** Customer-facing / real-time
- **Performance target:** Under 5 ms on large data
- **Root cause (likely):** `OFFSET`-based pagination is fundamentally slow. The fix is keyset pagination: `WHERE trip_id < last_seen_id ORDER BY trip_id DESC LIMIT 25`.

---

### P9 — Analytics dashboards are slow and must survive 10–20× growth
- **Queries:** R06, R11, R12, R17, R21, R23
- **Stakeholder:** Analytics team, Leadership
- **Business need:** Surge pricing, cancellation rates, rider growth, and driver quality dashboards are used daily for business decisions. They're already slow on current data — at 20× the volume they'll be unusable.
- **Type:** Reporting / analytics
- **Performance target:** Under 5,000 ms on large data
- **Root cause (likely):** Many of these aggregate the entire trips table. At scale, partitioning by date (`requested_at`) will allow partition pruning — queries that filter by month only scan relevant partitions instead of the whole table.

---

## Classification Summary

| # | Problem | Type | Stakeholder |
|---|---------|------|-------------|
| P1 | Rider trip history | Customer-facing / real-time | Rider |
| P2 | Driver earnings | Customer-facing / real-time | Driver |
| P3 | Email login | Customer-facing / real-time | Rider (Identity) |
| P4 | Live dispatch | Customer-facing / real-time | City Operations |
| P5 | Finance reports | Reporting / analytics | Finance |
| P6 | Win-back campaigns | Reporting / analytics | Marketing, Driver Ops |
| P7 | Fraud checks | Reporting / analytics | Trust & Safety |
| P8 | Admin pagination | Customer-facing / real-time | Admin |
| P9 | Analytics dashboards | Reporting / analytics | Analytics, Leadership |

---

## Assumptions

1. The 10 cities listed are the only valid cities; `city_id` is always 1–10.
2. A trip can only belong to one city, one rider, and one driver.
3. A driver can have multiple vehicles registered, but only one is used per trip (`vehicle_id` in trips).
4. `ratings.csv` uses a composite primary key `(trip_id, rated_by)` — each trip gets at most one rating from the rider and one from the driver.
5. Cancelled and in-progress trips (REQUESTED, ACCEPTED, ONGOING, CANCELLED_*) have NULL for `driver_id`, `vehicle_id`, `pickup_at`, `dropoff_at`, `distance_km`, `duration_min`, and `fare_amount` — this is valid data, not corrupt data.
6. Emails in `riders.csv` are stored with mixed case (e.g. `Vivaan.Sharma1@Mail.com`) — queries must normalize with `LOWER()`.
7. The `driver_rating` in `drivers` and `rider_rating` in `riders` are denormalized averages kept for fast lookups; the source of truth is `ratings`.
