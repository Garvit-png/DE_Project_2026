# Uber Ride-Hailing Database: DBMS Project

**Course:** Database Management Systems · **Year:** B.Tech 2nd year · **Team size:** 4
**Database:** PostgreSQL 15 or newer · **Final submission:** Mon 23 Nov 2026
**Topics used:** Data types & constraints · Keys & relationships · Normalization · Query execution plans · Indexing · Query optimization · VACUUM/ANALYZE · Partitioning & sharding

## Files in this folder

| Path | What it is |
|------|------------|
| `README.md` | This project brief |
| `seed_data.zip` | 8 CSV files (300,000 trips): the only input for Phase 2. Unzip it to get `seed_data/` |
| `queries/workload_30.sql` | The 30 queries for Phase 3 (do not edit) |
| `benchmarks/run_benchmark.sh` | Timing script: 3 runs per query, average, raw plans saved |
| `CHECKPOINTS.md` | Checkpoint dates and the files each one needs (DE and AP repos) |

**Getting started:** **clone this repository and push it into your team's DE repo** (the DE repo you submitted in the form); the steps are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Keep the structure shown in [Repository structure](#repository-structure-submit-exactly-this). Unzip `seed_data.zip` inside your project folder, but don't commit the CSV files. Deadlines are in [`CHECKPOINTS.md`](CHECKPOINTS.md). Then begin with Phase 1.

---

## Team details (fill in before you start)

| Role       | Name           | Enrollment No. | GitHub Username       |
|------------|----------------|----------------|-----------------------|
| Group Lead | Garvit Gandhi  | 2501010166     | Garvit-png            |
| Member 2   | Japinder Kaur  | 2501010649     | japinderofficial-hub  |
| Member 3   | Vansh Adhlakha | 2501010496     | VanshAdhlakha         |
| Member 4   | Keshav         | 2501010217     | Keshavv07             |

**Team No.:** ____ · **Section:** ____ · **Repository URL:** ____

---

## How this project works

| Phase | What you do | You submit | Counts toward | Marks |
|-------|-------------|------------|---------------|------:|
| 1 | Understand the problem statements | `docs/01_problem_understanding.md` | Query Execution | 2 |
| 2 | Work out the database schema **from the seed data** and load it | `sql/01_schema.sql`, `sql/02_load_data.sql`, `docs/02_schema_design.md` | Query Execution | 5 |
| 3 | Run the **30 given SQL queries** and record their execution time | `docs/03_baseline_timings.md`, `benchmarks/results/baseline/` | Query Execution | 3 |
| 4 | Optimize the queries and record the new times | `sql/05_indexes.sql`, `sql/06_optimized_queries.sql`, `docs/04_optimization_report.md`, `benchmarks/results/optimized/` | Code Optimization | 16 |
| 5 | Scalability test on the **large dataset** (given later by faculty) and final report | `docs/05_scalability_report.md`, `benchmarks/results/large/` | Code Optimization | 14 |
| | **Total** | | | **40** |

---

## Phase 1: Problem statements

Uber runs millions of trips every day. In every city, riders request rides, the nearest driver accepts, the trip happens, the rider pays, and both sides rate each other. You have joined the database team of Uber India, which operates in **10 cities**: Bengaluru, Mumbai, Delhi, Hyderabad, Chennai, Pune, Kolkata, Ahmedabad, Jaipur and Lucknow.

The current database was put together quickly by an earlier team. It has **no documented schema** (only data exports survive), and the product teams are complaining:

| # | Problem reported | Team | Related queries |
|---|------------------|------|-----------------|
| P1 | "The **Your Trips** screen in the rider app takes too long to load for frequent riders." | Rider app | R01, R15 |
| P2 | "Drivers check their **earnings** many times a day, and the earnings page is slow." | Driver app | R02, R07, R19 |
| P3 | "**Login by email** fails for users who type capital letters, and the fix made login slow." | Identity | R03 |
| P4 | "The **live dispatch screen** must refresh every 3 seconds, but each refresh takes longer than that under load." | City operations | R04, R05, W01, W02 |
| P5 | "Monthly **finance reports** (revenue, payment methods, failed payments) time out." | Finance | R08, R20, R22 |
| P6 | "Marketing's **win-back campaign list** returns strange results, and one list was empty when it shouldn't be." | Marketing / Driver ops | R09, R10, R18 |
| P7 | "**Fraud checks** for long or over-priced trips scan the whole table every time." | Trust & Safety | R24, R25 |
| P8 | "The **admin panel** gets slower the further you page through trips." | Admin | R16 |
| P9 | "Analytics dashboards (surge, cancellations, growth, ratings) are slow, and we expect **10–20× more trips next year**." | Analytics / Leadership | R06, R11, R12, R17, R21, R23 |

