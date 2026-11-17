# CP-2: Baseline Query Timings

## 1. Objective and scope

This checkpoint establishes the unoptimized performance baseline for the supplied 30-query RideNow/Uber-style workload. The workload contains 25 read queries (`R01`–`R25`) and 5 write queries (`W01`–`W05`). Each query was executed three times using the provided benchmark script. The average is the arithmetic mean of the three measured PostgreSQL execution times.

## 2. Benchmark method

The workload was run with the supplied script and original query file (neither was modified):

```bash
./benchmarks/run_benchmark.sh uber_cp1 baseline 3
```

The script executes each query with `EXPLAIN (ANALYZE, BUFFERS)`, captures the `Execution Time` value in milliseconds, writes the aggregate values to `benchmarks/results/baseline/summary.csv`, and saves the raw plans as one `.txt` file per query. Write queries are wrapped in `BEGIN`/`ROLLBACK`, so their changes are rolled back after each measurement.

The benchmark was run twice during setup. The script resets `summary.csv` and each query's plan file on every invocation; therefore, this report records the **latest (second) successful invocation**, whose individual measurements were extracted from the 30 raw plan files. It does not combine the two invocations.

### Test environment

| Item | Value |
|---|---|
| Database | `uber_cp1` |
| PostgreSQL | 18.6 (Postgres.app) |
| Platform | macOS on Apple Silicon (`aarch64-apple-darwin`) |
| Workload | `queries/workload_30.sql` (supplied; unchanged) |
| Runs per query | 3 |
| Measurement | `EXPLAIN (ANALYZE, BUFFERS)` → `Execution Time` (ms) |
| Benchmark date | 17 November 2026 |

The CP-1 load script ran `ANALYZE` on all eight tables after import. No workload-tuning indexes were added for this baseline. The plans can still use indexes automatically created by primary-key and `UNIQUE` constraints in the CP-1 schema.

## 3. Baseline timings

All times are in milliseconds (ms). Averages are calculated from the three run values shown and rounded to three decimal places.

| Query | Type | What it does | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---|---:|---:|---:|---:|
| R01 | READ | Rider's last 20 trips | 18.003 | 6.514 | 7.524 | **10.680** |
| R02 | READ | Driver's March 2026 completed trips and earnings | 11.924 | 9.370 | 8.945 | **10.080** |
| R03 | READ | Case-insensitive rider login by email | 7.151 | 6.543 | 6.435 | **6.710** |
| R04 | READ | Bengaluru trips requested on 10 May 2026 | 6.715 | 7.211 | 7.836 | **7.254** |
| R05 | READ | Oldest requested, accepted and ongoing trips | 11.890 | 12.346 | 11.713 | **11.983** |
| R06 | READ | Completed trips per city in June 2026 | 10.294 | 10.642 | 10.775 | **10.570** |
| R07 | READ | Top 10 earning drivers in Mumbai, Q1 2026 | 10.457 | 11.041 | 11.374 | **10.957** |
| R08 | READ | Successful revenue by payment method and month in 2026 | 30.852 | 30.401 | 30.216 | **30.490** |
| R09 | READ | Bengaluru riders with no trip since 1 April 2026 | 17.772 | 17.288 | 17.244 | **17.435** |
| R10 | READ | Active drivers with no trip since 25 June 2026 | 12.403 | 11.855 | 11.645 | **11.968** |
| R11 | READ | 20 lowest-rated drivers with at least 20 rider ratings | 31.277 | 44.078 | 30.776 | **35.377** |
| R12 | READ | Average surge by hour in Delhi | 29.967 | 31.479 | 29.361 | **30.269** |
| R13 | READ | Search riders by surname (Sharma) | 9.211 | 9.037 | 8.820 | **9.023** |
| R14 | READ | Vehicle and driver lookup by registration number | 0.035 | 0.036 | 0.297 | **0.123** |
| R15 | READ | Single-trip receipt with rider, driver, vehicle and payment | 0.079 | 0.068 | 0.074 | **0.074** |
| R16 | READ | Admin trips page 8,001 (25 rows) | 21.458 | 21.494 | 20.584 | **21.179** |
| R17 | READ | Cancellation rate per city | 23.646 | 24.293 | 24.496 | **24.145** |
| R18 | READ | Last trip date of every rider in Pune | 18055.911 | 17383.736 | 18138.508 | **17859.385** |
| R19 | READ | Top 3 drivers per city by completed trips in May 2026 | 13.279 | 11.195 | 11.578 | **12.017** |
| R20 | READ | Daily revenue and running total for May 2026 | 18.834 | 28.643 | 22.484 | **23.320** |
| R21 | READ | Usage of every promo code | 22.319 | 27.205 | 38.113 | **29.212** |
| R22 | READ | Failed payments since 24 June 2026 with rider phone | 10.644 | 7.329 | 6.856 | **8.276** |
| R23 | READ | Distinct active riders per city per month in 2026 | 58.161 | 75.147 | 111.424 | **81.577** |
| R24 | READ | Unusually long completed trips | 18.991 | 13.972 | 14.908 | **15.957** |
| R25 | READ | Completed trips charging more than ₹100 per km | 20.244 | 20.882 | 30.599 | **23.908** |
| W01 | WRITE | Insert one new trip request | 1.586 | 2.014 | 1.373 | **1.658** |
| W02 | WRITE | Complete the oldest ongoing trip | 28.508 | 25.822 | 25.680 | **26.670** |
| W03 | WRITE | Suspend active drivers rated below 3.5 | 2.334 | 2.426 | 2.305 | **2.355** |
| W04 | WRITE | Bulk insert 5,000 corporate trip requests | 33.028 | 35.017 | 34.165 | **34.070** |
| W05 | WRITE | Delete cancelled trips requested before 1 February 2025 | 33.476 | 34.588 | 34.720 | **34.261** |
| **Sum of per-query averages** | — | **30 queries** | — | — | — | **18,400.983** |

