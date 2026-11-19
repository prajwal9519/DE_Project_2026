# CP-3 Optimization Report

## 1. Objective

CP-3 adds workload-oriented indexes and uses an optimized version of the 30-query workload. The purpose is to compare measured execution times against the CP-2 baseline and explain the observed changes. All timings below are in milliseconds (ms).

## 2. Benchmark environment and method

- Database: `uber_cp1`
- PostgreSQL: 18.6 (Postgres.app)
- Dataset: the CP-1 seed dataset (300,000 trips, 30,000 riders, 3,000 drivers, 3,300 vehicles, 245,839 payments, 307,214 ratings, 40 promo codes, and 10 cities)
- Workload: 25 read queries (`R01`–`R25`) and 5 write queries (`W01`–`W05`)
- Repetitions: 3 executions per query for both baseline and optimized runs
- Measurement: the supplied benchmark runner uses `EXPLAIN (ANALYZE, BUFFERS)` and records the execution time from each plan.

The baseline numbers are from the final CP-2 baseline run. The optimized numbers are from the CP-3 optimized run after `sql/05_indexes.sql` was applied and `VACUUM (ANALYZE) uber.trips` was run. The figures are averages across the three executions reported by the benchmark runner.

## 3. Before/after timings

| Query | Type | Baseline avg (ms) | Optimized avg (ms) | Change |
|---|---|---:|---:|---:|
| R01 | READ | 10.680 | 0.142 | 98.7% faster |
| R02 | READ | 10.080 | 0.124 | 98.8% faster |
| R03 | READ | 6.710 | 0.141 | 97.9% faster |
| R04 | READ | 7.254 | 0.082 | 98.9% faster |
| R05 | READ | 11.983 | 0.163 | 98.6% faster |
| R06 | READ | 10.570 | 2.357 | 77.7% faster |
| R07 | READ | 10.957 | 3.967 | 63.8% faster |
| R08 | READ | 30.490 | 23.396 | 23.3% faster |
| R09 | READ | 17.435 | 4.071 | 76.7% faster |
| R10 | READ | 11.968 | 1.269 | 89.4% faster |
| R11 | READ | 35.377 | 33.164 | 6.3% faster |
| R12 | READ | 30.269 | 14.076 | 53.5% faster |
| R13 | READ | 9.023 | 0.925 | 89.7% faster |
| R14 | READ | 0.123 | 0.217 | 76.4% slower |
| R15 | READ | 0.074 | 0.441 | 495.9% slower |
| R16 | READ | 21.179 | 24.016 | 13.4% slower |
| R17 | READ | 24.145 | 24.779 | 2.6% slower |
| R18 | READ | 17,859.385 | 2.985 | approximately 99.98% faster (about 5,983x) |
| R19 | READ | 12.017 | 3.168 | 73.6% faster |
| R20 | READ | 23.320 | 2.166 | 90.7% faster |
| R21 | READ | 29.212 | 8.171 | 72.0% faster |
| R22 | READ | 8.276 | 1.020 | 87.7% faster |
| R23 | READ | 81.577 | 38.084 | 53.3% faster |
| R24 | READ | 15.957 | 0.054 | 99.7% faster |
| R25 | READ | 23.908 | 16.766 | 29.9% faster |
| W01 | WRITE | 1.658 | 1.204 | 27.4% faster |
| W02 | WRITE | 26.670 | 0.526 | 98.0% faster |
| W03 | WRITE | 2.355 | 3.656 | 55.2% slower |
| W04 | WRITE | 34.070 | 61.861 | 81.6% slower |
| W05 | WRITE | 34.261 | 12.146 | 64.5% faster |

## 4. Main observations

### 4.1 Largest improvements

- **R18** fell from 17,859.385 ms to 2.985 ms (approximately 5,983x faster). The optimized plan uses an index-only lookup on riders by home city and an index-only lookup on trips by rider and requested time. This addresses the repeated latest-trip lookup that made the baseline correlated-subquery query expensive.
- **R01–R05** now complete in roughly 0.08–0.16 ms. Their optimized plans use targeted B-tree indexes, including index-only scans and a bitmap index/heap scan, instead of scanning the entire trips or riders table.
- **R24** fell from 15.957 ms to 0.054 ms using the partial index for long completed trips.
- **R20, R22 and R10** also show substantial reductions, consistent with more selective access paths and the R10 query rewrite.

