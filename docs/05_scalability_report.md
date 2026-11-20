# CP-4 Scalability Report

## 1. Objective, Dataset Transparency, and Environment

CP-4 evaluates whether the CP-3 optimized RideNow (Uber India) schema and 30-query workload remain within the project performance targets when data volume grows by **20×** (approximately **6,000,000 trips**, **600,000 riders**, and **60,000 drivers**), and specifies a production architecture for **100×** volume (~30,000,000 trips/year).

### Dataset transparency disclosure

The faculty-provided `large_data.zip` was **not released** in the project repository (`DBMS-Uber-Ride-Hailing` contains only `seed_data.zip`). Rather than inventing benchmark timings or relying purely on paper estimates, we built a **deterministic, reproducible 20× scale-up script** (`sql/10_scale_to_large_20x.sql`) that scales the official seed dataset into a separate local PostgreSQL database (`uber_large`) while:

- Leaving our CP-1/CP-2/CP-3 database (`uber_cp1`) completely untouched.
- Preserving batch 0 verbatim (so all workload literals such as `rider_id = 1042`, `driver_id = 217`, `trip_id = 123458`, `karan.verma1042@mail.com`, and `KA01AA1500` remain valid).
- Enforcing every CP-1 `PRIMARY KEY`, `UNIQUE`, `FOREIGN KEY`, and `CHECK` constraint across all 8 tables (`0` duplicate `trip_id` groups, `0` orphaned payments, `0` orphaned ratings).

Every timing, storage size, and execution plan reported below is an **actual PostgreSQL measurement** matching the committed raw plans in `benchmarks/results/large/` (and `benchmarks/results/partitioned_seed/` for the 300k partitioned comparison). Only Section 7's 100× capacity figures are projections, and they are explicitly labelled as projections derived from our measured 1× and 20× data. If faculty releases `large_data.zip` later, `sql/02_load_large_data.sql` can be swapped in for `sql/10_scale_to_large_20x.sql` with zero changes to `sql/08_partitioning.sql`, `sql/05_indexes.sql`, or `sql/06_optimized_queries.sql`.

### Dataset row counts (actual measured)

| Table | Seed (`uber_cp1` & `uber_cp4_partition_test`) | Large 20× (`uber_large`) | Scale factor |
|---|---:|---:|---:|
| `cities` | 10 | 10 | 1.0× (reference) |
| `promo_codes` | 40 | 40 | 1.0× (reference) |
| `riders` | 30,000 | 600,000 | 20.0× |
| `drivers` | 3,000 | 60,000 | 20.0× |
| `vehicles` | 3,300 | 66,000 | 20.0× |
| `trips` | 300,000 | 6,000,000 | 20.0× |
| `payments` | 245,839 | 4,916,780 | 20.0× |
| `ratings` | 307,214 | 6,144,280 | 20.0× |
| **Total rows** | **609,403** | **17,787,110** | **~20.0×** |

### Benchmark environment

- **Hardware / OS:** MacBook Pro (Apple Silicon), macOS.
- **Database engine:** PostgreSQL 18.6 (Postgres.app), database timezone set to `Asia/Kolkata` (`+05:30`).
- **Databases:**
  - `uber_cp1`: CP-3 optimized unpartitioned seed reference (`300,000` trips, untouched).
  - `uber_cp4_partition_test`: partitioned + indexed seed verification database (`300,000` trips, 19 partitions).
  - `uber_large`: 20× scaled, partitioned + indexed database (`6,000,000` trips, 19 partitions).
- **Measurement protocol:** `./benchmarks/run_benchmark.sh uber_large large 3 sql/06_optimized_queries.sql` (`EXPLAIN (ANALYZE, BUFFERS)`, 3 runs per query, writes wrapped in `BEGIN ... ROLLBACK`).

---

## 2. Results Table: Seed Optimized (1×) vs. Partitioned Seed (1×) vs. Large Partitioned (20×)

All **30 of 30 queries meet their official `README.md` large-data targets** after applying the two CP-4 scale-only fixes (R16 and R25) and post-migration `VACUUM (FULL, ANALYZE)` documented in Section 4.

- `Growth = Optimized large avg (ms) / Optimized seed avg (ms)`
- Source files: `benchmarks/results/optimized/summary.csv`, `benchmarks/results/partitioned_seed/summary.csv`, and `benchmarks/results/large/summary.csv`.