> The total row is the arithmetic sum of the 30 per-query averages; it is not a separately measured end-to-end benchmark duration.

## 4. Execution-plan scan types and observations

The scan nodes below are taken from the benchmark script's scan-node summary for the final run of each query. Queries may contain more than one node because of joins.

| Query | Scan type(s) observed | Why the query is relatively slow or fast |
|---|---|---|
| R01 | Seq Scan on trips | The rider filter and descending time order are evaluated over a sequential scan; a matching composite index is a likely CP-3 candidate. |
| R02 | Seq Scan on trips | The trips table is scanned and filtered by driver, status and month; applying DATE() to requested_at also makes a plain timestamp range index harder to use. |
| R03 | Seq Scan on riders | LOWER(email) is applied to the column, so the existing ordinary unique email index is not used by this plan. |
| R04 | Seq Scan on trips; Seq Scan on cities | All trips are scanned before applying the city/date condition; the cities table is also scanned for the join. |
| R05 | Seq Scan on trips | The status filter and oldest-first ordering require examining trips without a supporting status/time access path. |
| R06 | Seq Scan on trips; Seq Scan on cities | The query scans trips and joins cities, then groups completed trips in the June date range. |
| R07 | Seq Scan on trips; Seq Scan on drivers; Seq Scan on cities | The query scans trips and joins drivers/cities before grouping and sorting Mumbai driver earnings for Q1. |
| R08 | Seq Scan on payments | Payments are scanned to find successful 2026 payments and aggregate them by month and method; EXTRACT(YEAR ...) is applied to paid_at. |
| R09 | Seq Scan on riders; Seq Scan on trips | The anti-subquery checks riders against trips since a cutoff; both tables are sequentially scanned in this plan. |
| R10 | Seq Scan on drivers; Seq Scan on trips | The active-driver filter is combined with a NOT IN subquery over trips; the plan scans drivers and trips. |
| R11 | Seq Scan on trips; Seq Scan on ratings | Trips and ratings are sequentially scanned for the join and aggregation of rider-given ratings; one run was noticeably slower than the other two. |
| R12 | Seq Scan on trips; Seq Scan on cities | Trips are scanned and joined to cities to calculate hourly surge averages; the query has no date restriction. |
| R13 | Seq Scan on riders | The leading-wildcard ILIKE search cannot use a conventional B-tree name index efficiently, so riders are sequentially scanned. |
| R14 | Index Scan using vehicles_registration_no_key on vehicles; Index Scan using drivers_pkey on drivers | A selective lookup uses the unique registration-number index, followed by the driver's primary-key index; this is one of the fastest queries. |
| R15 | Index Scan using trips_pkey on trips; Index Scan using riders_pkey on riders; Index Scan using drivers_pkey on drivers; Index Scan using uq_vehicles_vehicle_driver on vehicles; Index Scan using payments_trip_id_key on payments | A single trip is located through its primary key and related rows are reached through primary-key/unique indexes; this is the fastest query on average. |
| R16 | Index Scan using trips_pkey | The primary-key index is used, but OFFSET 200000 still requires stepping past a large number of earlier entries. |
| R17 | Seq Scan on trips; Seq Scan on cities | The query scans trips and cities to calculate cancellation totals and percentages across every city. |
| R18 | Seq Scan on riders; Seq Scan on trips | This is the clear outlier: a correlated MAX(requested_at) subquery is evaluated for Pune riders while trips has no index on rider_id to support the lookup, resulting in repeated work against the trips table. |
| R19 | Seq Scan on trips; Seq Scan on drivers | Trips and drivers are scanned and joined before grouping completed May trips and applying a per-city RANK window function. |
| R20 | Seq Scan on trips | Trips are scanned for May completed rides; casting requested_at to DATE in the filter/grouping adds work and can prevent a simple timestamp index range scan. |
| R21 | Seq Scan on trips; Seq Scan on promo_codes | The query scans trips and joins the small promo-code table to count usage across all promo codes. |
| R22 | Seq Scan on payments; Index Scan using trips_pkey on trips; Index Scan using riders_pkey on riders | Payments are sequentially scanned for failed payments after the cutoff; trip and rider details are then reached with primary-key indexes. |
| R23 | Seq Scan on trips | The entire trips table is scanned to compute distinct riders per city/month; COUNT(DISTINCT ...) and grouping make this a comparatively expensive aggregate. |
| R24 | Seq Scan on trips | Trips are scanned to find completed rides above distance/duration thresholds and then ordered by fare. |
| R25 | Seq Scan on trips | Trips are scanned because the fare-per-kilometre expression must be evaluated for completed rides before sorting the qualifying results. |
| W01 | No scan node reported | A single VALUES row is inserted; no table-scan node is expected. Constraints and indexes still need to be maintained. |
| W02 | Index Scan using trips_pkey | The target trip is updated using a primary-key index lookup; the operation also has to locate the oldest ongoing trip. |
| W03 | Seq Scan on drivers | Drivers are sequentially scanned to find active drivers below the rating threshold, then qualifying rows are updated. |
| W04 | No scan node reported | The bulk INSERT ... SELECT generates 5,000 rows; no base-table scan node was reported. Insert and constraint/index maintenance account for the measured work. |
| W05 | Seq Scan on trips | Trips are sequentially scanned to identify cancelled trips before the retention cutoff, then matching rows are deleted. |