**Your job:**
1. Rebuild a correct, well-constrained schema from the data exports (Phase 2).
2. Measure how the 30 most important queries perform today (Phase 3).
3. Make them fast **without changing their results** (Phase 4).
4. Prove the database will survive the next year's growth (Phase 5).

**Deliverable for Phase 1** (`docs/01_problem_understanding.md`, at most 1 page):
- For each problem P1–P9, write in your own words what the business needs and which **stakeholder** is affected (rider, driver, city ops, finance, marketing, trust & safety, admin, leadership).
- Classify each problem as **customer-facing / real-time** or **reporting / analytics**. This decides your performance targets later.
- List any assumptions you make.

---

## Phase 2: Work out the schema from the seed data

You receive **`seed_data.zip`**. Unzip it to get a folder **`seed_data/`** with 8 CSV files, a real export of the production data:

| File | Rows | What it contains |
|------|-----:|------------------|
| `cities.csv` | 10 | Cities where Uber operates and their fare rates |
| `riders.csv` | 30,000 | People who book rides |
| `drivers.csv` | 3,000 | Driver partners |
| `vehicles.csv` | 3,300 | Vehicles registered by drivers |
| `promo_codes.csv` | 40 | Discount codes |
| `trips.csv` | 300,000 | Every ride requested from 1 Jan 2025 to 30 Jun 2026 |
| `payments.csv` | 245,839 | Payments for completed trips |
| `ratings.csv` | 307,214 | Ratings given after trips (by rider and by driver) |

The first line of every file is the header (column names). Here are the headers and a few sample rows:

**cities.csv**
```
city_id,city_name,state,base_fare,per_km_rate,per_min_rate,launched_on
1,Bengaluru,Karnataka,50.00,12.00,1.50,2014-01-15
2,Mumbai,Maharashtra,55.00,13.50,1.75,2014-03-01
```

**riders.csv**
```
rider_id,full_name,email,phone,home_city_id,signup_date,rider_rating,is_active
1,Vivaan Sharma,Vivaan.Sharma1@Mail.com,9000000001,2,2024-03-16,3.9,t
2,Aditya Sharma,Aditya.Sharma2@Mail.com,9000000002,4,2022-04-30,4.5,t
```

**drivers.csv**
```
driver_id,full_name,phone,license_no,city_id,joined_on,driver_rating,status
1,Ananya Gupta,8000000001,DL-DL01-00000001,3,2023-06-20,4.6,ACTIVE
2,Kavya Khan,8000000002,DL-GJ01-00000002,8,2024-05-09,3.6,ACTIVE
```

**vehicles.csv**
```
vehicle_id,driver_id,registration_no,make,model,manufacture_year,vehicle_type,seat_capacity
1,1,DL01AA0001,Hyundai,i10,2022,MINI,4
2,2,GJ01AA0002,Maruti,Dzire,2023,SEDAN,4
```

**promo_codes.csv**
```
promo_code,discount_pct,max_discount,valid_from,valid_to,is_active
RIDE001,15,75.00,2025-01-31,2026-12-31,t
RIDE002,20,100.00,2025-03-02,2026-12-31,t
```

**trips.csv**
```
trip_id,rider_id,driver_id,vehicle_id,city_id,promo_code,requested_at,pickup_at,dropoff_at,pickup_lat,pickup_lng,drop_lat,drop_lng,distance_km,duration_min,surge_multiplier,fare_amount,status
1,6945,1922,1922,5,,2025-01-01 00:00:00+05:30,2025-01-01 00:10:07+05:30,2025-01-01 00:41:07+05:30,13.189840,80.159930,13.003266,80.245632,7.40,31,1.00,168.85,COMPLETED
2,1529,1000,1000,1,,2025-01-01 00:02:37+05:30,2025-01-01 00:08:14+05:30,2025-01-01 00:24:14+05:30,12.995984,77.525237,12.986103,77.510036,2.07,16,1.00,98.84,COMPLETED
```

**payments.csv**
```
payment_id,trip_id,amount,method,payment_status,paid_at
1,1,168.85,UPI,SUCCESS,2025-01-01 00:42:07+05:30
2,2,98.84,CASH,SUCCESS,2025-01-01 00:25:14+05:30
```