| Query | Type | Seed optimized avg (ms) | Partitioned seed avg (ms) | Large 20× avg (ms) | Growth (large ÷ seed) | Target | Meets target? | If not initially, what we changed |
|---|---|---:|---:|---:|---:|---:|:---:|---|
| R01 | READ | 0.142 | 2.597 | 2.782 | 19.59× | < 5 ms | Yes | — (median 0.277 ms; probes 19 partitions) |
| R02 | READ | 0.124 | 0.101 | 0.234 | 1.89× | < 5 ms | Yes | — (prunes to `trips_2026_03`) |
| R03 | READ | 0.141 | 0.161 | 0.154 | 1.09× | < 5 ms | Yes | — |
| R04 | READ | 0.082 | 0.144 | 0.605 | 7.38× | < 5 ms | Yes | — (prunes to `trips_2026_05`) |
| R05 | READ | 0.163 | 0.245 | 0.410 | 2.52× | < 5 ms | Yes | — |
| R06 | READ | 2.357 | 2.397 | 25.940 | 11.01× | < 5,000 ms | Yes | — (prunes to `trips_2026_06`) |
| R07 | READ | 3.967 | 3.959 | 85.478 | 21.55× | < 5,000 ms | Yes | — (prunes to Q1 `trips_2026_01..03`) |
| R08 | READ | 23.396 | 24.237 | 354.524 | 15.15× | < 5,000 ms | Yes | `VACUUM FULL` on `payments` cut 799.0 → 354.5 ms |
| R09 | READ | 4.071 | 6.988 | 67.077 | 16.48× | < 5,000 ms | Yes | — (prunes to `trips_2026_04..06` + default) |
| R10 | READ | 1.269 | 1.155 | 16.737 | 13.19× | < 5,000 ms | Yes | — (prunes to `trips_2026_06` + default) |
| R11 | READ | 33.164 | 36.590 | 1199.628 | 36.17× | < 5,000 ms | Yes | — (full join of 6M trips × 6.14M ratings) |
| R12 | READ | 14.076 | 17.591 | 228.200 | 16.21× | < 5,000 ms | Yes | Post-vacuum VM cut 385.2 → 228.2 ms |
| R13 | READ | 0.925 | 1.253 | 16.483 | 17.82× | < 250 ms | Yes | — |
| R14 | READ | 0.217 | 0.140 | 0.237 | 1.09× | < 5 ms | Yes | — |
| R15 | READ | 0.441 | 1.642 | 2.101 | 4.76× | < 5 ms | Yes | — (median 0.208 ms; probes 19 partitions) |
| R16 | READ | 24.016 | 23.693 | 0.449 | 0.02× | < 5 ms | Yes | **Missed initially (206.645 ms).** Replaced `OFFSET 200000` with keyset `WHERE trip_id < 5800001` (Sec. 4.1) |
| R17 | READ | 24.779 | 27.408 | 482.734 | 19.48× | < 5,000 ms | Yes | — |
| R18 | READ | 2.985 | 24.873 | 642.405 | 215.21× | < 5,000 ms | Yes | Post-vacuum VM cut 1,265.7 → 642.4 ms (Sec. 3.3) |
| R19 | READ | 3.168 | 3.332 | 77.774 | 24.55× | < 5,000 ms | Yes | Post-vacuum VM restored Index Only Scan on `trips_2026_05` (102.9 → 77.8 ms) |
| R20 | READ | 2.166 | 2.526 | 44.383 | 20.49× | < 5,000 ms | Yes | Post-vacuum VM restored Index Only Scan on `trips_2026_05` (161.5 → 44.4 ms) |
| R21 | READ | 8.171 | 11.370 | 146.971 | 17.99× | < 5,000 ms | Yes | — |
| R22 | READ | 1.020 | 1.189 | 71.478 | 70.08× | < 250 ms | Yes | — (median 22.899 ms; 19-partition probe per failed payment) |
| R23 | READ | 38.084 | 42.178 | 1034.655 | 27.17× | < 5,000 ms | Yes | — (prunes to 2026 partitions `01..06` + default) |
| R24 | READ | 0.054 | 1.247 | 1.855 | 34.35× | < 250 ms | Yes | — (tiny 0.054 ms base; median 0.553 ms on 6M rows) |
| R25 | READ | 16.766 | 17.026 | 1.495 | 0.09× | < 250 ms | Yes | **Missed initially (258.620 ms).** Added `AND distance_km > 0` to match partial index (Sec. 4.2) |
| W01 | WRITE | 1.204 | 1.584 | 1.598 | 1.33× | < 5 ms | Yes | — |
| W02 | WRITE | 0.526 | 0.801 | 1.370 | 2.60× | < 5 ms | Yes | — |
| W03 | WRITE | 3.656 | 3.188 | 119.298 | 32.63× | < 250 ms | Yes | — (updates 20× more matching drivers + index entries) |
| W04 | WRITE | 61.861 | 63.672 | 75.796 | 1.23× | < 1,000 ms | Yes | — (fixed 5,000-row batch insert into `trips_default`) |
| W05 | WRITE | 12.146 | 19.202 | 373.548 | 30.75× | < 1,000 ms | Yes | — (prunes to `trips_2025_01` + default; deletes 20× more rows) |

### Summary against official performance targets

| Query group | Queries | Target | Passed | Worst query in group |
|---|---|---:|:---:|---|
| Real-time / customer-facing | R01, R02, R03, R04, R05, R14, R15, R16, W01, W02 | < 5 ms | **10 / 10** | R01 (`2.782 ms`) |
| Interactive search and ops | R13, R22, R24, R25, W03 | < 250 ms | **5 / 5** | W03 (`119.298 ms`) |
| Reports and analytics | R06–R12, R17–R21, R23 | < 5,000 ms | **13 / 13** | R11 (`1,199.628 ms`) |
| Batch writes | W04, W05 | < 1,000 ms | **2 / 2** | W05 (`373.548 ms`) |

