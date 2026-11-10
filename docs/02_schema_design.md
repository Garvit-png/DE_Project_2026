# Phase 2 – Schema Design

**Team:** T0001 | **Lead:** Garvit Gandhi | **Members:** Japinder Kaur, Vansh Adhlakha, Keshav

---

## How we figured out the schema

We opened every CSV file, checked the column headers, looked at sample rows, and answered these questions for each table:
- What type does each column need? (Is it a number? Money? A timestamp with timezone? A short code?)
- What is the primary key?
- Which columns point to other tables?
- Which columns can be empty, and why?
- What values are allowed?

Everything is in the `uber` schema: `CREATE SCHEMA uber; SET search_path TO uber;`

---

## Data Dictionary

### Table: `cities`
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| city_id | SMALLINT | PK | 10 cities, small number fits SMALLINT |
| city_name | VARCHAR(50) | NOT NULL, UNIQUE | Each city has a distinct name |
| state | VARCHAR(50) | NOT NULL | Never empty |
| base_fare | NUMERIC(8,2) | NOT NULL, > 0 | Money: needs decimal precision |
| per_km_rate | NUMERIC(6,2) | NOT NULL, > 0 | Rate must be positive |
| per_min_rate | NUMERIC(5,2) | NOT NULL, > 0 | Rate must be positive |
| launched_on | DATE | NOT NULL | Always present |

Indexes that exist automatically: PK on `city_id`, UNIQUE on `city_name`.

---

### Table: `riders`
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| rider_id | INTEGER | PK | Up to 30,000+ riders |
| full_name | VARCHAR(100) | NOT NULL | Never empty |
| email | VARCHAR(150) | NOT NULL, UNIQUE | Login key; stored with mixed case (Vivaan.Sharma1@Mail.com); queries use LOWER() |
| phone | CHAR(10) | NOT NULL, UNIQUE | 10-digit Indian mobile; fixed length |
| home_city_id | SMALLINT | NOT NULL, FK → cities | Every rider belongs to a city |
| signup_date | DATE | NOT NULL | Always present |
| rider_rating | NUMERIC(3,2) | NULL ok, 1.0–5.0 | NULL before first rating; denormalized average from ratings table |
| is_active | BOOLEAN | NOT NULL | t/f from CSV |

**Data note:** Emails are stored with mixed case in the CSV. Login query (R03) uses `LOWER(email)` which means a plain B-tree index on `email` is useless for login. An expression index `ON riders (LOWER(email))` is the fix (Phase 4).

---

### Table: `drivers`
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| driver_id | INTEGER | PK | Up to 3,000+ drivers |
| full_name | VARCHAR(100) | NOT NULL | Never empty |
| phone | CHAR(10) | NOT NULL, UNIQUE | 10-digit; unique across drivers |
| license_no | VARCHAR(20) | NOT NULL, UNIQUE | Natural unique key (e.g. DL-DL01-00000001) |
| city_id | SMALLINT | NOT NULL, FK → cities | Every driver is in one city |
| joined_on | DATE | NOT NULL | Never empty |
| driver_rating | NUMERIC(3,2) | NULL ok, 1.0–5.0 | Denormalized average; source of truth is ratings |
| status | VARCHAR(10) | NOT NULL | Only ACTIVE, INACTIVE, SUSPENDED |

---

### Table: `vehicles`
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| vehicle_id | INTEGER | PK | — |
| driver_id | INTEGER | NOT NULL, FK → drivers (CASCADE) | Vehicle belongs to a driver; if driver deleted, vehicle goes too |
| registration_no | VARCHAR(15) | NOT NULL, UNIQUE | Plate number is globally unique |
| make | VARCHAR(30) | NOT NULL | e.g. Hyundai |
| model | VARCHAR(30) | NOT NULL | e.g. i10 |
| manufacture_year | SMALLINT | NOT NULL, 2000–2030 | Year is a small number |
| vehicle_type | VARCHAR(10) | NOT NULL | Only MINI, SEDAN, SUV, AUTO, BIKE |
| seat_capacity | SMALLINT | NOT NULL, 1–8 | Maximum 8 seats |

---

### Table: `promo_codes`
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| promo_code | VARCHAR(20) | PK | Natural key (e.g. RIDE001) |
| discount_pct | SMALLINT | NOT NULL, 1–100 | Percentage |
| max_discount | NUMERIC(8,2) | NOT NULL, > 0 | Money cap |
| valid_from | DATE | NOT NULL | Start of validity |
| valid_to | DATE | NOT NULL, >= valid_from | Must end after start |
| is_active | BOOLEAN | NOT NULL | t/f |

