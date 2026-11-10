-- =============================================================
-- Phase 2: Load seed data into the uber schema
--
-- Run AFTER sql/01_schema.sql, from the project root:
--   psql -d <your_db> -f sql/02_load_data.sql
--
-- What this file does:
--   1. Sets search_path to uber.
--   2. Loads tables in parent-before-child order so FK checks pass.
--   3. Runs ANALYZE to update statistics for the query planner.
--   4. Runs 5 integrity checks to verify the data loaded correctly.
--
-- IMPORTANT: seed_data/ must be in the project root (unzip seed_data.zip).
-- The \copy paths are relative to the directory psql is run from.
-- Run psql from the project root:
--   cd /path/to/DE_Project_2026
--   psql -d uber_db -f sql/02_load_data.sql
-- =============================================================

SET search_path TO uber;

-- ---------------------------------------------------------------
-- Load order:
--   1. cities         (no FKs)
--   2. riders         (FK → cities)
--   3. drivers        (FK → cities)
--   4. vehicles       (FK → drivers)
--   5. promo_codes    (no FKs)
--   6. trips          (FK → riders, drivers, vehicles, cities, promo_codes)
--   7. payments       (FK → trips)
--   8. ratings        (FK → trips)
-- ---------------------------------------------------------------

\copy cities      FROM 'seed_data/cities.csv'      WITH (FORMAT csv, HEADER true)
\copy riders      FROM 'seed_data/riders.csv'      WITH (FORMAT csv, HEADER true)
\copy drivers     FROM 'seed_data/drivers.csv'     WITH (FORMAT csv, HEADER true)
\copy vehicles    FROM 'seed_data/vehicles.csv'    WITH (FORMAT csv, HEADER true)
\copy promo_codes FROM 'seed_data/promo_codes.csv' WITH (FORMAT csv, HEADER true)
\copy trips       FROM 'seed_data/trips.csv'       WITH (FORMAT csv, HEADER true)
\copy payments    FROM 'seed_data/payments.csv'    WITH (FORMAT csv, HEADER true)
\copy ratings     FROM 'seed_data/ratings.csv'     WITH (FORMAT csv, HEADER true)

-- Update planner statistics after loading
ANALYZE cities;
ANALYZE riders;
ANALYZE drivers;
ANALYZE vehicles;
ANALYZE promo_codes;
ANALYZE trips;
ANALYZE payments;
ANALYZE ratings;

-- ---------------------------------------------------------------
-- Row-count verification
-- Expected: cities=10, riders=30000, drivers=3000, vehicles=3300,
--           promo_codes=40, trips=300000, payments=245839, ratings=307214
-- ---------------------------------------------------------------
SELECT 'cities'      AS tbl, count(*) AS rows FROM cities
UNION ALL
SELECT 'riders',      count(*) FROM riders
UNION ALL
SELECT 'drivers',     count(*) FROM drivers
UNION ALL
SELECT 'vehicles',    count(*) FROM vehicles
UNION ALL
SELECT 'promo_codes', count(*) FROM promo_codes
UNION ALL
SELECT 'trips',       count(*) FROM trips
UNION ALL
SELECT 'payments',    count(*) FROM payments
UNION ALL
SELECT 'ratings',     count(*) FROM ratings
ORDER BY tbl;

-- ---------------------------------------------------------------
-- Integrity check 1:
-- Every completed trip must have at least one payment.
--   Result: 0 rows means the check passes.
-- ---------------------------------------------------------------
SELECT 'IC1: completed trips with no payment' AS check_name,
       count(*) AS violations
FROM trips t
WHERE t.status = 'COMPLETED'
  AND NOT EXISTS (SELECT 1 FROM payments p WHERE p.trip_id = t.trip_id);

-- ---------------------------------------------------------------
-- Integrity check 2:
--   No trip should use a vehicle that belongs to a different driver.
--   Result: 0 rows means the check passes.
-- ---------------------------------------------------------------
SELECT 'IC2: trips with mismatched vehicle/driver' AS check_name,
       count(*) AS violations
FROM trips t
JOIN vehicles v ON v.vehicle_id = t.vehicle_id
WHERE t.driver_id IS NOT NULL
  AND v.driver_id <> t.driver_id;

-- ---------------------------------------------------------------
-- Integrity check 3:
--   Every payment must point to an existing trip (FK check at DB
--   level, but verify again at data level).
--   Result: 0 rows means the check passes.
-- ---------------------------------------------------------------
SELECT 'IC3: payments with no matching trip' AS check_name,
       count(*) AS violations
FROM payments p
WHERE NOT EXISTS (SELECT 1 FROM trips t WHERE t.trip_id = p.trip_id);

-- ---------------------------------------------------------------
-- Integrity check 4:
--   Ratings must only exist for trips that actually happened
--   (completed or cancelled — not for trips that never started).
--   Check: no rating for a non-existent trip.
--   Result: 0 rows means the check passes.
-- ---------------------------------------------------------------
SELECT 'IC4: ratings with no matching trip' AS check_name,
       count(*) AS violations
FROM ratings r
WHERE NOT EXISTS (SELECT 1 FROM trips t WHERE t.trip_id = r.trip_id);

-- ---------------------------------------------------------------
-- Integrity check 5:
--   Composite PK on ratings means each (trip_id, rated_by) pair
--   is unique.  Verify no duplicates survived the load.
--   Result: 0 rows means the check passes.
-- ---------------------------------------------------------------
SELECT 'IC5: duplicate (trip_id, rated_by) in ratings' AS check_name,
       count(*) AS violations
FROM (
    SELECT trip_id, rated_by, count(*) AS cnt
    FROM ratings
    GROUP BY trip_id, rated_by
    HAVING count(*) > 1
) dup;