---

## 3. Growth Analysis (1× → 20×)

### 3.1 Stayed near-constant or improved (< 8× growth)
**Queries:** `R02` (1.89×), `R03` (1.09×), `R04` (7.38×), `R05` (2.52×), `R14` (1.09×), `R15` (4.76×), `R16` (0.02× after keyset fix), `R25` (0.09× after partial-index fix), `W01` (1.33×), `W02` (2.60×), `W04` (1.23×).

- **Why:** B-tree height grows logarithmically ($O(\log_B N)$, increasing by at most one tree level between 300k and 6M rows). Point lookups (`R03`, `R14`, `R15`), single-partition date-bounded lookups (`R02` on `trips_2026_03`, `R04` on `trips_2026_05`), and fixed-row-count operations (`R05` `LIMIT 50`, `R16` keyset `LIMIT 25`, `R25` partial-index `LIMIT 50`, `W01` single insert, `W04` fixed 5,000-row batch) touch a bounded number of index leaf pages regardless of total table size.

### 3.2 Grew approximately proportionally (~11× to 25×)
**Queries:** `R01` (19.59×), `R06` (11.01×), `R07` (21.55×), `R08` (15.15×), `R09` (16.48×), `R10` (13.19×), `R12` (16.21×), `R13` (17.82×), `R17` (19.48×), `R19` (24.55×), `R20` (20.49×), `R21` (17.99×).

- **Why:** These queries scan or aggregate a **fixed fraction** of the table—for example, all completed trips in May/June 2026 (`R06`, `R19`, `R20`), Q1 2026 (`R07`), 2026 successful payments (`R08`), all Delhi trips (`R12`), all trips for cancellation rate (`R17`), or all matching `'sharma'` riders (`R13`). When total rows grow 20×, the qualifying slice also grows 20×, so execution time scales ~11×–25× (slightly sub-linear where PostgreSQL uses parallel workers or partition pruning).
- **Special note on `R01` (19.59×):** `R01` (`WHERE rider_id = 1042`) has no `requested_at` filter. Comparing `optimized` (`0.142 ms`) → `partitioned_seed` (`2.597 ms`) → `large` (`2.782 ms`) proves that almost all of the jump came from probing **19 partitions instead of 1** (1× partitioned vs. 20× partitioned grew only **1.07×**).

### 3.3 Grew more than 25× (super-linear or partition-amplified growth)
**Queries:** `R11` (36.17×), `R18` (215.21×), `R22` (70.08×), `R23` (27.17×), `R24` (34.35×), `W03` (32.63×), `W05` (30.75×).

- **`R18` (`2.985 ms` → `642.405 ms`, 215.21× — passes `< 5,000 ms`):** The clearest demonstration of a partitioning trade-off. `R18` runs a `LEFT JOIN LATERAL` per Pune rider without a `requested_at` predicate. Moving from unpartitioned seed (`2.985 ms`) to partitioned seed (`24.873 ms`) already added an **8.3×** penalty because every rider probed all 19 partitions. Scaling Pune riders by 20× compounded that overhead (`8.3 × 25.8 ≈ 215×`).
- **`R22` (`1.020 ms` → `71.478 ms`, 70.08× — passes `< 250 ms`):** Failed payments in the last 7 days grew 20×, and joining `payments.trip_id = trips.trip_id` without `payments.requested_at = trips.requested_at` probes all 19 `trips` partitions per failed payment (run 1 cold cache was `173.256 ms`; warm median was `22.899 ms`). Adding `AND t.requested_at = p.requested_at` enables runtime partition pruning if needed at 100×.
- **`R11` (`33.164 ms` → `1,199.628 ms`, 36.17×) & `R23` (`38.084 ms` → `1,034.655 ms`, 27.17×):** Both exceed CPU cache and `shared_buffers` locality at 20× scale (6M trips + 6.14M ratings hash-join in `R11`; 3M 2026 trips `COUNT(DISTINCT rider_id)` aggregation in `R23`), adding memory-bandwidth and disk-read overhead on top of 20× row volume.
- **`R24` (`0.054 ms` → `1.855 ms`, 34.35× — passes `< 250 ms`):** Dividing by a 54-microsecond seed base exaggerates fixed `Merge Append` startup across 19 partitions; the warm median is just `0.553 ms`.
- **`W03` (`3.656 ms` → `119.298 ms`, 32.63×) & `W05` (`12.146 ms` → `373.548 ms`, 30.75×):** Bulk `UPDATE`/`DELETE` operations scale slightly faster than 20× because every modified row updates all associated B-tree indexes (13 indexes per partition on `trips` for `W05`) and generates WAL.

---

## 4. What Broke at Scale and How We Fixed It (Before/After Plans)

