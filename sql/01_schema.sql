-- =============================================================
-- Phase 2: Schema for Uber India ride-hailing database
-- Run on a fresh PostgreSQL database (v15+) with:
--   psql -d <your_db> -f sql/01_schema.sql
--
-- What this file does:
--   1. Creates schema "uber" and sets it as the search path.
--   2. Creates all 8 tables in parent-before-child order.
--   3. Adds PRIMARY KEY, FOREIGN KEY, UNIQUE, NOT NULL, and
--      CHECK constraints (12+).
--   4. Does NOT create any extra index — only the automatic
--      indexes from PK and UNIQUE are present.  That is
--      intentional: Phase 3 measures the untuned baseline.
-- =============================================================

-- Step 1: create the schema
CREATE SCHEMA IF NOT EXISTS uber;
SET search_path TO uber;

-- ---------------------------------------------------------------
-- Table: cities
-- One row per city where Uber India operates (10 cities).
-- city_id is a small integer, no SERIAL needed.
-- ---------------------------------------------------------------
CREATE TABLE cities (
    city_id       SMALLINT        PRIMARY KEY,
    city_name     VARCHAR(50)     NOT NULL,
    state         VARCHAR(50)     NOT NULL,
    base_fare     NUMERIC(8,2)    NOT NULL,        -- fixed base charge, e.g. ₹50.00
    per_km_rate   NUMERIC(6,2)    NOT NULL,        -- ₹ per km
    per_min_rate  NUMERIC(5,2)    NOT NULL,        -- ₹ per minute
    launched_on   DATE            NOT NULL,

    -- Business rules
    CONSTRAINT chk_cities_base_fare     CHECK (base_fare   > 0),
    CONSTRAINT chk_cities_per_km_rate   CHECK (per_km_rate > 0),
    CONSTRAINT chk_cities_per_min_rate  CHECK (per_min_rate > 0),
    CONSTRAINT uq_cities_name           UNIQUE (city_name)
);

-- ---------------------------------------------------------------
-- Table: riders
-- 30,000 riders.  email must be globally unique (login key).
-- phone must be unique (10-digit Indian mobile).
-- rider_rating is a denormalized average (source: ratings table).
-- ---------------------------------------------------------------
CREATE TABLE riders (
    rider_id      INTEGER         PRIMARY KEY,
    full_name     VARCHAR(100)    NOT NULL,
    email         VARCHAR(150)    NOT NULL,
    phone         CHAR(10)        NOT NULL,
    home_city_id  SMALLINT        NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    signup_date   DATE            NOT NULL,
    rider_rating  NUMERIC(3,2),                   -- NULL before any rating
    is_active     BOOLEAN         NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_riders_email  UNIQUE (email),
    CONSTRAINT uq_riders_phone  UNIQUE (phone),
    CONSTRAINT chk_riders_rating CHECK (rider_rating BETWEEN 1.0 AND 5.0)
);

-- ---------------------------------------------------------------
-- Table: drivers
-- 3,000 drivers.  license_no is a natural unique key.
-- driver_rating: denormalized average, same reasoning as riders.
-- status: ACTIVE / INACTIVE / SUSPENDED only.
-- ---------------------------------------------------------------
CREATE TABLE drivers (
    driver_id     INTEGER         PRIMARY KEY,
    full_name     VARCHAR(100)    NOT NULL,
    phone         CHAR(10)        NOT NULL,
    license_no    VARCHAR(20)     NOT NULL,
    city_id       SMALLINT        NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    joined_on     DATE            NOT NULL,
    driver_rating NUMERIC(3,2),                   -- NULL before any rating
    status        VARCHAR(10)     NOT NULL DEFAULT 'ACTIVE',

    CONSTRAINT uq_drivers_phone      UNIQUE (phone),
    CONSTRAINT uq_drivers_license_no UNIQUE (license_no),
    CONSTRAINT chk_drivers_rating    CHECK (driver_rating BETWEEN 1.0 AND 5.0),
    CONSTRAINT chk_drivers_status    CHECK (status IN ('ACTIVE','INACTIVE','SUSPENDED'))
);