**ratings.csv**
```
trip_id,rated_by,stars,comment,created_at
1,DRIVER,5,,2025-01-01 01:03:23+05:30
1,RIDER,5,,2025-01-01 07:29:52+05:30
```

Open the files yourself (a spreadsheet, `head`, or `SELECT` after a quick load into a scratch table) and study the data carefully. **Nobody will give you the CREATE TABLE statements.** Working them out *is* the task.

### 2.1 What you must identify (for every table)
1. **Table name and column names.** Use exactly the file names and CSV headers. The 30 queries depend on them.
2. **Data type** of every column. Choose the *right* type, not just `TEXT` everywhere. Think about money, coordinates, timestamps with a time-zone offset, yes/no columns, small whole numbers and short codes.
3. **Primary key.** Is it one column, or a combination? (Hint: look closely at `ratings.csv`.)
4. **Foreign keys.** Which column points to which table? What should happen **ON DELETE** (CASCADE, RESTRICT or SET NULL), and why?
5. **NOT NULL vs NULL.** Some columns are empty in some rows. Find out **when** and **why** (look at the trip `status`) and decide which columns must never be empty.
6. **UNIQUE** columns (natural candidate keys such as phone numbers, emails, licence and registration numbers).
7. **CHECK constraints.** Write at least **12** that the data obeys and the business needs. Examples of what to look for: allowed status values, rating ranges, coordinate ranges, "drop-off after pick-up", rules that depend on `status`, and relationships between two columns (e.g. vehicle type and seat capacity).
8. **Relationships and cardinalities** (1:1, 1:N, M:N). Draw the **ER diagram** (image + Mermaid code).
9. **Normal form.** Show that each table is in 3NF/BCNF (list its functional dependencies). Point out any column that is *derived or redundant* (hint: ratings vs `driver_rating`; fare vs city rates) and say whether keeping it is justified.