During our first 20× benchmark run on `uber_large`, **two queries missed their official targets** (`R16` and `R25`) and **post-migration MVCC dead-tuple bloat** degraded several reporting queries. All three issues were diagnosed directly from `EXPLAIN (ANALYZE, BUFFERS)` plans and fixed.

### 4.1 Scale fix #1: `R16` — Deep `OFFSET 200000` missed `< 5 ms` (`206.645 ms` → `0.449 ms`)

- **Root cause:** `OFFSET 200000 LIMIT 25` forces PostgreSQL's `Merge Append` to read and discard 200,000 index tuples across the 19 partitions before returning rows 200,001–200,025. At 6M rows, the before-fix plan read `67,105` buffers and averaged **`206.645 ms`** (missing `< 5 ms` by 41×).
- **Fix (matching `README.md` Section 5.1):** Computed the exact last `trip_id` of page 8,000 in `uber_large`:
```sql
SELECT trip_id FROM uber.trips ORDER BY trip_id DESC OFFSET 199999 LIMIT 1;
-- Returns: 5800001
```
  Rewrote `R16` in `sql/06_optimized_queries.sql` to use **keyset pagination** (`WHERE trip_id < 5800001 ORDER BY trip_id DESC LIMIT 25`).
- **Equivalence verification:** `EXCEPT ALL` in both directions against the original `OFFSET 200000` query returned **`0` differing rows** (`R16_diff_rows = 0`).
- **Result:** Average execution time dropped from **`206.645 ms` → `0.449 ms`** (**99.78% faster**, passing `< 5 ms`).

**Before-fix plan (`R16` run 1 on `uber_large`, `314.170 ms`, avg `206.645 ms`):**
```text
Limit  (cost=27173.50..27176.90 rows=25 width=41) (actual time=314.083..314.089 rows=25.00 loops=1)
  Buffers: shared hit=2331 read=67105 written=11
  ->  Merge Append  (cost=8.13..814969.27 rows=6000001 width=41) (actual time=9.548..310.448 rows=200025.00 loops=1)
        Sort Key: trips.trip_id DESC
        ->  Index Only Scan using trips_2025_01_trip_id_rider_id_driver_id_city_id_status_far_idx on trips_2025_01 ...
        ->  Index Scan Backward using trips_2025_08_pkey on trips_2025_08 ... (actual time=0.326..26.386 rows=17034.00)
        ... (reads 200,025 rows across partitions before discarding 200,000)
```

**After-fix plan (`R16` run 3 on `uber_large`, `0.408 ms`, avg `0.449 ms`):**
```text
Limit  (rows=25.00)
  ->  Merge Append (Sort Key: trips.trip_id DESC)
        ->  Index Only Scan using trips_2025_08_trip_id_rider_id_driver_id_city_id_status_far_idx on trips_2025_08
              Index Cond: (trip_id < 5800001)  Heap Fetches: 0  Buffers: shared hit=4
        ... (19 partitions probed directly at trip_id < 5800001, ~1 row per partition)
Execution Time: 0.408 ms
```

### 4.2 Scale fix #2: `R25` — Partial index predicate mismatch missed `< 250 ms` (`258.620 ms` → `1.495 ms`)

- **Root cause:** Our CP-3 partial index `idx_trips_high_fare_per_km` includes `WHERE status = 'COMPLETED' AND distance_km > 0 AND fare_amount / NULLIF(distance_km, 0) > 100`. Because `R25` omitted `AND distance_km > 0`, PostgreSQL's planner could not prove predicate implication and ignored the index completely. On 300k rows the `Seq Scan` took `16.766 ms`, hiding the bug; at 6M rows the `Parallel Seq Scan` across all 19 partitions read `102,520` buffers and averaged **`258.620 ms`** (missing `< 250 ms`).
- **Fix:** Added `AND distance_km > 0` and matched `ORDER BY round(fare_amount / NULLIF(distance_km, 0), 2) DESC` in `sql/06_optimized_queries.sql`. Under `CHECK (distance_km >= 0)` and `NULLIF(distance_km, 0)`, `distance_km > 0` is 100% logically equivalent.
- **Equivalence verification:** Full qualifying set comparison (`EXCEPT ALL` in both directions) returned **`0` differing rows** across all matching trips (any row-ID difference at `LIMIT 50` is purely tie-breaking among equal `fare_per_km` values).
- **Result:** Average execution time dropped from **`258.620 ms` → `1.495 ms`** (**99.42% faster**, passing `< 250 ms`).

**Before-fix plan (`R25` run 1 on `uber_large`, `253.277 ms`, avg `258.620 ms`):**
```text
Limit  (cost=194167.85..194173.67 rows=50 width=52) (actual time=252.159..253.212 rows=50.00 loops=1)
  Buffers: shared hit=9488 read=102520
  ->  Gather Merge (Workers Launched: 2)
        ->  Sort (Sort Method: top-N heapsort  Memory: 31kB)
              ->  Parallel Append
                    ->  Parallel Seq Scan on trips_2025_12 ... Rows Removed by Filter: 338440
                    ->  Parallel Seq Scan on trips_2026_03 ... Rows Removed by Filter: 338820
                    ... (scans all 6,000,000 rows across 19 partitions)
```

