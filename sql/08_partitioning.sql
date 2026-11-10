-- =============================================================
-- Phase 5: Partitioning DDL for scalability
--
-- Why partitioning?
--   trips is 300k rows now; at 20× it becomes 6M rows.
--   At 100× (30M rows/year), full table scans on trips become
--   unusable (minutes per query).
--
-- Strategy: RANGE partition trips by requested_at (monthly).
--   - Almost every query filters on requested_at or a date range.
--   - PostgreSQL will do "partition pruning" — it only opens the
--     partitions that overlap the query's date range.
--   - A query for May 2026 only touches ONE partition instead of
--     all 18 months of data.
--
-- This file shows:
--   1. How to create a partitioned version of trips.
--   2. How to verify partition pruning with EXPLAIN.
--   3. Primary key rules for partitioned tables.
--   4. How to add indexes to partitions.
--
-- NOTE: This creates a NEW table uber.trips_partitioned so the
-- existing uber.trips (with loaded data) is not disturbed.
-- In a real migration you would rename and swap them.
-- =============================================================

SET search_path TO uber;

-- -------------------------------------------------------------
-- Step 1: Create the partitioned table
--
-- Partition key: requested_at (TIMESTAMPTZ)
-- Partition strategy: RANGE (by month)
--
-- PRIMARY KEY rule for partitioned tables:
--   PostgreSQL requires the partition key column to be part of
--   the primary key. So the PK is (trip_id, requested_at) not
--   just (trip_id). This is a PostgreSQL constraint — it needs
--   to know which partition to check for duplicates.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS trips_partitioned (
    trip_id           INTEGER         NOT NULL,
    rider_id          INTEGER         NOT NULL,
    driver_id         INTEGER,
    vehicle_id        INTEGER,
    city_id           SMALLINT        NOT NULL,
    promo_code        VARCHAR(20),
    requested_at      TIMESTAMPTZ     NOT NULL,
    pickup_at         TIMESTAMPTZ,
    dropoff_at        TIMESTAMPTZ,
    pickup_lat        NUMERIC(9,6)    NOT NULL,
    pickup_lng        NUMERIC(9,6)    NOT NULL,
    drop_lat          NUMERIC(9,6)    NOT NULL,
    drop_lng          NUMERIC(9,6)    NOT NULL,
    distance_km       NUMERIC(7,2),
    duration_min      SMALLINT,
    surge_multiplier  NUMERIC(4,2)    NOT NULL DEFAULT 1.00,
    fare_amount       NUMERIC(10,2),
    status            VARCHAR(20)     NOT NULL,

    -- PK must include the partition key (requested_at) for PostgreSQL partitioning
    PRIMARY KEY (trip_id, requested_at),

    CONSTRAINT chk_tp_status CHECK (
        status IN ('REQUESTED','ACCEPTED','ONGOING','COMPLETED',
                   'CANCELLED_BY_RIDER','CANCELLED_BY_DRIVER')
    ),
    CONSTRAINT chk_tp_surge CHECK (surge_multiplier >= 1.00)
)
PARTITION BY RANGE (requested_at);

-- -------------------------------------------------------------
-- Step 2: Create monthly partitions
--
-- Data spans Jan 2025 – Jun 2026 (18 months).
-- For 20× data (next year): add 2026-07 through 2027-06.
-- For 100× data: pre-create partitions for 5+ years.
--
-- Naming convention: trips_YYYY_MM
-- -------------------------------------------------------------

-- 2025 partitions
CREATE TABLE IF NOT EXISTS trips_2025_01 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

CREATE TABLE IF NOT EXISTS trips_2025_02 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');

CREATE TABLE IF NOT EXISTS trips_2025_03 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');

CREATE TABLE IF NOT EXISTS trips_2025_04 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2025-04-01') TO ('2025-05-01');

CREATE TABLE IF NOT EXISTS trips_2025_05 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');

CREATE TABLE IF NOT EXISTS trips_2025_06 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');

CREATE TABLE IF NOT EXISTS trips_2025_07 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');

CREATE TABLE IF NOT EXISTS trips_2025_08 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');

CREATE TABLE IF NOT EXISTS trips_2025_09 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');

CREATE TABLE IF NOT EXISTS trips_2025_10 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');

CREATE TABLE IF NOT EXISTS trips_2025_11 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');

CREATE TABLE IF NOT EXISTS trips_2025_12 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

-- 2026 partitions (seed data goes to Jun 2026; pre-create through Dec 2026)
CREATE TABLE IF NOT EXISTS trips_2026_01 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

CREATE TABLE IF NOT EXISTS trips_2026_02 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

CREATE TABLE IF NOT EXISTS trips_2026_03 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');

CREATE TABLE IF NOT EXISTS trips_2026_04 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');

CREATE TABLE IF NOT EXISTS trips_2026_05 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');

CREATE TABLE IF NOT EXISTS trips_2026_06 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

-- Future partitions for expected 20× growth
CREATE TABLE IF NOT EXISTS trips_2026_07 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

CREATE TABLE IF NOT EXISTS trips_2026_08 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');

CREATE TABLE IF NOT EXISTS trips_2026_09 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');

CREATE TABLE IF NOT EXISTS trips_2026_10 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');

CREATE TABLE IF NOT EXISTS trips_2026_11 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');

CREATE TABLE IF NOT EXISTS trips_2026_12 PARTITION OF trips_partitioned
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');

-- Catch-all for anything outside the defined range (safety net)
CREATE TABLE IF NOT EXISTS trips_default PARTITION OF trips_partitioned DEFAULT;

-- -------------------------------------------------------------
-- Step 3: Load existing data into the partitioned table
-- (PostgreSQL automatically routes each row to the right partition)
-- -------------------------------------------------------------
INSERT INTO trips_partitioned
SELECT * FROM trips;