### 2.2 Rules for your schema
- Create every table in a schema named **`uber`**: `CREATE SCHEMA uber;` and `SET search_path TO uber;`
- In this phase create **only constraints**: PK, FK, UNIQUE, NOT NULL, CHECK. **Do not create any other index yet.** (PostgreSQL automatically indexes PRIMARY KEY and UNIQUE columns; that's allowed. Note which indexes exist.) Your baseline in Phase 3 must reflect a database *without* tuning.
- Your constraints must accept **all** rows of the seed data. If a load fails, either your constraint is wrong or you found a data problem. Explain which in your design doc.

### 2.3 Load the data
Write `sql/02_load_data.sql` using `\copy`, loading tables in the right order (parents before children):

```sql
SET search_path TO uber;
\copy cities FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true)
-- ... the other 7 tables, in an order that satisfies your foreign keys
ANALYZE;
```

Then verify the row counts match the table above, and run at least **3 integrity checks** of your own (e.g. "every completed trip has exactly one payment", "no trip has a vehicle that belongs to a different driver"). Paste the results into `docs/02_schema_design.md`.

### Phase 2 deliverables
- `sql/01_schema.sql`: runs top-to-bottom on an empty database without errors
- `sql/02_load_data.sql`: loads all 8 files without errors
- `docs/02_schema_design.md`: data dictionary (table · column · type · constraint · *why*), ER diagram, FDs and normal form per table, integrity-check results, and every data problem you found

---

## Phase 3: Run the 30 queries and record the time

The file **`queries/workload_30.sql`** contains **30 queries**: 25 reads (`R01`–`R25`) and 5 writes (`W01`–`W05`). They're also listed in the [Appendix](#appendix-the-30-queries). **Do not modify them.** If a query fails, your schema doesn't match the seed data; fix the schema, not the query.

### 3.1 How to measure (everyone must use the same method)
- Run each query with `EXPLAIN (ANALYZE, BUFFERS)` and read the **`Execution Time`** at the bottom.
- Run each query **3 times** and record the **average** of the three `Execution Time` values. Keep all three runs in the raw plan file.
- Write queries (`W01`–`W05`) must be measured inside `BEGIN; … ROLLBACK;` so the data does not change.
- Close other heavy applications while measuring, and use the **same laptop** for Phase 3 and Phase 4.

The helper script does all of this for you:
```bash
./benchmarks/run_benchmark.sh <your_database> baseline
# → benchmarks/results/baseline/summary.csv   (avg, median, min, max, scan types)
# → benchmarks/results/baseline/R01.txt …     (full plans of all 3 runs)
```
> ⚠️ One of the 30 queries takes **many seconds** on the seed data. That's intentional. Let it finish, and don't skip it.

### 3.2 Deliverable: the timing table
In `docs/03_baseline_timings.md`, fill this table for **all 30** queries:

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Rider's last 20 trips | READ | | | | |
| R02: Driver's March 2026 earnings | READ | | | | |
| R03: Login by email (case-insensitive) | READ | | | | |
| R04: Bengaluru trips on 10 May 2026 | READ | | | | |
| R05: Oldest in-progress trips (dispatch) | READ | | | | |
| R06: Completed trips per city, June 2026 | READ | | | | |
| R07: Top 10 earning drivers in Mumbai, Q1 2026 | READ | | | | |
| R08: Revenue per payment method per month, 2026 | READ | | | | |
| R09: Bengaluru riders inactive since April 2026 | READ | | | | |
| R10: Active drivers with no trip since 25 June 2026 | READ | | | | |
| R11: 20 lowest-rated drivers | READ | | | | |
| R12: Average surge by hour in Delhi | READ | | | | |
| R13: Search riders by surname | READ | | | | |
| R14: Vehicle + driver by registration number | READ | | | | |
| R15: Trip receipt | READ | | | | |
| R16: Admin panel page 8,001 | READ | | | | |
| R17: Cancellation rate per city | READ | | | | |
| R18: Last trip date of every Pune rider | READ | | | | |
| R19: Top 3 drivers per city, May 2026 | READ | | | | |
| R20: Daily revenue + running total, May 2026 | READ | | | | |
| R21: Promo code usage | READ | | | | |
| R22: Failed payments, last 7 days | READ | | | | |
| R23: Distinct active riders per city per month | READ | | | | |
| R24: Unusually long trips | READ | | | | |
| R25: Trips charging more than ₹100/km | READ | | | | |
| W01: Request a new trip | WRITE | | | | |
| W02: Complete the oldest ongoing trip | WRITE | | | | |
| W03: Suspend low-rated drivers | WRITE | | | | |
| W04: Bulk import of 5,000 trips | WRITE | | | | |
| W05: Purge cancelled trips from Jan 2025 | WRITE | | | | |
| **Total (sum of all 30)** | | | | | |

Below the table, add for each query the **scan type** from the plan (Seq Scan, Index Scan, …) and one line on **why** it is slow or fast.

---

## Phase 4: Optimize the queries

Make the queries faster. **The results must stay the same** (same rows; order matters only where the query has an `ORDER BY`).

### 4.1 Techniques you may use
| Technique | Example |
|-----------|---------|
| B-tree index (single / composite) | the right column **order** matters: equality columns first, then range/sort |
| Partial index | index only the rows a query needs (e.g. a rare status) |
| Covering index | `INCLUDE (...)` so the table is never visited (Index Only Scan) |
| Expression index | index the exact expression used in `WHERE` |
| GIN trigram index | for `ILIKE '%text%'` (extension `pg_trgm`) |
| BRIN index | for huge tables stored in time order |
| Query rewrite | sargable date ranges instead of functions on columns; `NOT EXISTS` instead of `NOT IN`; joins instead of correlated subqueries; keyset instead of `OFFSET` pagination |
| VACUUM / ANALYZE | fresh statistics and visibility maps |
| Summary table / materialized view | for heavy reports that don't need live data (state how it's refreshed) |

**Not allowed:** changing the data, deleting rows, changing PostgreSQL server settings to hide the problem (e.g. huge `work_mem`, `enable_seqscan = off`), or caching results outside the database.

### 4.2 How to work
1. Put every index in `sql/05_indexes.sql`, each with a comment: **which queries it serves and why this type and column order**.
2. Put rewritten queries in `sql/06_optimized_queries.sql`. Copy `queries/workload_30.sql` and change **only** the queries you rewrite, keeping the `-- @R01` markers.
3. **Prove the results are unchanged** for every rewritten query (compare row counts, plus a checksum or an `EXCEPT` query). Put the proof in your report.
4. Benchmark again with the same method:
```bash
./benchmarks/run_benchmark.sh <your_database> optimized 5 sql/06_optimized_queries.sql
```
> 🔎 **Read the results, not just the timings.** At least one of the 30 original queries returns a **wrong answer** because of a subtle SQL rule. Find it, explain it, and fix it. This is worth marks.

### 4.3 Deliverable: the optimization table
In `docs/04_optimization_report.md`:

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------------:|---------------------------|----------------------|-----------:|------------:|:------------:|
| R01 | | e.g. Seq Scan on 300k trips | e.g. composite index `(rider_id, requested_at DESC)` | | e.g. 99.3% (145×) | ✅ |
| … all 30 … | | | | | | |
| **Total** | | | | | | |