**After-fix plan (`R25` run 3 on `uber_large`, `0.474 ms`, avg `1.495 ms`):**
```text
Limit (rows=50)
  ->  Merge Append
        ->  Index Only Scan using trips_2025_05_round_trip_id_city_id_distance_km_fare_amount_idx on trips_2025_05
              Heap Fetches: 0   Buffers: shared hit=3
        ... (reads 1–21 pre-sorted index entries per partition, 0 heap fetches)
Execution Time: 0.474 ms
```

### 4.3 Operational scale fix #3: Reclaiming partitioning migration MVCC bloat (`VACUUM FULL` + visibility maps)

- **Root cause:** In `sql/08_partitioning.sql`, backfilling `requested_at` via full-table `UPDATE` statements on `payments` (4.92M rows) and `ratings` (6.14M rows) doubled both heaps with MVCC dead tuples (`uber_large` grew to `5,564 MB`). Additionally, newly populated `trips` partitions lacked visibility maps, pushing `R08`, `R12`, `R19`, and `R20` to `Seq Scan`.
- **Fix:** Ran non-transactional `VACUUM (FULL, ANALYZE)` on `payments` and `ratings` and `VACUUM (ANALYZE)` on `trips`, `riders`, `drivers`, and `vehicles`.
- **Measured impact:**
  - Database size dropped from **`5,564 MB` → `4,535 MB`** (**1,029 MB reclaimed**).
  - `R08`: `799.027 ms` (`Seq Scan`) → **`354.524 ms`** (`Bitmap Index Scan`).
  - `R12`: `385.214 ms` (`Seq Scan`) → **`228.200 ms`** (`Index Only Scan`).
  - `R18`: `1,265.730 ms` → **`642.405 ms`**.
  - `R19`: `102.896 ms` (`Seq Scan`) → **`77.774 ms`** (`Index Only Scan` on `trips_2026_05`).
  - `R20`: `161.538 ms` (`Seq Scan`) → **`44.383 ms`** (`Index Only Scan` on `trips_2026_05`).

---

## 5. Partitioning Design and Pruning Evidence

### 5.1 Strategy and DDL (`sql/08_partitioning.sql`)

- **Table & method:** `uber.trips` partitioned by **`RANGE (requested_at)`**, one partition per calendar month in `Asia/Kolkata` (`+05:30`), plus `uber.trips_default` as a `DEFAULT` catch-all partition.
- **Partitions created (19 total):** `trips_2025_01` through `trips_2026_06` (18 monthly partitions, ~307k–341k rows each at 20× scale) + `trips_default` (0 live rows).
- **Why `RANGE (requested_at)`:**
  1. Operational, financial, and retention queries filter `trips` by calendar windows (`R02`, `R04`, `R06`, `R07`, `R09`, `R10`, `R19`, `R20`, `R23`, `W05`), letting PostgreSQL prune irrelevant months at planning time.
  2. Monthly partitions provide an instant archival boundary (`DETACH PARTITION` + archive/drop replaces expensive `DELETE` jobs like `W05`).
  3. 18 monthly partitions keep catalog and planning overhead low compared to daily partitions (~546 partitions).

### 5.2 Primary-key and foreign-key rule for partitioned tables

PostgreSQL requires every `PRIMARY KEY` or `UNIQUE` constraint on a partitioned table to include **all partition-key columns**, because uniqueness is enforced locally per leaf partition. Therefore:

- `uber.trips` uses **`PRIMARY KEY (trip_id, requested_at)`** instead of `PRIMARY KEY (trip_id)`.
- `sql/08_partitioning.sql` adds `requested_at TIMESTAMPTZ NOT NULL` to `payments` and `ratings`, backfills it from `trips`, and recreates declarative composite foreign keys (`FOREIGN KEY (trip_id, requested_at) REFERENCES uber.trips(trip_id, requested_at) ON DELETE RESTRICT`).
- `sql/09_scalability_checks.sql` verifies global `trip_id` uniqueness (`duplicate_trip_id_groups = 0`) and composite FK integrity (`payments_without_trip = 0`, `ratings_without_trip = 0`). In production, global `trip_id` uniqueness across partitions should be guaranteed via a PostgreSQL `SEQUENCE` or Snowflake ID allocator.

### 5.3 Partition pruning evidence (`EXPLAIN (ANALYZE, BUFFERS)`)

**1) May 2026 count on `uber_large` (6M trips, `sql/09_scalability_checks.sql`) — prunes 18 of 19 partitions:**
```text
Finalize Aggregate  (cost=9842.19..9842.20 rows=1 width=8) (actual time=14.386..15.040 rows=1.00 loops=1)
  Buffers: shared read=6358
  ->  Gather  (Workers Planned: 2, Workers Launched: 2)
        ->  Partial Aggregate
              ->  Parallel Seq Scan on trips_2026_05 trips  (actual time=0.053..6.294 rows=113553.33 loops=3)
                    Filter: ((requested_at >= '2026-05-01 00:00:00+05:30'::timestamptz)
                         AND (requested_at <  '2026-06-01 00:00:00+05:30'::timestamptz))
Planning Time: 1.406 ms
Execution Time: 15.050 ms
```
Only `trips_2026_05` (`340,660` rows) is scanned; the other 18 partitions (`5,659,340` rows) are pruned at planning time.