## 5. Main findings

1. **R18 is the dominant baseline bottleneck** at **17,859.385 ms (17.859 seconds)**. Its correlated subquery calculates the latest trip timestamp for every Pune rider. The observed sequential scans on both `riders` and `trips`, together with the query shape, indicate repeated work against `trips`; an index beginning with `trips.rider_id` is a high-priority CP-3 investigation.
2. **R23 is the next slowest read query** at **81.577 ms**. It scans the trips table and computes distinct active riders grouped by city and month.
3. **R11** averages **35.377 ms** because it joins and aggregates the large `ratings` and `trips` tables. Its second run (44.078 ms) is higher than the other two, so timings should be interpreted with normal run-to-run variation in mind.
4. **R14 and R15 are the fastest reads** at **0.123 ms** and **0.074 ms**, respectively. Their plans use existing unique/primary-key indexes for selective lookups.
5. Several query predicates apply functions or casts to filtered columns, including `LOWER(email)` in R03, `DATE(requested_at)` in R02, `EXTRACT(YEAR FROM paid_at)` in R08, `ILIKE '%sharma%'` in R13 and `requested_at::date` in R20. These forms should be evaluated carefully during CP-3 because they can prevent ordinary B-tree indexes from being used as direct range/equality lookups.
6. R16 uses the trips primary-key index, but deep pagination with `OFFSET 200000` still requires advancing past many rows. This is a potential query-design issue for later evaluation.
7. The write workload ranges from a single-row insert (W01) to a 5,000-row batch insert (W04) and a delete scan (W05). Write timings must be considered alongside read improvements in CP-3, because additional indexes add maintenance work to inserts, updates and deletes.

## 6. Baseline interpretation and CP-3 starting points

The baseline plans show that most read queries use sequential scans on `trips`, `payments`, `riders`, `drivers` or `ratings`. This is expected for an unoptimized baseline without workload-specific indexes. The primary-key and unique-constraint indexes already created in CP-1 explain the selective index access observed in R14, R15, R16 and parts of R22.

The highest-priority candidates for CP-3 investigation are:

- R18: investigate an index on `trips(rider_id, requested_at)` to support the per-rider latest-trip lookup.
- R01: investigate a composite index on `trips(rider_id, requested_at DESC)` for one rider's recent trips.
- R05: investigate an access path that supports filtering by active status and ordering by `requested_at`.
- R08/R22: investigate payment filtering by `payment_status` and `paid_at`.
- R02/R04/R06/R07: investigate indexes aligned with equality filters and timestamp ranges, after checking selectivity and the actual full plans.
- R13: because the search pattern starts with `%`, investigate PostgreSQL trigram indexing rather than assuming a standard B-tree index will help.

These are **candidates for testing, not indexes already created**. CP-3 must measure the effect of each change and prove that query results remain unchanged. Do not add these indexes as part of CP-2.

## 7. Deliverable verification

The first completed benchmark run was verified to produce 31 lines in `summary.csv` (one header plus 30 query rows) and 30 raw `.txt` plan files. The second completed run recreated those same output files. Re-run the verification commands below after the latest run before committing.

```bash
wc -l benchmarks/results/baseline/summary.csv
find benchmarks/results/baseline -name '*.txt' | wc -l
```

Expected verification output: `31` for the CSV line count and `30` for the raw plan file count.

The `summary.csv` and raw plan files are generated locally by the supplied benchmark script. Commit `benchmarks/results/baseline/summary.csv` as required by CP-2; keep the raw plans available for analysis and future reference.
