-- CP-4 verification and storage measurements.
\set ON_ERROR_STOP on
SET TIME ZONE 'Asia/Kolkata';
SET search_path TO uber, public;

-- 1) Row counts. Compare these with the row counts supplied by the faculty.
SELECT 'cities' AS table_name, COUNT(*) AS rows FROM uber.cities
UNION ALL SELECT 'riders', COUNT(*) FROM uber.riders
UNION ALL SELECT 'drivers', COUNT(*) FROM uber.drivers
UNION ALL SELECT 'vehicles', COUNT(*) FROM uber.vehicles
UNION ALL SELECT 'promo_codes', COUNT(*) FROM uber.promo_codes
UNION ALL SELECT 'trips', COUNT(*) FROM uber.trips
UNION ALL SELECT 'payments', COUNT(*) FROM uber.payments
UNION ALL SELECT 'ratings', COUNT(*) FROM uber.ratings
ORDER BY table_name;

-- 2) Prove that trip_id is unique in the supplied dataset (the partitioned
-- primary key is (trip_id, requested_at), due to PostgreSQL's partition rule).
SELECT COUNT(*) AS duplicate_trip_id_groups
FROM (
    SELECT trip_id
    FROM uber.trips
    GROUP BY trip_id
    HAVING COUNT(*) > 1
) duplicates;

-- 3) Prove date-based partition pruning. The plan should name only the
-- monthly partition covering May 2026 (rather than every trips partition).
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*)
FROM uber.trips
WHERE requested_at >= TIMESTAMPTZ '2026-05-01 00:00:00+05:30'
  AND requested_at <  TIMESTAMPTZ '2026-06-01 00:00:00+05:30';

-- 4) Verify child rows still reference an existing trip through the
-- partition-aware composite key.
SELECT 'payments_without_trip' AS check_name, COUNT(*) AS violations
FROM uber.payments p
LEFT JOIN uber.trips t
  ON t.trip_id = p.trip_id
 AND t.requested_at = p.requested_at
WHERE t.trip_id IS NULL
UNION ALL
SELECT 'ratings_without_trip', COUNT(*)
FROM uber.ratings r
LEFT JOIN uber.trips t
  ON t.trip_id = r.trip_id
 AND t.requested_at = r.requested_at
WHERE t.trip_id IS NULL;

-- 5) Whole database size.
SELECT
    current_database() AS database_name,
    pg_size_pretty(pg_database_size(current_database())) AS database_size;

-- 6) Per-table/partition table bytes, index bytes, and total bytes.
-- The leaf partitions appear separately in this output.
SELECT
    schemaname,
    relname,
    pg_size_pretty(pg_relation_size(relid)) AS table_bytes,
    pg_size_pretty(pg_indexes_size(relid)) AS index_bytes,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_bytes
FROM pg_catalog.pg_statio_user_tables
WHERE schemaname = 'uber'
ORDER BY pg_total_relation_size(relid) DESC;