Improvement % = (before − after) / before × 100

Also include:
- **Before/after `EXPLAIN` plans** for your 5 biggest improvements
- **Write overhead:** which of W01–W05 got **slower** because of your indexes, by how much, and whether that's acceptable
- **Index storage:** the size of each index you created (`pg_relation_size`) compared with its table
- **Queries you could not speed up**, and why (an honest "this query must read most of the table" earns marks)
- The **wrong-result query**: what was wrong, why, and your fix

---

## Phase 5: Scalability report (large dataset round)

Your optimizations worked on 300,000 trips. Next year Uber expects **20× the volume**.

By **Thu 19 Nov 2026**, faculty will release **`large_data.zip`**: the same 8 CSV files with about **20× the rows** (≈ 6,000,000 trips, 600,000 riders, 60,000 drivers). Until then, work on the design part of the report.

### 5.1 What to do with the large dataset
1. Create a new database. Run **your** `01_schema.sql`, load `large_data/` with your load script (change the folder name only), then run **your** `05_indexes.sql` and `ANALYZE`.
2. Run your **optimized** queries (`sql/06_optimized_queries.sql`). **Do not run the original 30 on the large data.** Some of them would run for hours.
   - R16 uses a fixed `trip_id` for the page; recompute it for the large data and explain how.
3. Record the times and compare with your Phase 4 results on the seed data.

| Query | Optimized on seed (ms) | Optimized on large (ms) | Growth (large ÷ seed) | Meets target? | If not, what you changed |
|-------|------------------------:|------------------------:|----------------------:|:-------------:|--------------------------|
| R01 | | | | | |
| … all 30 … | | | | | |

### 5.2 Performance targets on the large dataset
| Query group | Queries | Target (average of 3 runs) |
|-------------|---------|----------------:|
| Real-time / customer-facing | R01, R02, R03, R04, R05, R14, R15, R16, W01, W02 | **under 5 ms** |
| Interactive search and ops | R13, R22, R24, R25, W03 | **under 250 ms** |
| Reports and analytics | all remaining read queries | **under 5,000 ms** |
| Batch writes | W04, W05 | **under 1,000 ms** |

If a query misses its target, **find out why from the plan and fix it.** A query that was fast on the seed data can become slow on large data for reasons that only appear at scale. Show the before/after plans for every fix.

### 5.3 Deliverable: `docs/05_scalability_report.md`
1. **Results table** (above), with every target met or explained.
2. **Growth analysis.** Group your queries by how their time grew when the data grew 20×:
   - *stayed about the same* (why? e.g. index lookups grow with log n)
   - *grew about 20×* (why? e.g. they read a fixed *share* of the table)
   - *grew more than 20×* (why, and what you did about it)
3. **What broke at scale** and how you fixed it (plans before/after).
4. **Storage:** total database size, table vs index size, on seed and large data.
5. **Architecture for 100× (≈ 30 million trips/year):** explain with numbers from your own measurements:
   - **Partitioning:** which table, by which column (RANGE / LIST / HASH), and why. Write the DDL for `trips`, show partition pruning with `EXPLAIN`, and note the primary-key rule for partitioned tables.
   - **Sharding:** your shard key (e.g. city?), which queries become cross-shard, and how you would handle them.
   - **Read replicas and caching:** which of the 30 queries you would send to a replica or cache, and which must hit the primary.
   - **Maintenance:** VACUUM/autovacuum settings for `trips`, archiving old trips, refreshing summary tables.
6. **Conclusion:** is your database ready for next year? What are the remaining risks?

---

## Repository structure (submit exactly this)

```
uber-dbms-<team-no>/
├── README.md                          # team table, how to run, headline numbers
├── team.json                          # group lead, members, enrollment numbers
├── docs/
│   ├── 01_problem_understanding.md
│   ├── 02_schema_design.md
│   ├── 03_baseline_timings.md
│   ├── 04_optimization_report.md
│   └── 05_scalability_report.md
├── diagrams/
│   └── er_diagram.png
├── sql/
│   ├── 01_schema.sql
│   ├── 02_load_data.sql
│   ├── 05_indexes.sql
│   ├── 06_optimized_queries.sql
│   └── 08_partitioning.sql
├── queries/
│   └── workload_30.sql                # given; do not edit
└── benchmarks/
    ├── run_benchmark.sh               # given
    └── results/
        ├── baseline/                  # Phase 3: summary.csv + raw plans
        ├── optimized/                 # Phase 4
        └── large/                     # Phase 5
```