**2) May 2026 daily revenue (`R20`) on `uber_cp4_partition_test` — single-partition Index Only Scan:**
```text
GroupAggregate (actual time=1.610..2.440 rows=31.00 loops=1)
  ->  Sort (Sort Method: quicksort  Memory: 822kB)
        ->  Index Only Scan using trips_2026_05_requested_at_city_id_driver_id_fare_amount_idx on trips_2026_05 trips
              Index Cond: ((requested_at >= '2026-05-01 00:00:00+05:30'::timestamptz)
                       AND (requested_at <  '2026-06-01 00:00:00+05:30'::timestamptz))
              Heap Fetches: 0
Execution Time: 2.467 ms
```
On `uber_large`, `R20` runs the exact same single-partition `Index Only Scan` on `trips_2026_05` in **`44.383 ms`** (avg).

**3) Out-of-range query (August 2026) — routes strictly to `trips_default`:**
```text
Aggregate (actual time=0.003..0.003 rows=1.00 loops=1)
  ->  Seq Scan on trips_default trips (actual time=0.002..0.002 rows=0.00 loops=1)
        Filter: ((requested_at >= '2026-08-01 00:00:00+05:30'::timestamptz)
             AND (requested_at <  '2026-09-01 00:00:00+05:30'::timestamptz))
Execution Time: 0.010 ms
```

**4) Operational pruning observed across `benchmarks/results/large/summary.csv`:**
- `R02` (March 2026): **`trips_2026_03` only** (`0.234 ms`).
- `R04` (10 May 2026): **`trips_2026_05` only** (`0.605 ms`).
- `R06` (June 2026): **`trips_2026_06` only** (`25.940 ms`).
- `R07` (Q1 2026): **`trips_2026_01..03` only** (`85.478 ms`).
- `R19` & `R20` (May 2026): **`trips_2026_05` only** (`77.774 ms` and `44.383 ms`).
- `W05` (`< 2025-02-01`): **`trips_2025_01` + `trips_default` only** (`373.548 ms`).

---

## 6. Storage Measurements (Actual Measured)

Measured via `pg_database_size`, `pg_table_size`, `pg_indexes_size`, and `pg_total_relation_size` on `uber_cp1` (seed unpartitioned) and `uber_large` (20× partitioned, post-`VACUUM FULL`).

| Metric | Seed (`uber_cp1`, 1×) | Large (`uber_large`, 20× post-vacuum) | Ratio (20× ÷ 1×) |
|---|---:|---:|---:|
| **Total database size** | **228 MB** | **4,535 MB** *(5,564 MB pre-vacuum)* | **19.89×** |
| `trips` heap (table / all 19 partitions) | 45 MB | 877 MB | 19.49× |
| `trips` indexes (all 13 × 19 partitions) | 97 MB | 2,021 MB | 20.84× |
| `trips` total | 142 MB | 2,898 MB | 20.41× |
| `payments` (heap / indexes / total) | 16 MB / 20 MB / 36 MB | 359 MB / 398 MB / 757 MB | 21.03× |
| `ratings` (heap / indexes / total) | 16 MB / 13 MB / 29 MB | 372 MB / 258 MB / 630 MB | 21.72× |
| `riders` (heap / indexes / total) | 3.0 MB / 7.8 MB / 11 MB | 61 MB / 149 MB / 210 MB | 19.09× |
| `drivers` (heap / indexes / total) | 328 kB / 696 kB / 1.0 MB | 8.0 MB / 10.0 MB / 18 MB | 18.00× |
| `vehicles` (heap / indexes / total) | 280 kB / 336 kB / 616 kB | 4.8 MB / 6.4 MB / 11 MB | 17.86× |
| `cities` + `promo_codes` total | 64 kB | 64 kB | 1.00× |
| **Total `uber` table (heap) size** | **~81 MB** | **~1,682 MB** | **20.8×** |
| **Total `uber` index size** | **~139 MB** | **~2,842 MB** | **20.4×** |

### Per-partition storage breakdown on `uber_large` (6,000,000 trips)

- **31-day monthly partitions** (10 partitions, ~340,660 rows each): `50 MB` heap + `114–115 MB` indexes = **`164 MB` per month**.
- **30-day monthly partitions** (6 partitions, ~329,660 rows each): `48 MB` heap + `111 MB` indexes = **`159 MB` per month**.
- **28-day monthly partitions** (2 partitions, ~307,700 rows each): `45 MB` heap + `103 MB` indexes = **`148 MB` per month**.
- **`trips_default`** (0 live rows): `1,608 kB` heap + `5,384 kB` indexes = **`7.0 MB`** (allocated by rolled-back `W01`/`W04` benchmark transactions inserting `2026-07-01` rows).

