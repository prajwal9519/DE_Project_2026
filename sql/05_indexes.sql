-- CP-3: workload-driven indexes for the Uber ride-hailing database
-- Apply AFTER CP-1 schema/data load and CP-2 baseline measurement.
-- Run from the repository root:
--   psql -d uber_cp1 -f sql/05_indexes.sql
-- These are workload indexes; do not edit the supplied original workload.

\set ON_ERROR_STOP on
SET search_path TO uber, public;

-- R01, R09, R18: rider equality followed by time ordering/range.
-- DESC supports the latest-trip access pattern; the same leading rider_id
-- also supports the anti-existence probe for R09.
CREATE INDEX IF NOT EXISTS idx_trips_rider_requested_desc
    ON uber.trips (rider_id, requested_at DESC);

-- R02, R07, R10, R19: driver-specific time-window lookups and NOT EXISTS.
-- Equality key first, then requested_at range; INCLUDE lets earnings and
-- status be checked without making them search keys.
CREATE INDEX IF NOT EXISTS idx_trips_driver_requested_cover
    ON uber.trips (driver_id, requested_at)
    INCLUDE (status, fare_amount);

-- R09: narrow the candidate riders to the requested home city and return
-- the rider columns used by the campaign list.
CREATE INDEX IF NOT EXISTS idx_riders_home_city_cover
    ON uber.riders (home_city_id, rider_id)
    INCLUDE (full_name, email);

-- R03: the predicate applies LOWER() to email, so index the same expression.
CREATE INDEX IF NOT EXISTS idx_riders_lower_email
    ON uber.riders ((LOWER(email)));

-- R04, R12, R17: city equality/grouping then time access; included columns
-- cover the projected/filter/aggregate values used by these queries.
CREATE INDEX IF NOT EXISTS idx_trips_city_requested_cover
    ON uber.trips (city_id, requested_at)
    INCLUDE (trip_id, status, fare_amount, surge_multiplier);

-- R05: only the three live-dispatch statuses are indexed, already ordered
-- by requested_at; this is a partial, covering index for the 50-row queue.
CREATE INDEX IF NOT EXISTS idx_trips_dispatch_requested
    ON uber.trips (requested_at)
    INCLUDE (trip_id, city_id, status)
    WHERE status IN ('REQUESTED', 'ACCEPTED', 'ONGOING');

-- R06, R19, R20: completed-trip reports constrained by requested_at.
-- Partial predicate removes all non-completed trips; INCLUDE supports
-- city/driver grouping and fare aggregation without widening the key.
CREATE INDEX IF NOT EXISTS idx_trips_completed_requested_cover
    ON uber.trips (requested_at)
    INCLUDE (city_id, driver_id, fare_amount)
    WHERE status = 'COMPLETED';

-- R07, R19: find a city's drivers before probing trips by driver_id.
CREATE INDEX IF NOT EXISTS idx_drivers_city_driver
    ON uber.drivers (city_id, driver_id);

-- R08: range scan over successful 2026 payments; the partial predicate
-- avoids carrying failed/refunded payment rows in this reporting index.
CREATE INDEX IF NOT EXISTS idx_payments_success_paid_at
    ON uber.payments (paid_at)
    INCLUDE (method, amount)
    WHERE payment_status = 'SUCCESS';

-- R22: failed-payment lookback; DESC matches the requested newest-first order.
CREATE INDEX IF NOT EXISTS idx_payments_failed_paid_at
    ON uber.payments (paid_at DESC)
    INCLUDE (payment_id, trip_id, amount)
    WHERE payment_status = 'FAILED';

-- R11: only rider-provided ratings are needed; the PK starts with trip_id,
-- so this partial index makes rated_by='RIDER' the indexed subset.
CREATE INDEX IF NOT EXISTS idx_ratings_rider_trip_cover
    ON uber.ratings (trip_id)
    INCLUDE (stars)
    WHERE rated_by = 'RIDER';

-- R13: a leading-wildcard ILIKE cannot use a normal B-tree pattern lookup.
-- pg_trgm supplies a GIN operator class for substring searches.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_riders_full_name_trgm
    ON uber.riders USING GIN (full_name gin_trgm_ops);

-- R21: speed up the trips-to-promo_codes side of the LEFT JOIN aggregation.
CREATE INDEX IF NOT EXISTS idx_trips_promo_code
    ON uber.trips (promo_code)
    WHERE promo_code IS NOT NULL;

-- R23: restrict to the requested_at window and carry the grouping/distinct keys.
CREATE INDEX IF NOT EXISTS idx_trips_requested_city_rider
    ON uber.trips (requested_at, city_id, rider_id);

-- R16: retain the existing deep OFFSET semantics but make the page query
-- covering and ordered in the requested descending trip_id direction.
-- OFFSET still has to walk past 200,000 index entries; this only reduces heap I/O.
CREATE INDEX IF NOT EXISTS idx_trips_admin_page_cover
    ON uber.trips (trip_id DESC)
    INCLUDE (rider_id, driver_id, city_id, status, fare_amount, requested_at);

-- R24: the partial predicate stores only qualifying long completed trips,
-- in fare order, so the top-100 query can avoid sorting unrelated rows.
CREATE INDEX IF NOT EXISTS idx_trips_long_completed_fare
    ON uber.trips (fare_amount DESC)
    INCLUDE (trip_id, driver_id, distance_km, duration_min)
    WHERE status = 'COMPLETED'
      AND (distance_km > 43 OR duration_min > 150);

-- R25: index only completed trips that satisfy the fraud threshold, ordered
-- by the same rounded ratio returned by the query.
CREATE INDEX IF NOT EXISTS idx_trips_high_fare_per_km
    ON uber.trips ((ROUND(fare_amount / NULLIF(distance_km, 0), 2)) DESC)
    INCLUDE (trip_id, city_id, distance_km, fare_amount)
    WHERE status = 'COMPLETED'
      AND distance_km > 0
      AND fare_amount / NULLIF(distance_km, 0) > 100;

-- W02: locate the smallest trip_id among ongoing trips for the completion update.
CREATE INDEX IF NOT EXISTS idx_trips_ongoing_trip_id
    ON uber.trips (trip_id)
    WHERE status = 'ONGOING';

-- W03: locate active drivers below the rating threshold; the partial index
-- excludes inactive/suspended drivers.
CREATE INDEX IF NOT EXISTS idx_drivers_active_rating
    ON uber.drivers (driver_rating, driver_id)
    WHERE status = 'ACTIVE';

-- W05: partial timestamp index for old cancelled trips. The optimized query
-- uses IN, equivalent under the trips.status CHECK constraint.
CREATE INDEX IF NOT EXISTS idx_trips_cancelled_requested
    ON uber.trips (requested_at)
    WHERE status IN ('CANCELLED_BY_RIDER', 'CANCELLED_BY_DRIVER');

-- Refresh planner statistics after creating the indexes.
ANALYZE uber.trips;
ANALYZE uber.riders;
ANALYZE uber.drivers;
ANALYZE uber.vehicles;
ANALYZE uber.payments;
ANALYZE uber.ratings;
ANALYZE uber.promo_codes;
ANALYZE uber.cities;
