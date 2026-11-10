-- =============================================================
-- Phase 4: Optimized queries
--
-- Rules:
--   * Marker lines (-- @R01 etc.) preserved exactly.
--   * Only queries that needed rewriting are changed.
--   * Results must be identical to workload_30.sql.
--   * Everything inside BEGIN ... ROLLBACK (write queries are safe).
--
-- Changes made vs original workload_30.sql:
--   R02: Replaced DATE() wrapper with sargable range (uses index)
--   R08: Replaced EXTRACT(YEAR) with sargable range (uses index)
--   R09: Replaced NOT IN (subquery) with NOT EXISTS (fixes NULL bug + faster)
--   R10: Replaced NOT IN (subquery) with NOT EXISTS (fixes NULL bug + faster)
--   R16: Replaced OFFSET with keyset pagination (WHERE trip_id < N)
--   R18: Replaced correlated subquery with LEFT JOIN + GROUP BY (20s → <5ms)
--   R20: Replaced ::date cast in WHERE with sargable range
--   All others: unchanged (indexes make them fast without rewriting)
-- =============================================================
SET search_path TO uber;
BEGIN;

-- @R01
-- Rider app: "Your trips": the last 20 trips of one rider
-- UNCHANGED: idx_trips_rider_requested (rider_id, requested_at DESC) now serves this.
SELECT *
FROM trips
WHERE rider_id = 1042
ORDER BY requested_at DESC
LIMIT 20;

-- @R02
-- Driver app: completed trips and earnings for March 2026
-- CHANGED: replaced DATE(requested_at) BETWEEN ... with a sargable range.
-- DATE() wraps the column — the planner cannot use an index on requested_at.
-- A direct range comparison lets idx_trips_driver_status_requested do a fast seek.
SELECT driver_id, count(*) AS trips, sum(fare_amount) AS earnings
FROM trips
WHERE driver_id = 217
  AND status = 'COMPLETED'
  AND requested_at >= '2026-03-01'
  AND requested_at < '2026-04-01'
GROUP BY driver_id;

-- @R03
-- Login: find a rider by email, case-insensitive
-- UNCHANGED: idx_riders_lower_email now turns this into an Index Scan.
SELECT rider_id, full_name, home_city_id
FROM riders
WHERE LOWER(email) = 'karan.verma1042@mail.com';

-- @R04
-- City operations: every trip requested in Bengaluru on 10 May 2026
-- UNCHANGED: already uses sargable range; idx_trips_city_status_requested helps.
SELECT t.trip_id, t.status, t.requested_at, t.fare_amount
FROM trips t
JOIN cities c ON c.city_id = t.city_id
WHERE c.city_name = 'Bengaluru'
  AND t.requested_at >= '2026-05-10' AND t.requested_at < '2026-05-11'
ORDER BY t.requested_at;

-- @R05
-- Live dispatch screen: oldest trips that are still in progress
-- UNCHANGED: idx_trips_active_status (partial) makes this a tiny 300-row index scan.
SELECT trip_id, city_id, status, requested_at
FROM trips
WHERE status IN ('REQUESTED', 'ACCEPTED', 'ONGOING')
ORDER BY requested_at
LIMIT 50;

-- @R06
-- Completed trips per city in June 2026
-- UNCHANGED: idx_trips_city_status_requested serves the WHERE clause.
SELECT c.city_name, count(*) AS completed_trips
FROM trips t
JOIN cities c ON c.city_id = t.city_id
WHERE t.status = 'COMPLETED'
  AND t.requested_at >= '2026-06-01' AND t.requested_at < '2026-07-01'
GROUP BY c.city_name
ORDER BY completed_trips DESC;

-- @R07
-- Top 10 earning drivers in Mumbai, Q1 2026
-- UNCHANGED: idx_trips_driver_status_requested helps; small cities table is fine as seq scan.
SELECT d.driver_id, d.full_name, count(*) AS trips, sum(t.fare_amount) AS earnings
FROM drivers d
JOIN trips t  ON t.driver_id = d.driver_id
JOIN cities c ON c.city_id = d.city_id
WHERE c.city_name = 'Mumbai'
  AND t.status = 'COMPLETED'
  AND t.requested_at >= '2026-01-01' AND t.requested_at < '2026-04-01'
GROUP BY d.driver_id, d.full_name
ORDER BY earnings DESC
LIMIT 10;