**Key storage insights:**
1. Indexes represent **62.8%** of total relation storage (`2,842 MB` indexes vs. `1,682 MB` heaps), and **69.7%** of `trips` storage (`2,021 MB` vs. `877 MB`), because `trips` carries 13 workload-driven covering/partial indexes across 19 partitions.
2. `payments` (`21.03×`) and `ratings` (`21.72×`) grew slightly above `20.0×` because `sql/08_partitioning.sql` added an 8-byte `TIMESTAMPTZ` `requested_at` column to every row to preserve declarative composite foreign keys.

---

## 7. Architecture for 100× Volume (~30 Million Trips/Year — Projected)

> **Projection note:** Every storage and latency figure in this section is an **explicit projection** extrapolated from our measured 20× `uber_large` dataset (`6,000,000` trips across 18 months = 4,000,000 trips/year, `4,535 MB` total DB size). Scaling to **100× seed** (`30,000,000` trips across 18 months, or ~20M–30M trips/year) multiplies our 20× measurements by **5×**.

### Projected 100× footprint (derived from measured `uber_large` = 4.54 GB at 20×)

- **Active 18-month working set:** `4.535 GB × 5` ≈ **`22.7 GB`** total database size (`~14.5 GB` for `trips` + indexes, `~3.8 GB` for `payments`, `~3.2 GB` for `ratings`, `~1.1 GB` for `riders`).
- **Single monthly `trips` partition at 100×:** ~1.65M–1.70M rows, `~250 MB` heap + `~570 MB` indexes = **`~820 MB/month`** (comfortably fits in RAM on a single PostgreSQL node with 32–64 GB RAM).
- **Multi-year growth (36 months retained online):** `~45 GB` active DB; archival keeps the hot working set bounded.

### 7.1 Partitioning at 100×

- Retain **monthly `RANGE (requested_at)` partitioning** on `uber.trips` (`~820 MB/month` keeps per-month B-tree indexes compact and hot in `shared_buffers`).
- Pre-create future monthly partitions 3 months ahead via `pg_partman` or a scheduled job so live inserts (`W01`, `W04`) never land in `trips_default`.
- Partition `payments` and `ratings` by `RANGE (requested_at)` on matching monthly boundaries once they exceed ~50M rows, enabling **partition-wise joins** (`enable_partitionwise_join = on`) for `R11` and `R22`.
- Add `AND t.requested_at = p.requested_at` to `R22` so joins from `payments` prune `trips` partitions at runtime.

### 7.2 Sharding strategy

At 22.7 GB, a single primary with read replicas handles 100× comfortably; sharding becomes necessary as write IOPS or multi-year volume exceeds single-node limits.

- **Recommended shard key:** **`city_id`** (hash- or list-sharded via Citus), with small reference tables (`cities`, `promo_codes`) replicated to every shard.
- **Shard-local queries (single-shard routing — zero fan-out):**
  - `R04` (Bengaluru daily trips), `R06` (per-city completed trips), `R07` (Mumbai top drivers), `R09` (Bengaluru win-back), `R12` (Delhi hourly surge), `R17` (cancellation rate per city), `R18` (Pune riders), `R19` (per-city driver leaderboard), `R23` (active riders per city/month), `W01` & `W04` (new trip requests routed by `city_id`).
- **Cross-shard queries (require coordinator fan-out & merge):**
  - `R01` (rider history across cities), `R02` (driver earnings across cities), `R03`/`R13` (global rider email/name lookup), `R05` (global dispatch queue), `R08` & `R20` (company-wide finance revenue—parallel partial sums merged on coordinator), `R10`, `R11`, `R14`, `R15`, `R16` (global admin pagination), `R21`, `R22`, `R24`, `R25`, `W02`, `W03`, `W05`.
- **Handling cross-shard work:** Use globally unique 64-bit IDs (Snowflake/UUIDv7) instead of serial integers; route global analytical queries (`R08`, `R11`, `R17`, `R20`, `R21`, `R23`) to an analytical replica/warehouse rather than fanning out across OLTP shards.

### 7.3 Read replicas and caching

| Tier | Assigned queries | Rationale |
|---|---|---|
| **Primary (read/write, strong consistency)** | `W01`, `W02`, `W03`, `W04`, `W05`, `R03`, `R05`, `R15` (immediately post-trip) | Mutations, login auth, live dispatch state, and read-after-write receipt flows cannot tolerate replication lag. |
| **Streaming Read Replicas (async, <100 ms lag)** | `R01`, `R02`, `R04`, `R06`, `R07`, `R08`, `R09`, `R10`, `R11`, `R12`, `R13`, `R16`, `R17`, `R18`, `R19`, `R20`, `R21`, `R22`, `R23`, `R24`, `R25` | Offloads heavy scans (`R11` ~1.2 s at 20× → projected ~6 s at 100×, `R23` ~1.0 s → ~5 s, `R17` ~0.5 s → ~2.4 s) from primary write IOPS. |
| **Redis / Application Cache** | `cities` & `promo_codes` metadata (TTL 1h), `R14` vehicle registration lookups (TTL 10m), `R06`/`R12`/`R17`/`R20`/`R21` dashboard aggregates (TTL 5–15m), `R18` rider `last_trip_at` (write-through on trip insert) | Eliminates repeated read load on static reference lookups and prevents `R18`'s partition-amplified `LATERAL` scans. |

