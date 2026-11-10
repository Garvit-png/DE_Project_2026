# Uber Ride-Hailing Database: DBMS Project

**Team No.:** T0001 | **Course:** Database Management Systems | **Year:** B.Tech 2nd Year  
**Database:** PostgreSQL 16.15 | **Machine:** MacBook Pro M4  
**Repository:** [Garvit-png/DE_Project_2026](https://github.com/Garvit-png/DE_Project_2026)

---

## Team

| Role | Name | Enrollment No. | GitHub |
|------|------|----------------|--------|
| Group Lead | Garvit Gandhi | 2501010166 | Garvit-png |
| Member | Japinder Kaur | 2501010649 | japinderofficial-hub |
| Member | Vansh Adhlakha | 2501010496 | VanshAdhlakha |
| Member | Keshav | 2501010217 | Keshavv07 |

---

## Headline Numbers

| Metric | Value |
|--------|------:|
| Total queries optimized | 30 (25 read + 5 write) |
| Baseline total time | ~40,014 ms |
| Optimized total time | ~397 ms |
| **Overall speedup** | **99.0% (100×)** |
| Biggest single win | R18: 20,451 ms → 25 ms (802×) |
| Second biggest win | W05: 19,091 ms → 10 ms (1,864×) |
| Bug found & fixed | R10: NOT IN returned 0 rows (NULL trap) |
| Indexes created | 19 (composite, partial, expression, GIN) |
| CHECK constraints | 13+ across 8 tables |
| Integrity checks | 5 (all pass with 0 violations) |

---

## What This Project Does

Uber India runs a ride-hailing service across 10 cities. The database was built quickly with no documented schema — only raw CSV data exports. Our job across 5 phases:

1. **Understand** the 9 performance problems reported by product teams
2. **Build** a correct, well-constrained schema from CSV data exports
3. **Measure** how 30 key queries perform (baseline timings)
4. **Optimize** them using indexes + query rewrites (results must stay identical)
5. **Prove** the database can handle 20× growth (partitioning + scalability design)

---

## How to Run Everything From Scratch

### Prerequisites
- PostgreSQL 15+ installed and running
- `seed_data.zip` unzipped to `seed_data/` in project root
- `psql` CLI available

### Step 1: Create database and schema
```bash
psql -d postgres -c "CREATE DATABASE uber_db;"
psql -d uber_db -f sql/01_schema.sql
```

### Step 2: Load seed data
```bash
psql -d uber_db -f sql/02_load_data.sql
```
This loads 8 CSV files in FK-safe order and runs 5 integrity checks.

### Step 3: Run baseline benchmarks (Phase 3)
```bash
./benchmarks/run_benchmark.sh uber_db baseline 3
```
Output: `benchmarks/results/baseline/summary.csv` + raw plans for all 30 queries.

### Step 4: Apply indexes (Phase 4)
```bash
psql -d uber_db -f sql/05_indexes.sql
```
Creates 19 indexes (composite, partial, expression, GIN trigram).

### Step 5: Run optimized benchmarks (Phase 4)
```bash
./benchmarks/run_benchmark.sh uber_db optimized 3 sql/06_optimized_queries.sql
```
Output: `benchmarks/results/optimized/summary.csv` + raw plans.

### Step 6: Set up partitioning (Phase 5)
```bash
psql -d uber_db -f sql/08_partitioning.sql
```
Creates monthly RANGE partitions on trips, verifies partition pruning with EXPLAIN.

---

## Repository Structure

```
DE_Project_2026/
├── README.md                              # This file
├── team.json                               # Team details
├── CHECKPOINTS.md                          # Checkpoint dates and requirements
├── .gitignore                              # Excludes seed_data/, WHAT_I_DID.md
│
├── docs/
│   ├── 01_problem_understanding.md         # CP1: P1-P9 analysis, stakeholders, classification
│   ├── 02_schema_design.md                 # CP1: Data dictionary, normal forms, integrity checks
│   ├── 03_baseline_timings.md              # CP2: 30 queries × 3 runs, scan types, analysis
│   ├── 04_optimization_report.md           # CP3: Before/after table, bug fix, index sizes
│   └── 05_scalability_report.md            # CP4: 20× projections, growth analysis, sharding
│
├── sql/
│   ├── 01_schema.sql                       # CP1: 8 tables, 13+ CHECK constraints, PKs, FKs
│   ├── 02_load_data.sql                    # CP1: \copy in FK-safe order + 5 integrity checks
│   ├── 05_indexes.sql                      # CP3: 19 indexes with per-query explanations
│   ├── 06_optimized_queries.sql            # CP3: 30 queries (6 rewritten, results unchanged)
│   └── 08_partitioning.sql                 # CP4: Monthly RANGE partitions on trips
│
├── diagrams/
│   ├── er_diagram.png                      # CP1: ER diagram (8 tables, 10 relationships)
│   └── er_diagram.mmd                      # CP1: Mermaid source code
│
├── queries/
│   └── workload_30.sql                     # Given by faculty (do not edit)
│
└── benchmarks/
    ├── run_benchmark.sh                    # Given by faculty
    └── results/
        ├── baseline/                       # CP2: summary.csv + R01-W05.txt raw plans
        ├── optimized/                      # CP3: summary.csv + R01-W05.txt raw plans
        └── large/                          # CP4: projected large dataset summary.csv
```

[View ER Diagram](diagrams/er_diagram.png)

---

## Checkpoint Status

| CP | Due | What | Status | Commit |
|----|-----|------|:------:|--------|
| CP0 | Nov 3 | Setup (workload, benchmark script, team.json) | ✅ | `078895f` |
| CP1 | Nov 16 | Schema, load script, ER diagram, problem understanding | ✅ | `2434a49` |
| CP2 | Nov 17 | Baseline timings for all 30 queries | ✅ | `a345fd1` |
| CP3 | Nov 19 | Indexes, optimized queries, optimization report | ✅ | `d5a3209` |
| CP4 | Nov 23 | Scalability report, partitioning DDL, large dataset | ✅ | `b0d9fcd` |

---

## Phase-by-Phase Summary

### Phase 1: Problem Understanding + Schema Design

**9 problems identified** (P1-P9), classified as customer-facing/real-time or reporting/analytics:
- P1: Rider trip history slow (R01, R15)
- P2: Driver earnings slow (R02, R07, R19)
- P3: Email login fails with capitals (R03)
- P4: Live dispatch refresh > 3s (R04, R05, W01, W02)
- P5: Finance reports timeout (R08, R20, R22)
- P6: Win-back campaign wrong results (R09, R10, R18)
- P7: Fraud checks scan whole table (R24, R25)
- P8: Admin pagination degrades (R16)
- P9: Analytics dashboards slow (R06, R11, R12, R17, R21, R23)

**Schema:** 8 tables in `uber` schema, 13+ CHECK constraints, composite PK on ratings `(trip_id, rated_by)`, nullable driver_id/vehicle_id for cancelled trips, justified denormalized rating columns.

### Phase 2: Baseline Timings

All 30 queries benchmarked with `EXPLAIN (ANALYZE, BUFFERS)`, 3 runs each. Key findings:
- Almost every query does **Seq Scan on trips** (300k rows) — no non-PK indexes existed
- R18 (20.5s) and W05 (19.1s) are catastrophically slow
- R14 (0.033ms) is already fast — UNIQUE index on registration_no existed
- R10's `NOT IN` returns 0 rows — the **wrong-result bug**

### Phase 3: Optimization

**19 indexes created** across 5 types:

| Type | Example | Serves |
|------|---------|--------|
| Composite B-tree | `(rider_id, requested_at DESC)` | R01 |
| Partial | `WHERE status IN ('REQUESTED','ACCEPTED','ONGOING')` | R05, W02, W05 |
| Expression | `ON riders (LOWER(email))` | R03 |
| GIN trigram | `USING GIN (full_name gin_trgm_ops)` | R13 |
| FK index | `ON payments (trip_id)` | R15 |

**6 queries rewritten:**
- R02, R08, R20: `DATE()` / `EXTRACT()` / `::date` → sargable TIMESTAMPTZ ranges
- R09, R10: `NOT IN` → `NOT EXISTS` (fixes NULL bug, also faster)
- R16: `OFFSET 200000` → keyset pagination `WHERE trip_id <= anchor`
- R18: correlated subquery → `LEFT JOIN ... GROUP BY` (802× faster)

**Bug fixed:** R10 `NOT IN (subquery)` returned 0 rows because cancelled trips have NULL `driver_id`. When a subquery returns NULL, `NOT IN` evaluates to UNKNOWN for every row. Fixed with `NOT EXISTS` → returns correct 978 rows.

### Phase 4: Scalability

**Partitioning:** `trips` table partitioned by RANGE on `requested_at` (monthly). A query for May 2026 only scans `trips_2026_05` (~16k rows) instead of all 300k — 94% data eliminated. Verified with EXPLAIN.

**Growth analysis (3 categories):**
- Stayed same (<3×): 15 queries using index seeks or partition pruning
- Grew ~20× (linear): 7 queries that must read most of the table (honest scans)
- Would have grown >20× without fix: R18 (quadratic → linear), W05 (full scan → partial index)

**Architecture for 100× scale:**
- Partitioning: RANGE monthly on `requested_at` (done)
- Sharding: by `city_id` (trips are city-local)
- Read replicas: analytics queries → replica; writes + real-time → primary
- VACUUM: aggressive autovacuum for trips (scale_factor = 0.01)
- Caching: Redis for login (R03), promo usage (R21), surge (R12)

---

## Data Dictionary Summary

| Table | Rows | PK | Key Columns |
|-------|-----:|----|-------------|
| cities | 10 | city_id (SMALLINT) | city_name (UNIQUE) |
| riders | 30,000 | rider_id | email (UNIQUE), phone (UNIQUE), home_city_id (FK) |
| drivers | 3,000 | driver_id | license_no (UNIQUE), phone (UNIQUE), city_id (FK), status |
| vehicles | 3,300 | vehicle_id | registration_no (UNIQUE), driver_id (FK) |
| promo_codes | 40 | promo_code | discount_pct, valid_from/to |
| trips | 300,000 | trip_id | rider_id, driver_id (NULL ok), city_id, requested_at, status, fare_amount |
| payments | 245,839 | payment_id | trip_id (FK), method, payment_status, paid_at |
| ratings | 307,214 | (trip_id, rated_by) | stars (1-5), comment |

---

## Topics Covered

- Data types & constraints (NUMERIC for money, TIMESTAMPTZ, CHAR(10) for phone)
- Keys & relationships (composite PK on ratings, FK with CASCADE/RESTRICT/SET NULL)
- Normalization (3NF/BCNF analysis with functional dependencies)
- Query execution plans (EXPLAIN ANALYZE, Seq Scan vs Index Scan)
- Indexing (B-tree, partial, expression, GIN trigram, covering)
- Query optimization (sargable predicates, NOT EXISTS, keyset pagination, JOIN rewrite)
- VACUUM/ANALYZE (autovacuum settings for hot tables)
- Partitioning (RANGE by month, partition pruning, PK rules)
- Sharding (by city_id, cross-shard query handling)
- Read replicas and caching strategy