-- ---------------------------------------------------------------
-- Table: vehicles
-- Each vehicle belongs to exactly one driver.
-- registration_no is the natural unique key (plate number).
-- vehicle_type and seat_capacity are validated with CHECKs.
-- ---------------------------------------------------------------
CREATE TABLE vehicles (
    vehicle_id        INTEGER         PRIMARY KEY,
    driver_id         INTEGER         NOT NULL REFERENCES drivers(driver_id) ON DELETE CASCADE,
    registration_no   VARCHAR(15)     NOT NULL,
    make              VARCHAR(30)     NOT NULL,
    model             VARCHAR(30)     NOT NULL,
    manufacture_year  SMALLINT        NOT NULL,
    vehicle_type      VARCHAR(10)     NOT NULL,
    seat_capacity     SMALLINT        NOT NULL,

    CONSTRAINT uq_vehicles_reg_no          UNIQUE (registration_no),
    CONSTRAINT chk_vehicles_type           CHECK (vehicle_type IN ('MINI','SEDAN','SUV','AUTO','BIKE')),
    CONSTRAINT chk_vehicles_seats          CHECK (seat_capacity BETWEEN 1 AND 8),
    CONSTRAINT chk_vehicles_year           CHECK (manufacture_year BETWEEN 2000 AND 2030)
);

-- ---------------------------------------------------------------
-- Table: promo_codes
-- promo_code itself is the natural PK (short uppercase code).
-- valid_from must be before valid_to.
-- ---------------------------------------------------------------
CREATE TABLE promo_codes (
    promo_code    VARCHAR(20)     PRIMARY KEY,
    discount_pct  SMALLINT        NOT NULL,
    max_discount  NUMERIC(8,2)    NOT NULL,
    valid_from    DATE            NOT NULL,
    valid_to      DATE            NOT NULL,
    is_active     BOOLEAN         NOT NULL DEFAULT TRUE,

    CONSTRAINT chk_promo_discount_pct  CHECK (discount_pct BETWEEN 1 AND 100),
    CONSTRAINT chk_promo_max_discount  CHECK (max_discount > 0),
    CONSTRAINT chk_promo_dates         CHECK (valid_to >= valid_from)
);