`team.json`:
```json
{
  "team_number": "",
  "group_lead": { "name": "", "enrollment_no": "", "github": "" },
  "members": [
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" },
    { "name": "", "enrollment_no": "", "github": "" }
  ],
  "postgres_version": "",
  "laptop_used_for_benchmarks": ""
}
```

**Do not commit the CSV files** (`seed_data/`, `large_data/`); add them to `.gitignore`. They are too large and we already have them.

---

## Timeline

| Due | Work | Checkpoint |
|-----|------|------------|
| Tue 3 Nov 2026 | Clone this repo into your team's DE repo, add members, commit `team.json` | **CP0** Setup |
| Mon 16 Nov 2026 | Phase 1 + Phase 2 (schema, load, ER, data dictionary) | **CP1** Schema loads all seed data with no errors |
| Tue 17 Nov 2026 | Phase 3 (baseline, 3 runs, average) + start Phase 4 | **CP2** Baseline table for all 30 queries committed |
| Thu 19 Nov 2026 | Phase 4 (indexes, rewrites, wrong-result query) | **CP3** Optimization table committed |
| Mon 23 Nov 2026 | Phase 5 on the large dataset + final report | **CP4 Final submission:** last commit on the default branch |
| Wed 25 – Thu 26 Nov 2026 | Individual analysis, in class time | **CP5** Individual analysis |

Full list of files per checkpoint, including the AP repo: [`CHECKPOINTS.md`](CHECKPOINTS.md).

---

## Evaluation (40 marks)

These 40 marks are the DE part of the project: **Query Execution (10)** and **Code Optimization (30)**.
The AP project (20) and your Individual analysis (40) make up the rest of the 100.

| Phase | Criteria | Marks |
|-------|----------|------:|
| | **Query Execution** | **10** |
| 1 | Problems understood, stakeholders and query groups correctly identified | 2 |
| 2 | Correct data types (1), keys and foreign keys with justified delete rules (1), ≥12 meaningful CHECK / NOT NULL / UNIQUE constraints (1), ER diagram + normal-form analysis (1), data loads cleanly + integrity checks (1) | 5 |
| 3 | All 30 queries measured with the required method: 3 runs, average (1), raw plans committed (1), scan type and reason for each query (1) | 3 |
| | **Code Optimization** | **30** |
| 4 | Speed-up achieved with appropriate techniques (6), every index justified (3), results proven unchanged (2), wrong-result query found and explained (2), write overhead and index storage reported (3) | 16 |
| 5 | Large-dataset results with all targets met or explained (4), growth analysis (3), scale-only problems found and fixed (3), partitioning DDL + sharding/replica design backed by your numbers (4) | 14 |
| | **Total** | **40** |

**Integrity rules**
- Every number in your reports must match the raw plan files in `benchmarks/results/`. Copied or invented timings make the whole phase score 0.
- Every member must have commits; the commit history is checked.
- You may use AI tools to learn, but you must be able to explain every index and rewrite in your individual analysis.

---

## Appendix: the 30 queries

These are identical to `queries/workload_30.sql`. Use the file, not copy-paste from this page.

**R01: Rider app: "Your trips": the last 20 trips of one rider**
```sql
SELECT *
FROM trips
WHERE rider_id = 1042
ORDER BY requested_at DESC
LIMIT 20;
```

**R02: Driver app: completed trips and earnings for March 2026**
```sql
SELECT driver_id, count(*) AS trips, sum(fare_amount) AS earnings
FROM trips
WHERE driver_id = 217
  AND status = 'COMPLETED'
  AND DATE(requested_at) BETWEEN '2026-03-01' AND '2026-03-31'
GROUP BY driver_id;
```

**R03: Login: find a rider by email, case-insensitive**
```sql
SELECT rider_id, full_name, home_city_id
FROM riders
WHERE LOWER(email) = 'karan.verma1042@mail.com';
```

**R04: City operations: every trip requested in Bengaluru on 10 May 2026**
```sql
SELECT t.trip_id, t.status, t.requested_at, t.fare_amount
FROM trips t
JOIN cities c ON c.city_id = t.city_id
WHERE c.city_name = 'Bengaluru'
  AND t.requested_at >= '2026-05-10' AND t.requested_at < '2026-05-11'
ORDER BY t.requested_at;
```

**R05: Live dispatch screen: oldest trips that are still in progress**
```sql
SELECT trip_id, city_id, status, requested_at
FROM trips
WHERE status IN ('REQUESTED', 'ACCEPTED', 'ONGOING')
ORDER BY requested_at
LIMIT 50;
```