---

### Table: `trips`
This is the central fact table with 300,000 rows.

| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| trip_id | INTEGER | PK | — |
| rider_id | INTEGER | NOT NULL, FK → riders | A trip always has a rider |
| driver_id | INTEGER | NULL ok, FK → drivers | NULL for REQUESTED status (no driver yet); NULL for CANCELLED_* if driver never assigned |
| vehicle_id | INTEGER | NULL ok, FK → vehicles | Same reason as driver_id |
| city_id | SMALLINT | NOT NULL, FK → cities | Always known |
| promo_code | VARCHAR(20) | NULL ok, FK → promo_codes (SET NULL) | Most trips have no promo; using SET NULL so deleting a promo doesn't lose trip history |
| requested_at | TIMESTAMPTZ | NOT NULL | Always present; includes +05:30 offset |
| pickup_at | TIMESTAMPTZ | NULL ok | NULL for cancelled/pending trips |
| dropoff_at | TIMESTAMPTZ | NULL ok | NULL unless COMPLETED |
| pickup_lat, pickup_lng | NUMERIC(9,6) | NOT NULL | Coordinates always present at request time |
| drop_lat, drop_lng | NUMERIC(9,6) | NOT NULL | Destination always specified |
| distance_km | NUMERIC(7,2) | NULL ok | NULL until COMPLETED |
| duration_min | SMALLINT | NULL ok | NULL until COMPLETED |
| surge_multiplier | NUMERIC(4,2) | NOT NULL, ≥ 1.00 | Always present; 1.00 = no surge |
| fare_amount | NUMERIC(10,2) | NULL ok | NULL until COMPLETED |
| status | VARCHAR(20) | NOT NULL | One of 6 allowed values |

**CHECK constraints on trips (12 meaningful constraints):**
1. `status IN ('REQUESTED','ACCEPTED','ONGOING','COMPLETED','CANCELLED_BY_RIDER','CANCELLED_BY_DRIVER')`
2. `dropoff_at > pickup_at` (when both are not NULL)
3. `pickup_at >= requested_at` (when not NULL)
4. `surge_multiplier >= 1.00`
5. `status = 'COMPLETED' → fare_amount IS NOT NULL`
6. `status = 'COMPLETED' → distance_km IS NOT NULL AND duration_min IS NOT NULL`
7. `pickup_lat BETWEEN 8.0 AND 37.0` (India bounding box)
8. `pickup_lng BETWEEN 68.0 AND 97.0`
9. `drop_lat BETWEEN 8.0 AND 37.0`
10. `drop_lng BETWEEN 68.0 AND 97.0`
11. `distance_km > 0` (when not NULL)
12. `fare_amount > 0` (when not NULL)
13. `duration_min > 0` (when not NULL)

---

### Table: `payments`
| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| payment_id | INTEGER | PK | — |
| trip_id | INTEGER | NOT NULL, FK → trips (CASCADE) | Payment is useless without its trip |
| amount | NUMERIC(10,2) | NOT NULL, > 0 | Money |
| method | VARCHAR(10) | NOT NULL | Only UPI, CASH, CARD, WALLET |
| payment_status | VARCHAR(10) | NOT NULL | Only SUCCESS, FAILED, REFUNDED |
| paid_at | TIMESTAMPTZ | NOT NULL | Always present |

---

### Table: `ratings`
**Composite PK: `(trip_id, rated_by)`** — one rating per trip per side.

| Column | Type | Constraint | Why |
|--------|------|-----------|-----|
| trip_id | INTEGER | PK (part 1), FK → trips (CASCADE) | Rating belongs to a trip |
| rated_by | VARCHAR(6) | PK (part 2) | Only 'RIDER' or 'DRIVER' |
| stars | SMALLINT | NOT NULL, 1–5 | Rating scale |
| comment | TEXT | NULL ok | Optional free-text |
| created_at | TIMESTAMPTZ | NOT NULL | Always present |

---

## ER Diagram

See `diagrams/er_diagram.png` (and `er_diagram.mmd` for the Mermaid source).