-- ---------------------------------------------------------------
-- Table: trips
-- 300,000 trips.  The central fact table of the schema.
--
-- Nullable columns (and WHY):
--   driver_id, vehicle_id : NULL when status is REQUESTED
--     (driver not yet assigned)
--   pickup_at, dropoff_at : NULL for cancelled or pending trips
--   distance_km, duration_min, fare_amount : NULL until completed
--   promo_code : NULL when no promo was applied
--
-- FK to promo_codes uses ON DELETE SET NULL so deleting an
-- expired promo does not delete the trips that used it.
-- ---------------------------------------------------------------
CREATE TABLE trips (
    trip_id           INTEGER         PRIMARY KEY,
    rider_id          INTEGER         NOT NULL REFERENCES riders(rider_id)     ON DELETE RESTRICT,
    driver_id         INTEGER                  REFERENCES drivers(driver_id)   ON DELETE RESTRICT,
    vehicle_id        INTEGER                  REFERENCES vehicles(vehicle_id) ON DELETE RESTRICT,
    city_id           SMALLINT        NOT NULL REFERENCES cities(city_id)      ON DELETE RESTRICT,
    promo_code        VARCHAR(20)              REFERENCES promo_codes(promo_code) ON DELETE SET NULL,
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

    -- Allowed status values
    CONSTRAINT chk_trips_status CHECK (
        status IN ('REQUESTED','ACCEPTED','ONGOING','COMPLETED',
                   'CANCELLED_BY_RIDER','CANCELLED_BY_DRIVER')
    ),
    -- Time ordering: dropoff must be after pickup
    CONSTRAINT chk_trips_dropoff_after_pickup CHECK (
        dropoff_at IS NULL OR pickup_at IS NULL OR dropoff_at > pickup_at
    ),
    -- pickup must be after or equal to requested_at
    CONSTRAINT chk_trips_pickup_after_request CHECK (
        pickup_at IS NULL OR pickup_at >= requested_at
    ),
    -- Surge must be >= 1 (cannot be a discount)
    CONSTRAINT chk_trips_surge CHECK (surge_multiplier >= 1.00),
    -- Completed trips must have a fare
    CONSTRAINT chk_trips_completed_has_fare CHECK (
        status != 'COMPLETED' OR fare_amount IS NOT NULL
    ),
    -- Completed trips must have distance and duration
    CONSTRAINT chk_trips_completed_has_distance CHECK (
        status != 'COMPLETED' OR (distance_km IS NOT NULL AND duration_min IS NOT NULL)
    ),
    -- Coordinates sanity: India bounding box approximately
    CONSTRAINT chk_trips_pickup_lat  CHECK (pickup_lat BETWEEN 8.0 AND 37.0),
    CONSTRAINT chk_trips_pickup_lng  CHECK (pickup_lng BETWEEN 68.0 AND 97.0),
    CONSTRAINT chk_trips_drop_lat    CHECK (drop_lat   BETWEEN 8.0 AND 37.0),
    CONSTRAINT chk_trips_drop_lng    CHECK (drop_lng   BETWEEN 68.0 AND 97.0),
    -- Distance and duration must be positive when present
    CONSTRAINT chk_trips_distance    CHECK (distance_km  IS NULL OR distance_km  > 0),
    CONSTRAINT chk_trips_duration    CHECK (duration_min IS NULL OR duration_min > 0),
    CONSTRAINT chk_trips_fare        CHECK (fare_amount  IS NULL OR fare_amount  > 0)
);

-- ---------------------------------------------------------------
-- Table: payments
-- 245,839 payments.  One payment per completed trip (some trips
-- have no payment yet — e.g. cash trips where payment is pending).
-- ON DELETE CASCADE: if a trip is deleted, its payment goes too.
-- ---------------------------------------------------------------
CREATE TABLE payments (
    payment_id      INTEGER         PRIMARY KEY,
    trip_id         INTEGER         NOT NULL REFERENCES trips(trip_id) ON DELETE CASCADE,
    amount          NUMERIC(10,2)   NOT NULL,
    method          VARCHAR(10)     NOT NULL,
    payment_status  VARCHAR(10)     NOT NULL,
    paid_at         TIMESTAMPTZ     NOT NULL,

    CONSTRAINT chk_payments_method  CHECK (method IN ('UPI','CASH','CARD','WALLET')),
    CONSTRAINT chk_payments_status  CHECK (payment_status IN ('SUCCESS','FAILED','REFUNDED')),
    CONSTRAINT chk_payments_amount  CHECK (amount > 0)
);

-- ---------------------------------------------------------------
-- Table: ratings
-- 307,214 ratings.  Composite PK = (trip_id, rated_by) because
-- each trip gets at most one rating from the RIDER and one from
-- the DRIVER.  ON DELETE CASCADE: rating has no meaning without
-- the trip.
-- ---------------------------------------------------------------
CREATE TABLE ratings (
    trip_id     INTEGER         NOT NULL REFERENCES trips(trip_id) ON DELETE CASCADE,
    rated_by    VARCHAR(6)      NOT NULL,   -- 'RIDER' or 'DRIVER'
    stars       SMALLINT        NOT NULL,
    comment     TEXT,                       -- optional free-text comment
    created_at  TIMESTAMPTZ     NOT NULL,

    PRIMARY KEY (trip_id, rated_by),
    CONSTRAINT chk_ratings_rated_by CHECK (rated_by IN ('RIDER','DRIVER')),
    CONSTRAINT chk_ratings_stars    CHECK (stars BETWEEN 1 AND 5)
);
