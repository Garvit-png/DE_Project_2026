-- =============================================================
-- Phase 4: Indexes for query optimization
--
-- Run AFTER 01_schema.sql and 02_load_data.sql:
--   psql -d uber_db -f sql/05_indexes.sql
--
-- Every index has a comment explaining:
--   - Which queries it serves
--   - Why this index type and column order
--
-- Index naming convention: idx_<table>_<cols>
-- =============================================================
SET search_path TO uber;

-- -------------------------------------------------------------
-- TRIPS table indexes
-- Trips (300k rows) is the hottest table — almost every query
-- touches it.  Column order rule: equality columns first, then
-- range/sort columns.
-- -------------------------------------------------------------

-- R01: WHERE rider_id = ? ORDER BY requested_at DESC LIMIT 20
-- Composite: equality on rider_id first, then sort column requested_at.
-- INCLUDE fare_amount, status, distance_km to enable Index Only Scan
-- for SELECT * (the planner can get most columns from the index).
CREATE INDEX idx_trips_rider_requested
    ON trips (rider_id, requested_at DESC);
-- Why DESC: query wants latest trips first, so index is stored in
-- matching order — no sort step needed.

-- R02: WHERE driver_id = ? AND status = 'COMPLETED' AND DATE(requested_at) BETWEEN ...
-- R03-style driver queries: equality driver_id + status, then date range.
-- Also serves R19 (driver_id join + status filter + date range).
CREATE INDEX idx_trips_driver_status_requested
    ON trips (driver_id, status, requested_at);

-- R04, R06, R12, R17, R23: WHERE city_id = ? AND status = ? AND requested_at range
-- Equality city_id + status, then range on requested_at.
-- Also serves R05 partial logic (status filter).
CREATE INDEX idx_trips_city_status_requested
    ON trips (city_id, status, requested_at);

-- R05: WHERE status IN ('REQUESTED','ACCEPTED','ONGOING') ORDER BY requested_at LIMIT 50
-- PARTIAL INDEX: only indexes the ~300 active rows out of 300,000.
-- Tiny index, extremely fast lookup, no wasted space on completed/cancelled rows.
CREATE INDEX idx_trips_active_status
    ON trips (requested_at)
    WHERE status IN ('REQUESTED', 'ACCEPTED', 'ONGOING');

-- R07: JOIN drivers ON city_id + status='COMPLETED' + date range + ORDER BY earnings
-- Covered by idx_trips_driver_status_requested when joined with drivers.
-- Additional index on city_id alone for faster join with cities in R07:
-- (already covered by idx_trips_city_status_requested above)

-- R09, R10: subquery WHERE requested_at >= ? (used in NOT EXISTS rewrite)
-- Simple index on requested_at alone for fast range scans in subqueries.
CREATE INDEX idx_trips_requested_at
    ON trips (requested_at);

-- R18: correlated subquery WHERE rider_id = ? — need index on rider_id alone
-- for fast lookup in the rewritten JOIN version.
-- (rider_id is leading column of idx_trips_rider_requested — already covered)

-- R20: WHERE status='COMPLETED' AND requested_at::date range, GROUP BY date
-- Partial index: only COMPLETED trips (245,839 rows), covering requested_at.
CREATE INDEX idx_trips_completed_requested
    ON trips (requested_at)
    WHERE status = 'COMPLETED';

-- R21: WHERE promo_code IS NOT NULL (LEFT JOIN from promo_codes to trips)
CREATE INDEX idx_trips_promo_code
    ON trips (promo_code)
    WHERE promo_code IS NOT NULL;

-- R24: WHERE status='COMPLETED' AND (distance_km > 43 OR duration_min > 150)
-- Partial index on COMPLETED trips with the fraud columns.
CREATE INDEX idx_trips_completed_distance_duration
    ON trips (distance_km, duration_min)
    WHERE status = 'COMPLETED';

-- R25: WHERE status='COMPLETED' AND fare_amount / NULLIF(distance_km,0) > 100
-- Expression index for the per-km fare calculation.
CREATE INDEX idx_trips_fare_per_km
    ON trips ((fare_amount / NULLIF(distance_km, 0)))
    WHERE status = 'COMPLETED';

-- W02: subquery SELECT min(trip_id) WHERE status='ONGOING'
-- Partial index on ONGOING trips only.
CREATE INDEX idx_trips_ongoing
    ON trips (trip_id)
    WHERE status = 'ONGOING';

-- W05: DELETE WHERE status LIKE 'CANCELLED%' AND requested_at < ?
-- Partial index on cancelled trips only, with requested_at for date range.
CREATE INDEX idx_trips_cancelled_requested
    ON trips (requested_at)
    WHERE status LIKE 'CANCELLED%';

-- -------------------------------------------------------------
-- RIDERS table indexes
-- -------------------------------------------------------------

-- R03: WHERE LOWER(email) = ?
-- Expression index: stores LOWER(email), allowing Index Scan on the expression.
-- Without this, the UNIQUE index on email (exact case) is useless for LOWER() queries.
CREATE INDEX idx_riders_lower_email
    ON riders (LOWER(email));

-- R13: WHERE full_name ILIKE '%sharma%'
-- GIN trigram index: the only way to speed up leading-wildcard ILIKE.
-- Requires the pg_trgm extension.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_riders_name_trgm
    ON riders USING GIN (full_name gin_trgm_ops);

-- R09, R18: WHERE home_city_id = ? (Bengaluru=1, Pune=6)
CREATE INDEX idx_riders_home_city
    ON riders (home_city_id);

-- -------------------------------------------------------------
-- PAYMENTS table indexes
-- -------------------------------------------------------------

-- R08: WHERE payment_status='SUCCESS' AND EXTRACT(YEAR FROM paid_at)=2026
-- R22: WHERE payment_status='FAILED' AND paid_at >= ?
-- Composite: equality on payment_status first, then range on paid_at.
CREATE INDEX idx_payments_status_paid_at
    ON payments (payment_status, paid_at);

-- R15: WHERE trip_id = ? (LEFT JOIN from trips to payments)
-- payments.trip_id has no index; PK is on payment_id.
CREATE INDEX idx_payments_trip_id
    ON payments (trip_id);

-- -------------------------------------------------------------
-- RATINGS table indexes
-- -------------------------------------------------------------

-- R11: WHERE rated_by='RIDER', GROUP BY driver_id (via trips join)
-- Composite on (rated_by, trip_id) allows fast filter + join.
CREATE INDEX idx_ratings_rated_by_trip
    ON ratings (rated_by, trip_id);

-- -------------------------------------------------------------
-- DRIVERS table indexes
-- -------------------------------------------------------------

-- R03/R10/R07: WHERE status='ACTIVE' — partial index on active drivers only.
CREATE INDEX idx_drivers_active
    ON drivers (driver_id)
    WHERE status = 'ACTIVE';

-- -------------------------------------------------------------
-- Refresh planner statistics after creating all indexes
-- -------------------------------------------------------------
ANALYZE trips;
ANALYZE riders;
ANALYZE payments;
ANALYZE ratings;
ANALYZE drivers;