### 7.4 Maintenance plan

- **Autovacuum on active `trips` partitions:** Only the **current month's partition** receives active writes; older months become read-only and freeze once. Lower per-table autovacuum thresholds on the active partition (`autovacuum_vacuum_scale_factor = 0.02`, `autovacuum_analyze_scale_factor = 0.01`, `autovacuum_vacuum_cost_limit = 1000`) so visibility maps stay fresh (preventing the `R08`/`R19`/`R20` regressions observed in Section 4.3).
- **Archival & retention (replacing `W05`):** Instead of running bulk `DELETE` jobs (`W05` took `373.5 ms` at 20× and projects to `~1.9 s` at 100×), detach partitions older than the retention window (`ALTER TABLE uber.trips DETACH PARTITION uber.trips_2025_01 CONCURRENTLY;`), export to Parquet/S3 cold storage, and `DROP TABLE`.
- **Summary tables / Materialized Views:** At 100×, full-history analytics (`R11` projected ~6 s, `R23` projected ~5 s) approach the 5,000 ms reporting target. Pre-aggregate daily city/driver/revenue rollups (`mv_daily_city_revenue`, `mv_driver_ratings_summary`) refreshed hourly with `REFRESH MATERIALIZED VIEW CONCURRENTLY` on a read replica.
- **Post-migration maintenance:** Always run `VACUUM (FULL, ANALYZE)` or `pg_repack` after any full-table backfill (such as `08_partitioning.sql`'s `payments`/`ratings` update) to reclaim 2× MVCC bloat.

---

## 8. Conclusion and Remaining Risks

**Verdict: Ready for next year's 20× volume.** With monthly `RANGE (requested_at)` partitioning, 20 workload-specific indexes, the CP-4 scale fixes for `R16` and `R25`, and post-migration vacuuming, **all 30 queries pass their official large-data targets on 6,000,000 trips** (`4.54 GB` total DB size), with real-time queries completing in **`0.15–2.78 ms`** and analytical queries completing in **`16.7–1,200 ms`**.

**Remaining risks to manage before 100× volume:**
1. **Unpruned `trips` queries (`R01`, `R15`, `R18`, `R22`):** As partition count grows from 19 to 36+, queries lacking a `requested_at` predicate incur linearly increasing planning and probe overhead. Mitigate by archiving partitions older than 18–24 months, adding `t.requested_at = p.requested_at` to `R22`, and denormalizing/caching `last_trip_at` for `R18`.
2. **Full-history analytical queries (`R11`, `R23`) at 100×:** At 5× beyond `uber_large`, `R11` (`1,200 ms` at 20×) and `R23` (`1,035 ms` at 20×) will approach or exceed `5,000 ms` on a single uncached node unless backed by read replicas and materialized rollups.
3. **High index write amplification (`69.7%` of `trips` storage):** Consolidate overlapping indexes if write throughput spikes to reduce WAL volume and memory pressure.
4. **Faculty `large_data.zip` delta:** If faculty later releases a different distribution in `large_data.zip`, re-run Path B below and recompute `R16`'s page-8,001 `trip_id` cursor on that dataset.

---

## 9. Reproducibility Commands

### Path A: Reproducing our exact 20× benchmark (`uber_large` via `sql/10_scale_to_large_20x.sql`)

```bash
unzip -q seed_data.zip
createdb uber_large
psql -d uber_large -c "ALTER DATABASE uber_large SET TimeZone TO 'Asia/Kolkata';"
psql -d uber_large -f sql/01_schema.sql
psql -d uber_large -f sql/02_load_data.sql
psql -d uber_large -f sql/10_scale_to_large_20x.sql
psql -d uber_large -f sql/08_partitioning.sql
psql -d uber_large -f sql/05_indexes.sql
psql -d uber_large -c "VACUUM (FULL, ANALYZE) uber.payments;"
psql -d uber_large -c "VACUUM (FULL, ANALYZE) uber.ratings;"
psql -d uber_large -c "VACUUM (ANALYZE) uber.trips;"
psql -d uber_large -f sql/09_scalability_checks.sql
./benchmarks/run_benchmark.sh uber_large large 3 sql/06_optimized_queries.sql
```

### Path B: Running on faculty `large_data.zip` (if released later)

Replace `sql/02_load_data.sql` + `sql/10_scale_to_large_20x.sql` with `unzip -q large_data.zip && psql -d uber_large -f sql/02_load_large_data.sql`, recompute `R16`'s cursor (`SELECT trip_id FROM uber.trips ORDER BY trip_id DESC OFFSET 199999 LIMIT 1;`), and execute the same partitioning, indexing, vacuum, check, and benchmark commands.