### 4.2 Queries with modest or no improvement

- **R08** improved by 23.3%, but still takes 23.396 ms. Its plan uses an index-only scan on successful payments; remaining work in the query still matters.
- **R11** improved by only 6.3%. The ratings access is index-only, but the plan still performs a sequential scan on trips.
- **R16 and R17** were slightly slower in this run. R16 already used the trips primary-key index in the baseline; R17 still uses sequential scans on trips and cities. The new indexes do not guarantee an improvement when the chosen access path or amount of data processed remains similar.
- **R25** improved by 29.9%, but its optimized plan still uses a sequential scan on trips.

### 4.3 Regressions and index trade-offs

- **R14 and R15** were already extremely fast in the baseline (0.123 ms and 0.074 ms). Their optimized measurements were 0.217 ms and 0.441 ms. At this scale, small absolute differences can be magnified as percentages; the additional index does not provide a useful benefit for queries already served by existing primary-key/unique indexes.
- **W03** increased from 2.355 ms to 3.656 ms, and **W04** increased from 34.070 ms to 61.861 ms. Maintaining additional indexes adds work to writes, so read improvements must be balanced against insert/update/delete overhead.

Across the 25 read-query averages, the unweighted mean fell from approximately 732.079 ms to 8.230 ms. This aggregate is dominated by R18, so the per-query table is the more useful comparison. Across the five write-query averages, the unweighted mean fell from approximately 19.803 ms to 15.879 ms, despite regressions in W03 and W04. These aggregate figures should be interpreted cautiously because each query has different work and result cardinality.

## 5. Correctness validation

The provided validation script reported `same_result = true` and `differing_rows = 0` for R02, R08, R09, R18, R20, and the W05 candidate-ID comparison.

R10 required a correctness fix. The original `NOT IN` predicate reads `trips.driver_id`, which includes NULL values. In the supplied data, 277 qualifying rows in that subquery have a NULL driver ID. As a result, the original `NOT IN` returned zero rows, while the corrected `NOT EXISTS` version returned 978 rows. This is a semantic correction, not a performance-only rewrite; the difference should be explained when presenting the result.

## 6. Execution-plan changes

Observed optimized plans include:

- Index Scan / Index Only Scan for selective lookups and queries whose required columns are covered by an index.
- Bitmap Index Scan + Bitmap Heap Scan for predicates that match multiple rows.
- Sequential Scans where PostgreSQL estimates that scanning the relation is still appropriate or where the query needs a large fraction of rows.

An index being present does not force PostgreSQL to use it. The planner selects a plan based on estimated cost, table statistics, predicate selectivity, required columns, and expected I/O.

## 7. Conclusion

The CP-3 indexes and selected query rewrites materially improve many read queries, especially R18, R01–R05, R20 and R24. The results also show that indexes have trade-offs: some already-fast reads became slightly slower, and W03/W04 incurred write overhead. The most important correctness finding is the R10 `NOT IN`/NULL issue and its `NOT EXISTS` correction. Further tuning should focus on queries that remain slow or still use sequential scans, while considering index storage and write cost.

## 8. Reproducibility notes

Commands used:

```bash
psql -d uber_cp1 -f sql/05_indexes.sql
psql -d uber_cp1 -c "VACUUM (ANALYZE) uber.trips;"
psql -d uber_cp1 -f sql/07_validate_optimized_queries.sql
./benchmarks/run_benchmark.sh uber_cp1 optimized 3 sql/06_optimized_queries.sql
```

Optimized benchmark output was saved under `benchmarks/results/optimized/` by the supplied script. Commit `benchmarks/results/optimized/summary.csv` together with this report and the CP-3 SQL files.

## 9. Index storage

Record the measured index storage footprint here after running the index-size query against the `uber` schema:

- Total index size: **to be measured**
- Largest indexes: **to be measured**

This section must be filled with values from the actual PostgreSQL instance; do not estimate index sizes.