**R06: Completed trips per city in June 2026**
```sql
SELECT c.city_name, count(*) AS completed_trips
FROM trips t
JOIN cities c ON c.city_id = t.city_id
WHERE t.status = 'COMPLETED'
  AND t.requested_at >= '2026-06-01' AND t.requested_at < '2026-07-01'
GROUP BY c.city_name
ORDER BY completed_trips DESC;
```

**R07: Top 10 earning drivers in Mumbai, Q1 2026**
```sql
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
```

**R08: Finance: successful revenue per payment method per month, 2026**
```sql
SELECT date_trunc('month', paid_at) AS month, method, count(*) AS payments, sum(amount) AS revenue
FROM payments
WHERE payment_status = 'SUCCESS'
  AND EXTRACT(YEAR FROM paid_at) = 2026
GROUP BY 1, 2
ORDER BY 1, 2;
```

**R09: Marketing: Bengaluru riders with no trip since 1 April 2026 (win-back campaign)**
```sql
SELECT r.rider_id, r.full_name, r.email
FROM riders r
WHERE r.home_city_id = 1
  AND r.rider_id NOT IN (SELECT t.rider_id FROM trips t WHERE t.requested_at >= '2026-04-01');
```

**R10: Driver ops: active drivers with no trip at all since 25 June 2026**
```sql
SELECT d.driver_id, d.full_name, d.city_id
FROM drivers d
WHERE d.status = 'ACTIVE'
  AND d.driver_id NOT IN (SELECT t.driver_id FROM trips t WHERE t.requested_at >= '2026-06-25');
```