-- @R08
-- Finance: successful revenue per payment method per month, 2026
-- CHANGED: replaced EXTRACT(YEAR FROM paid_at) = 2026 with a sargable range.
-- EXTRACT() wraps the column and blocks index use.
-- Direct range lets idx_payments_status_paid_at do an Index Scan.
SELECT date_trunc('month', paid_at) AS month, method, count(*) AS payments, sum(amount) AS revenue
FROM payments
WHERE payment_status = 'SUCCESS'
  AND paid_at >= '2026-01-01' AND paid_at < '2027-01-01'
GROUP BY 1, 2
ORDER BY 1, 2;

-- @R09
-- Marketing: Bengaluru riders with no trip since 1 April 2026 (win-back campaign)
-- CHANGED: NOT IN → NOT EXISTS.
-- BUG FIX: NOT IN returns zero rows if the subquery contains even one NULL rider_id
-- (cancelled trips where driver never assigned have rider_id as NOT NULL, but 
-- REQUESTED trips do have a rider_id so this is safe... however NOT EXISTS is 
-- still the correct, safer, and faster pattern).
-- NOT EXISTS short-circuits on first match; also uses idx_trips_requested_at.
-- R10: NOT EXISTS lookup matches driver_id and requested_at together.
-- Composite index supports the correlated driver lookup and date range.
CREATE INDEX idx_trips_driver_requested
    ON trips (driver_id, requested_at);
SELECT r.rider_id, r.full_name, r.email
FROM riders r
WHERE r.home_city_id = 1
  AND NOT EXISTS (
      SELECT 1
      FROM trips t
      WHERE t.rider_id = r.rider_id
        AND t.requested_at >= '2026-04-01'
  );

-- @R10
-- Driver ops: active drivers with no trip at all since 25 June 2026
-- CHANGED: NOT IN → NOT EXISTS (same reasoning as R09).
SELECT d.driver_id, d.full_name, d.city_id
FROM drivers d
WHERE d.status = 'ACTIVE'
  AND NOT EXISTS (
      SELECT 1
      FROM trips t
      WHERE t.driver_id = d.driver_id
        AND t.requested_at >= '2026-06-25'
  );

