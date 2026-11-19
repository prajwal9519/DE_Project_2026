-- CP-3 result validation for rewritten queries.
-- Run from repository root:
--   psql -d uber_cp1 -f sql/07_validate_optimized_queries.sql
-- Each SAME_RESULT check uses EXCEPT ALL in both directions, so duplicates count.
-- R10 is handled separately because its original NOT IN result is wrong when NULLs exist.

\set ON_ERROR_STOP on
SET search_path TO uber, public;

-- R02: DATE(timestamptz) range rewrite.
WITH original AS (
    SELECT driver_id, count(*) AS trips, sum(fare_amount) AS earnings
    FROM trips
    WHERE driver_id = 217 AND status = 'COMPLETED'
      AND DATE(requested_at) BETWEEN '2026-03-01' AND '2026-03-31'
    GROUP BY driver_id
), optimized AS (
    SELECT driver_id, count(*) AS trips, sum(fare_amount) AS earnings
    FROM trips
    WHERE driver_id = 217 AND status = 'COMPLETED'
      AND requested_at >= (TIMESTAMP '2026-03-01 00:00:00' AT TIME ZONE current_setting('TimeZone'))
      AND requested_at <  (TIMESTAMP '2026-04-01 00:00:00' AT TIME ZONE current_setting('TimeZone'))
    GROUP BY driver_id
), diff AS (
    (SELECT * FROM original EXCEPT ALL SELECT * FROM optimized)
    UNION ALL
    (SELECT * FROM optimized EXCEPT ALL SELECT * FROM original)
)
SELECT 'R02' AS query_id, COUNT(*) = 0 AS same_result, COUNT(*) AS differing_rows FROM diff;

-- R08: EXTRACT(YEAR) rewritten as a session-local half-open range.
WITH original AS (
    SELECT date_trunc('month', paid_at) AS month, method, count(*) AS payments, sum(amount) AS revenue
    FROM payments
    WHERE payment_status = 'SUCCESS' AND EXTRACT(YEAR FROM paid_at) = 2026
    GROUP BY 1, 2
), optimized AS (
    SELECT date_trunc('month', paid_at) AS month, method, count(*) AS payments, sum(amount) AS revenue
    FROM payments
    WHERE payment_status = 'SUCCESS'
      AND paid_at >= (TIMESTAMP '2026-01-01 00:00:00' AT TIME ZONE current_setting('TimeZone'))
      AND paid_at <  (TIMESTAMP '2027-01-01 00:00:00' AT TIME ZONE current_setting('TimeZone'))
    GROUP BY 1, 2
), diff AS (
    (SELECT * FROM original EXCEPT ALL SELECT * FROM optimized)
    UNION ALL
    (SELECT * FROM optimized EXCEPT ALL SELECT * FROM original)
)
SELECT 'R08' AS query_id, COUNT(*) = 0 AS same_result, COUNT(*) AS differing_rows FROM diff;

-- R09: NOT IN to NOT EXISTS; riders.rider_id is NOT NULL, so semantics are preserved.
WITH original AS (
    SELECT r.rider_id, r.full_name, r.email
    FROM riders r
    WHERE r.home_city_id = 1
      AND r.rider_id NOT IN (SELECT t.rider_id FROM trips t WHERE t.requested_at >= '2026-04-01')
), optimized AS (
    SELECT r.rider_id, r.full_name, r.email
    FROM riders r
    WHERE r.home_city_id = 1
      AND NOT EXISTS (
          SELECT 1 FROM trips t
          WHERE t.rider_id = r.rider_id AND t.requested_at >= '2026-04-01'
      )
), diff AS (
    (SELECT * FROM original EXCEPT ALL SELECT * FROM optimized)
    UNION ALL
    (SELECT * FROM optimized EXCEPT ALL SELECT * FROM original)
)
SELECT 'R09' AS query_id, COUNT(*) = 0 AS same_result, COUNT(*) AS differing_rows FROM diff;