**R11: Quality: 20 lowest-rated drivers (riders' ratings, at least 20 ratings)**
```sql
SELECT t.driver_id, round(avg(r.stars), 2) AS avg_stars, count(*) AS ratings
FROM ratings r
JOIN trips t ON t.trip_id = r.trip_id
WHERE r.rated_by = 'RIDER'
GROUP BY t.driver_id
HAVING count(*) >= 20
ORDER BY avg_stars ASC
LIMIT 20;
```

**R12: Pricing: average surge by hour of day in Delhi**
```sql
SELECT EXTRACT(HOUR FROM t.requested_at) AS hour_of_day,
       round(avg(t.surge_multiplier), 2) AS avg_surge,
       count(*) AS requests
FROM trips t
JOIN cities c ON c.city_id = t.city_id
WHERE c.city_name = 'Delhi'
GROUP BY 1
ORDER BY 1;
```

**R13: Support: search riders by surname**
```sql
SELECT rider_id, full_name, phone
FROM riders
WHERE full_name ILIKE '%sharma%'
ORDER BY full_name
LIMIT 50;
```

**R14: Traffic police request: vehicle and driver by registration number**
```sql
SELECT v.vehicle_id, v.registration_no, v.make, v.model, d.driver_id, d.full_name, d.phone
FROM vehicles v
JOIN drivers d ON d.driver_id = v.driver_id
WHERE v.registration_no = 'KA01AA1500';
```

**R15: Trip receipt: one trip with rider, driver, vehicle and payment**
```sql
SELECT t.trip_id, t.requested_at, t.dropoff_at, t.distance_km, t.fare_amount,
       r.full_name AS rider, d.full_name AS driver, v.registration_no,
       p.method, p.payment_status
FROM trips t
JOIN riders r   ON r.rider_id   = t.rider_id
JOIN drivers d  ON d.driver_id  = t.driver_id
JOIN vehicles v ON v.vehicle_id = t.vehicle_id
LEFT JOIN payments p ON p.trip_id = t.trip_id
WHERE t.trip_id = 123458;
```

**R16: Admin panel: "All trips" table, page 8,001 (25 rows per page)**
```sql
SELECT trip_id, rider_id, driver_id, city_id, status, fare_amount, requested_at
FROM trips
ORDER BY trip_id DESC
OFFSET 200000
LIMIT 25;
```

**R17: Cancellation rate per city**
```sql
SELECT c.city_name,
       count(*) AS requests,
       count(*) FILTER (WHERE t.status LIKE 'CANCELLED%') AS cancelled,
       round(100.0 * count(*) FILTER (WHERE t.status LIKE 'CANCELLED%') / count(*), 2) AS cancel_pct
FROM trips t
JOIN cities c ON c.city_id = t.city_id
GROUP BY c.city_name
ORDER BY cancel_pct DESC;
```

**R18: CRM: last trip date of every rider in Pune**
```sql
SELECT r.rider_id, r.full_name,
       (SELECT max(t.requested_at) FROM trips t WHERE t.rider_id = r.rider_id) AS last_trip_at
FROM riders r
WHERE r.home_city_id = 6
ORDER BY last_trip_at DESC NULLS LAST;
```

**R19: Leaderboard: rank drivers inside each city by completed trips in May 2026**
```sql
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
```

**R20: Finance: daily revenue and running total for May 2026**
```sql
SELECT day, revenue, sum(revenue) OVER (ORDER BY day) AS running_total
FROM (
    SELECT requested_at::date AS day, sum(fare_amount) AS revenue
    FROM trips
    WHERE status = 'COMPLETED'
      AND requested_at::date >= '2026-05-01' AND requested_at::date <= '2026-05-31'
    GROUP BY 1
) daily
ORDER BY day;
```

**R21: Marketing: usage of each promo code**
```sql
SELECT p.promo_code, p.discount_pct, count(t.trip_id) AS trips_used
FROM promo_codes p
LEFT JOIN trips t ON t.promo_code = p.promo_code
GROUP BY p.promo_code, p.discount_pct
ORDER BY trips_used DESC;
```

**R22: Payments team: failed payments in the last 7 days with the rider's phone**
```sql
SELECT p.payment_id, p.amount, p.paid_at, r.rider_id, r.phone
FROM payments p
JOIN trips t  ON t.trip_id  = p.trip_id
JOIN riders r ON r.rider_id = t.rider_id
WHERE p.payment_status = 'FAILED'
  AND p.paid_at >= '2026-06-24'
ORDER BY p.paid_at DESC;
```

**R23: Growth: distinct active riders per city per month in 2026**
```sql
SELECT city_id, date_trunc('month', requested_at) AS month, count(DISTINCT rider_id) AS active_riders
FROM trips
WHERE requested_at >= '2026-01-01'
GROUP BY 1, 2
ORDER BY 1, 2;
```

**R24: Fraud check: unusually long trips**
```sql
SELECT trip_id, driver_id, distance_km, duration_min, fare_amount
FROM trips
WHERE status = 'COMPLETED'
  AND (distance_km > 43 OR duration_min > 150)
ORDER BY fare_amount DESC
LIMIT 100;
```

**R25: Fraud check: completed trips charging more than ₹100 per km**
```sql
SELECT trip_id, city_id, distance_km, fare_amount,
       round(fare_amount / NULLIF(distance_km, 0), 2) AS fare_per_km
FROM trips
WHERE status = 'COMPLETED'
  AND fare_amount / NULLIF(distance_km, 0) > 100
ORDER BY fare_per_km DESC
LIMIT 50;
```

**W01: Rider app: request a new trip**
```sql
INSERT INTO trips (trip_id, rider_id, city_id, requested_at, pickup_lat, pickup_lng,
                   drop_lat, drop_lng, surge_multiplier, status)
VALUES (90000001, 1042, 6, '2026-07-01 09:15:00+05:30', 18.520400, 73.856700,
        18.559000, 73.807700, 1.40, 'REQUESTED');
```

**W02: Driver app: finish the oldest ongoing trip**
```sql
UPDATE trips
SET status       = 'COMPLETED',
    dropoff_at   = pickup_at + interval '27 minutes',
    distance_km  = 9.80,
    duration_min = 27,
    fare_amount  = 245.50
WHERE trip_id = (SELECT min(trip_id) FROM trips WHERE status = 'ONGOING');
```

**W03: Safety team: suspend active drivers rated below 3.5**
```sql
UPDATE drivers
SET status = 'SUSPENDED'
WHERE status = 'ACTIVE' AND driver_rating < 3.5;
```

**W04: Partner import: 5,000 corporate trip requests in one batch**
```sql
INSERT INTO trips (trip_id, rider_id, city_id, requested_at, pickup_lat, pickup_lng,
                   drop_lat, drop_lng, surge_multiplier, status)
SELECT 90001000 + g, 1 + (g * 7) % 30000, 1,
       TIMESTAMPTZ '2026-07-01 10:00:00+05:30' + g * interval '2 seconds',
       12.971600, 77.594600, 12.935200, 77.624500, 1.00, 'REQUESTED'
FROM generate_series(1, 5000) AS g;
```

**W05: Data retention: purge cancelled trips from January 2025**
```sql
DELETE FROM trips
WHERE status LIKE 'CANCELLED%'
  AND requested_at < '2025-02-01';
```