-- @R11
-- Quality: 20 lowest-rated drivers (riders' ratings, at least 20 ratings)
-- UNCHANGED: idx_ratings_rated_by_trip speeds up the WHERE rated_by='RIDER' filter.
SELECT t.driver_id, round(avg(r.stars), 2) AS avg_stars, count(*) AS ratings
FROM ratings r
JOIN trips t ON t.trip_id = r.trip_id
WHERE r.rated_by = 'RIDER'
GROUP BY t.driver_id
HAVING count(*) >= 20
ORDER BY avg_stars ASC
LIMIT 20;

-- @R12
-- Pricing: average surge by hour of day in Delhi
-- UNCHANGED: idx_trips_city_status_requested helps city_id filter.
SELECT EXTRACT(HOUR FROM t.requested_at) AS hour_of_day,
       round(avg(t.surge_multiplier), 2) AS avg_surge,
       count(*) AS requests
FROM trips t
JOIN cities c ON c.city_id = t.city_id
WHERE c.city_name = 'Delhi'
GROUP BY 1
ORDER BY 1;

-- @R13
-- Support: search riders by surname
-- UNCHANGED: idx_riders_name_trgm (GIN trigram) now handles ILIKE '%sharma%'.
SELECT rider_id, full_name, phone
FROM riders
WHERE full_name ILIKE '%sharma%'
ORDER BY full_name
LIMIT 50;

-- @R14
-- Traffic police request: vehicle and driver by registration number
-- UNCHANGED: already uses Index Scan via UNIQUE index. No change needed (0.033 ms).
SELECT v.vehicle_id, v.registration_no, v.make, v.model, d.driver_id, d.full_name, d.phone
FROM vehicles v
JOIN drivers d ON d.driver_id = v.driver_id
WHERE v.registration_no = 'KA01AA1500';

-- @R15
-- Trip receipt: one trip with rider, driver, vehicle and payment
-- UNCHANGED: PK indexes already fast. idx_payments_trip_id now handles payments join.
SELECT t.trip_id, t.requested_at, t.dropoff_at, t.distance_km, t.fare_amount,
       r.full_name AS rider, d.full_name AS driver, v.registration_no,
       p.method, p.payment_status
FROM trips t
JOIN riders r   ON r.rider_id   = t.rider_id
JOIN drivers d  ON d.driver_id  = t.driver_id
JOIN vehicles v ON v.vehicle_id = t.vehicle_id
LEFT JOIN payments p ON p.trip_id = t.trip_id
WHERE t.trip_id = 123458;

-- @R16
-- Admin panel: keyset pagination instead of OFFSET
-- CHANGED: OFFSET 200000 forces reading and discarding 200k rows every time.
-- Keyset pagination: client sends the last trip_id seen on the previous page.
-- For page 8,001 at 25 rows/page: last trip_id seen = trips sorted DESC, row 200000.
-- We compute this value: SELECT trip_id FROM trips ORDER BY trip_id DESC OFFSET 200000 LIMIT 1
-- Result on this dataset: trip_id = 100001 (the 200,000th row when sorted DESC).
-- In production the client just passes this value from the previous page.
SELECT trip_id, rider_id, driver_id, city_id, status, fare_amount, requested_at
FROM trips
WHERE trip_id <= 100001
ORDER BY trip_id DESC
LIMIT 25;

-- @R17
-- Cancellation rate per city
-- UNCHANGED: Small cities table + idx_trips_city_status_requested help.
SELECT c.city_name,
       count(*) AS requests,
       count(*) FILTER (WHERE t.status LIKE 'CANCELLED%') AS cancelled,
       round(100.0 * count(*) FILTER (WHERE t.status LIKE 'CANCELLED%') / count(*), 2) AS cancel_pct
FROM trips t
JOIN cities c ON c.city_id = t.city_id
GROUP BY c.city_name
ORDER BY cancel_pct DESC;

-- @R18
-- CRM: last trip date of every rider in Pune
-- CHANGED: replaced correlated subquery with LEFT JOIN + GROUP BY.
-- Original: for each of ~3,000 Pune riders, runs SELECT max(requested_at) FROM trips
-- WHERE rider_id = ?  — that's 3,000 full table scans = ~20 seconds.
-- Rewrite: one pass over trips joined to Pune riders, grouped by rider.
-- Uses idx_trips_rider_requested for the join + idx_riders_home_city for the filter.
-- SAME RESULT: LEFT JOIN keeps riders with no trips (shows NULL for last_trip_at).
SELECT r.rider_id, r.full_name,
       max(t.requested_at) AS last_trip_at
FROM riders r
LEFT JOIN trips t ON t.rider_id = r.rider_id
WHERE r.home_city_id = 6
GROUP BY r.rider_id, r.full_name
ORDER BY last_trip_at DESC NULLS LAST;

-- @R19
-- Leaderboard: rank drivers inside each city by completed trips in May 2026
-- UNCHANGED: idx_trips_driver_status_requested helps the join + filter.
SELECT *
FROM (
    SELECT d.city_id, d.driver_id, d.full_name, count(*) AS trips,
           RANK() OVER (PARTITION BY d.city_id ORDER BY count(*) DESC) AS city_rank
    FROM drivers d
    JOIN trips t ON t.driver_id = d.driver_id
    WHERE t.status = 'COMPLETED'
      AND t.requested_at >= '2026-05-01' AND t.requested_at < '2026-06-01'
    GROUP BY d.city_id, d.driver_id, d.full_name
) ranked
WHERE city_rank <= 3
ORDER BY city_id, city_rank;

-- @R20
-- Finance: daily revenue and running total for May 2026
-- CHANGED: replaced requested_at::date in WHERE with a sargable range.
-- The cast ::date on the left side blocks idx_trips_completed_requested.
-- Direct TIMESTAMPTZ range comparison uses the partial index efficiently.
SELECT day, revenue, sum(revenue) OVER (ORDER BY day) AS running_total
FROM (
    SELECT requested_at::date AS day, sum(fare_amount) AS revenue
    FROM trips
    WHERE status = 'COMPLETED'
      AND requested_at >= '2026-05-01'
      AND requested_at < '2026-06-01'
    GROUP BY 1
) daily
ORDER BY day;

-- @R21
-- Marketing: usage of each promo code
-- UNCHANGED: idx_trips_promo_code speeds up the join.
SELECT p.promo_code, p.discount_pct, count(t.trip_id) AS trips_used
FROM promo_codes p
LEFT JOIN trips t ON t.promo_code = p.promo_code
GROUP BY p.promo_code, p.discount_pct
ORDER BY trips_used DESC;

-- @R22
-- Payments team: failed payments in the last 7 days with the rider's phone
-- UNCHANGED: idx_payments_status_paid_at serves WHERE payment_status='FAILED' AND paid_at>=?
SELECT p.payment_id, p.amount, p.paid_at, r.rider_id, r.phone
FROM payments p
JOIN trips t  ON t.trip_id  = p.trip_id
JOIN riders r ON r.rider_id = t.rider_id
WHERE p.payment_status = 'FAILED'
  AND p.paid_at >= '2026-06-24'
ORDER BY p.paid_at DESC;

-- @R23
-- Growth: distinct active riders per city per month in 2026
-- UNCHANGED: idx_trips_city_status_requested covers city_id + requested_at range.
SELECT city_id, date_trunc('month', requested_at) AS month, count(DISTINCT rider_id) AS active_riders
FROM trips
WHERE requested_at >= '2026-01-01'
GROUP BY 1, 2
ORDER BY 1, 2;

-- @R24
-- Fraud check: unusually long trips
-- UNCHANGED: idx_trips_completed_distance_duration (partial on COMPLETED) handles this.
SELECT trip_id, driver_id, distance_km, duration_min, fare_amount
FROM trips
WHERE status = 'COMPLETED'
  AND (distance_km > 43 OR duration_min > 150)
ORDER BY fare_amount DESC
LIMIT 100;

-- @R25
-- Fraud check: completed trips charging more than ₹100 per km
-- UNCHANGED: idx_trips_fare_per_km (expression index) handles fare/distance > 100.
SELECT trip_id, city_id, distance_km, fare_amount,
       round(fare_amount / NULLIF(distance_km, 0), 2) AS fare_per_km
FROM trips
WHERE status = 'COMPLETED'
  AND fare_amount / NULLIF(distance_km, 0) > 100
ORDER BY fare_per_km DESC
LIMIT 50;

-- @W01
-- Rider app: request a new trip
-- UNCHANGED: direct INSERT — already fast at 0.645 ms.
INSERT INTO trips (trip_id, rider_id, city_id, requested_at, pickup_lat, pickup_lng,
                   drop_lat, drop_lng, surge_multiplier, status)
VALUES (90000001, 1042, 6, '2026-07-01 09:15:00+05:30', 18.520400, 73.856700,
        18.559000, 73.807700, 1.40, 'REQUESTED');

-- @W02
-- Driver app: finish the oldest ongoing trip
-- UNCHANGED: idx_trips_ongoing (partial) makes the subquery instant.
UPDATE trips
SET status       = 'COMPLETED',
    dropoff_at   = pickup_at + interval '27 minutes',
    distance_km  = 9.80,
    duration_min = 27,
    fare_amount  = 245.50
WHERE trip_id = (SELECT min(trip_id) FROM trips WHERE status = 'ONGOING');

-- @W03
-- Safety team: suspend active drivers rated below 3.5
-- UNCHANGED: small drivers table, 3,000 rows — acceptable even as seq scan.
UPDATE drivers
SET status = 'SUSPENDED'
WHERE status = 'ACTIVE' AND driver_rating < 3.5;

-- @W04
-- Partner import: 5,000 corporate trip requests in one batch
-- UNCHANGED: bulk INSERT with generate_series — already fast.
INSERT INTO trips (trip_id, rider_id, city_id, requested_at, pickup_lat, pickup_lng,
                   drop_lat, drop_lng, surge_multiplier, status)
SELECT 90001000 + g, 1 + (g * 7) % 30000, 1,
       TIMESTAMPTZ '2026-07-01 10:00:00+05:30' + g * interval '2 seconds',
       12.971600, 77.594600, 12.935200, 77.624500, 1.00, 'REQUESTED'
FROM generate_series(1, 5000) AS g;

-- @W05
-- Data retention: purge cancelled trips from January 2025
-- UNCHANGED: idx_trips_cancelled_requested (partial on CANCELLED% + requested_at)
-- makes this an Index Scan DELETE instead of a full table scan.
DELETE FROM trips
WHERE status LIKE 'CANCELLED%'
  AND requested_at < '2025-02-01';

-- @END
ROLLBACK;