-- Refresh planner statistics on partitioned table and child partitions
ANALYZE trips_partitioned;

-- Verify row counts match
SELECT
    'trips (original)'    AS source, count(*) AS rows FROM trips
UNION ALL
SELECT
    'trips_partitioned',  count(*) FROM trips_partitioned;

-- Verify exact row count distribution across partitions
SELECT
    tableoid::regclass::text AS partition_name,
    count(*) AS row_count
FROM trips_partitioned
GROUP BY tableoid
ORDER BY partition_name;

-- Verify partition storage sizes (table data, indexes, total)
SELECT
    child.relname AS partition_name,
    pg_size_pretty(pg_relation_size(child.oid)) AS table_size,
    pg_size_pretty(pg_indexes_size(child.oid)) AS index_size,
    pg_size_pretty(pg_total_relation_size(child.oid)) AS total_size
FROM pg_inherits
JOIN pg_class child ON child.oid = pg_inherits.inhrelid
JOIN pg_class parent ON parent.oid = pg_inherits.inhparent
WHERE parent.relname = 'trips_partitioned'
ORDER BY child.relname;

-- -------------------------------------------------------------
-- Step 4: Add indexes to each partition
-- (In PostgreSQL 12+, CREATE INDEX on the parent automatically
-- creates matching indexes on all child partitions)
-- -------------------------------------------------------------

-- Primary lookup index: (rider_id, requested_at) per partition
CREATE INDEX IF NOT EXISTS idx_tp_rider_requested
    ON trips_partitioned (rider_id, requested_at DESC);

-- Active trips partial index (across all partitions)
CREATE INDEX IF NOT EXISTS idx_tp_active_status
    ON trips_partitioned (requested_at)
    WHERE status IN ('REQUESTED', 'ACCEPTED', 'ONGOING');

-- Driver + status index for earnings queries
CREATE INDEX IF NOT EXISTS idx_tp_driver_status_requested
    ON trips_partitioned (driver_id, status, requested_at);

-- City + status index for city-level queries
CREATE INDEX IF NOT EXISTS idx_tp_city_status_requested
    ON trips_partitioned (city_id, status, requested_at);

-- Completed trips partial index with requested_at (serves R20 daily revenue)
CREATE INDEX IF NOT EXISTS idx_tp_completed_requested
    ON trips_partitioned (requested_at)
    WHERE status = 'COMPLETED';

-- Promo code lookup index (serves R21 promo usage)
CREATE INDEX IF NOT EXISTS idx_tp_promo_code
    ON trips_partitioned (promo_code)
    WHERE promo_code IS NOT NULL;

-- Completed trips fraud distance & duration index (serves R24)
CREATE INDEX IF NOT EXISTS idx_tp_completed_distance_duration
    ON trips_partitioned (distance_km, duration_min)
    WHERE status = 'COMPLETED';

-- Completed trips fare per km expression index (serves R25)
CREATE INDEX IF NOT EXISTS idx_tp_fare_per_km
    ON trips_partitioned ((fare_amount / NULLIF(distance_km, 0)))
    WHERE status = 'COMPLETED';

-- Ongoing trips partial index (serves W02)
CREATE INDEX IF NOT EXISTS idx_tp_ongoing
    ON trips_partitioned (trip_id)
    WHERE status = 'ONGOING';

-- Cancelled trips partial index with requested_at (serves W05 data retention)
CREATE INDEX IF NOT EXISTS idx_tp_cancelled_requested
    ON trips_partitioned (requested_at)
    WHERE status LIKE 'CANCELLED%';

-- Re-analyze to update index statistics across all partitions
ANALYZE trips_partitioned;

-- -------------------------------------------------------------
-- Step 5: Verify partition pruning with EXPLAIN
--
-- This is the key benefit: a query for May 2026 only scans
-- the trips_2026_05 partition (≈16,500 rows), not all 300,000.
-- -------------------------------------------------------------

-- Show partition pruning for R04 (Bengaluru, 10 May 2026)
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT trip_id, status, requested_at, fare_amount
FROM trips_partitioned
WHERE city_id = 1
  AND requested_at >= '2026-05-10'
  AND requested_at <  '2026-05-11';

-- Show partition pruning for R20 (May 2026 revenue)
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT requested_at::date AS day, sum(fare_amount) AS revenue
FROM trips_partitioned
WHERE status = 'COMPLETED'
  AND requested_at >= '2026-05-01'
  AND requested_at <  '2026-06-01'
GROUP BY 1
ORDER BY 1;

-- Show partition pruning for R06 (June 2026)
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT city_id, count(*) AS completed_trips
FROM trips_partitioned
WHERE status = 'COMPLETED'
  AND requested_at >= '2026-06-01'
  AND requested_at <  '2026-07-01'
GROUP BY city_id
ORDER BY completed_trips DESC;

-- -------------------------------------------------------------
-- How to add a new month partition in production:
-- ALTER TABLE trips_partitioned DETACH PARTITION trips_default;
-- CREATE TABLE trips_2027_01 PARTITION OF trips_partitioned
--     FOR VALUES FROM ('2027-01-01') TO ('2027-02-01');
-- ALTER TABLE trips_partitioned ATTACH PARTITION trips_default DEFAULT;
-- This takes milliseconds — no table lock, no downtime.
-- -------------------------------------------------------------

-- -------------------------------------------------------------
-- How to archive old data (e.g. trips older than 2 years):
-- ALTER TABLE trips_partitioned DETACH PARTITION trips_2025_01;
-- -- trips_2025_01 is now a standalone table, not part of queries
-- -- Move it to cold storage / dump to S3, then:
-- DROP TABLE trips_2025_01;  -- or keep for historical queries
-- -------------------------------------------------------------