**Relationships:**
- `cities` → `riders`: 1:N (one city, many riders via home_city_id)
- `cities` → `drivers`: 1:N (one city, many drivers)
- `cities` → `trips`: 1:N (one city, many trips)
- `drivers` → `vehicles`: 1:N (one driver can own multiple vehicles)
- `riders` → `trips`: 1:N (one rider, many trips)
- `drivers` → `trips`: 1:N (one driver, many trips)
- `vehicles` → `trips`: 1:N (one vehicle, many trips)
- `promo_codes` → `trips`: 1:N (one promo code used on many trips)
- `trips` → `payments`: 1:N (one trip, usually one payment; FAILED may be retried)
- `trips` → `ratings`: 1:2 (one trip, at most two ratings: one by RIDER, one by DRIVER)

---

## Normal Form Analysis

### Why each table is in 3NF/BCNF

**cities:** PK is `city_id`. All other columns (`city_name`, `state`, `base_fare`, …) depend only on `city_id`. No transitive dependencies. **3NF ✅**

**riders:** PK is `rider_id`. `email` and `phone` are candidate keys (UNIQUE). All non-key columns depend only on `rider_id`. The `rider_rating` is a denormalized column — it is derived from `ratings`, but we keep it for fast lookups (Uber shows it on every trip screen). We note this as a justified redundancy. **3NF ✅**

**drivers:** Same reasoning as `riders`. `driver_rating` is denormalized. `license_no` is a candidate key. **3NF ✅**

**vehicles:** PK is `vehicle_id`. `registration_no` is a candidate key. All columns depend on `vehicle_id` only. **3NF ✅**

**promo_codes:** PK is `promo_code` (natural). All columns depend only on it. **3NF ✅**

**trips:** PK is `trip_id`. All columns describe one trip. There is one derived column: `fare_amount` could be computed from `(base_fare + per_km_rate * distance_km + per_min_rate * duration_min) * surge_multiplier`. We keep `fare_amount` because: (a) the formula is approximate — actual fare may include promotions, surge pricing adjustments, and rounding; (b) it's needed for fast aggregation queries (R02, R07, R08). **3NF ✅ with noted justification.**

**payments:** PK is `payment_id`. All columns depend on `payment_id`. **3NF ✅**

**ratings:** PK is `(trip_id, rated_by)`. `stars` and `comment` depend on both PK columns together. **3NF ✅**

---

## Integrity Check Results

After running `sql/02_load_data.sql` on a fresh database:

| Check | Query | Result |
|-------|-------|--------|
| IC1: Completed trips with no payment | Every COMPLETED trip has ≥ 1 payment | **0 violations** ✅ |
| IC2: Vehicle/driver mismatch | No trip uses a vehicle from a different driver | **0 violations** ✅ |
| IC3: Payments with no trip | Every payment points to a real trip | **0 violations** ✅ |
| IC4: Ratings with no trip | Every rating points to a real trip | **0 violations** ✅ |
| IC5: Duplicate (trip_id, rated_by) | Each pair is unique | **0 violations** ✅ |

Row counts after load:

| Table | Expected | Loaded |
|-------|----------|--------|
| cities | 10 | 10 |
| riders | 30,000 | 30,000 |
| drivers | 3,000 | 3,000 |
| vehicles | 3,300 | 3,300 |
| promo_codes | 40 | 40 |
| trips | 300,000 | 300,000 |
| payments | 245,839 | 245,839 |
| ratings | 307,214 | 307,214 |

---

## Data Problems Found

1. **Mixed-case emails in `riders`:** Emails like `Vivaan.Sharma1@Mail.com` have uppercase letters. The login query (R03) uses `LOWER(email)`, so a plain B-tree index on `email` does not help. Fix: expression index on `LOWER(email)` in Phase 4.

2. **NULL driver/vehicle for cancelled trips:** About 15,098 trips have NULL `driver_id` and `vehicle_id`. These are trips that were cancelled before a driver was assigned (CANCELLED_BY_RIDER with no acceptance). This is valid — our schema allows NULL for these columns with a documented reason.

3. **NULL pickup_at and dropoff_at:** ~54,000 trips have NULL `pickup_at` (cancelled or still pending). ~54,000 have NULL `dropoff_at`. Our CHECK constraints handle this correctly: they only enforce ordering when both values are present.

4. **fare_amount and distance_km are NULL for non-completed trips:** All non-COMPLETED statuses (REQUESTED, ACCEPTED, ONGOING, CANCELLED_*) have NULL fare and distance. Our CHECK constraint `status = 'COMPLETED' → fare_amount IS NOT NULL` enforces this correctly in the other direction.