-- R18: scalar correlated MAX rewritten as an indexed LATERAL top-1 lookup.
WITH original AS (
    SELECT r.rider_id, r.full_name,
           (SELECT max(t.requested_at) FROM trips t WHERE t.rider_id = r.rider_id) AS last_trip_at
    FROM riders r
    WHERE r.home_city_id = 6
), optimized AS (
    SELECT r.rider_id, r.full_name, latest.last_trip_at
    FROM riders r
    LEFT JOIN LATERAL (
        SELECT t.requested_at AS last_trip_at
        FROM trips t WHERE t.rider_id = r.rider_id
        ORDER BY t.requested_at DESC LIMIT 1
    ) latest ON TRUE
    WHERE r.home_city_id = 6
), diff AS (
    (SELECT * FROM original EXCEPT ALL SELECT * FROM optimized)
    UNION ALL
    (SELECT * FROM optimized EXCEPT ALL SELECT * FROM original)
)
SELECT 'R18' AS query_id, COUNT(*) = 0 AS same_result, COUNT(*) AS differing_rows FROM diff;

-- R20: date-cast filter rewritten as session-local timestamp range; day grouping stays unchanged.
WITH original AS (
    SELECT day, revenue, sum(revenue) OVER (ORDER BY day) AS running_total
    FROM (
        SELECT requested_at::date AS day, sum(fare_amount) AS revenue
        FROM trips
        WHERE status = 'COMPLETED'
          AND requested_at::date >= '2026-05-01' AND requested_at::date <= '2026-05-31'
        GROUP BY 1
    ) daily
), optimized AS (
    SELECT day, revenue, sum(revenue) OVER (ORDER BY day) AS running_total
    FROM (
        SELECT requested_at::date AS day, sum(fare_amount) AS revenue
        FROM trips
        WHERE status = 'COMPLETED'
          AND requested_at >= (TIMESTAMP '2026-05-01 00:00:00' AT TIME ZONE current_setting('TimeZone'))
          AND requested_at <  (TIMESTAMP '2026-06-01 00:00:00' AT TIME ZONE current_setting('TimeZone'))
        GROUP BY 1
    ) daily
), diff AS (
    (SELECT * FROM original EXCEPT ALL SELECT * FROM optimized)
    UNION ALL
    (SELECT * FROM optimized EXCEPT ALL SELECT * FROM original)
)
SELECT 'R20' AS query_id, COUNT(*) = 0 AS same_result, COUNT(*) AS differing_rows FROM diff;

-- W05: the CHECK constraint restricts status to the two cancellation values,
-- so LIKE 'CANCELLED%' and this IN-list identify exactly the same trip IDs.
WITH original AS (
    SELECT trip_id FROM trips
    WHERE status LIKE 'CANCELLED%' AND requested_at < '2025-02-01'
), optimized AS (
    SELECT trip_id FROM trips
    WHERE status IN ('CANCELLED_BY_RIDER', 'CANCELLED_BY_DRIVER')
      AND requested_at < '2025-02-01'
), diff AS (
    (SELECT * FROM original EXCEPT ALL SELECT * FROM optimized)
    UNION ALL
    (SELECT * FROM optimized EXCEPT ALL SELECT * FROM original)
)
SELECT 'W05 candidate IDs' AS query_id, COUNT(*) = 0 AS same_result, COUNT(*) AS differing_rows FROM diff;

-- R10 wrong-result diagnosis: a NULL in the NOT IN subquery makes comparisons UNKNOWN.
-- With this seed data, 277 recent trips have NULL driver_id; the original query
-- therefore returns zero rows, while NOT EXISTS finds drivers with no recent trip.
SELECT
    (SELECT COUNT(*) FROM trips WHERE requested_at >= '2026-06-25' AND driver_id IS NULL)
        AS null_driver_rows_in_subquery,
    (SELECT COUNT(*) FROM drivers d
     WHERE d.status = 'ACTIVE'
       AND d.driver_id NOT IN (SELECT t.driver_id FROM trips t WHERE t.requested_at >= '2026-06-25'))
        AS original_not_in_rows,
    (SELECT COUNT(*) FROM drivers d
     WHERE d.status = 'ACTIVE'
       AND NOT EXISTS (SELECT 1 FROM trips t
                       WHERE t.driver_id = d.driver_id AND t.requested_at >= '2026-06-25'))
        AS corrected_not_exists_rows;
