-- CP-4: monthly RANGE partitioning for the large trips table.
-- Run ONLY in the fresh large-data database, after loading large_data/ with
-- sql/02_load_large_data.sql. Run this BEFORE sql/05_indexes.sql so that
-- CP-3 indexes are created on the partitioned parent and propagated.
--
-- The database/session timezone is set to Asia/Kolkata because the supplied
-- timestamps are local Indian timestamps (+05:30). Monthly boundaries then
-- align with the workload's local-calendar date predicates.
--
-- PostgreSQL rule: a PRIMARY KEY / UNIQUE constraint on a partitioned table
-- must include every partition key column. Therefore the partitioned table
-- uses PRIMARY KEY (trip_id, requested_at), not PRIMARY KEY (trip_id).
-- payments and ratings gain requested_at so their foreign keys can reference
-- this composite key. The supplied data has globally unique trip_id values;
-- this is verified in the large-data checks. For a production design that
-- must enforce trip_id uniqueness independently of date, use a global
-- trip-id registry or globally allocated IDs.

\set ON_ERROR_STOP on
SET TIME ZONE 'Asia/Kolkata';
SET search_path TO uber, public;

BEGIN;

-- Fail early if the script is being applied to the wrong database state.
DO $$
BEGIN
    IF to_regclass('uber.trips') IS NULL THEN
        RAISE EXCEPTION 'uber.trips does not exist. Load the large dataset first.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_partitioned_table
        WHERE partrelid = 'uber.trips'::regclass
    ) THEN
        RAISE EXCEPTION 'uber.trips is already partitioned; refusing to run twice.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'uber'
          AND table_name IN ('payments', 'ratings')
          AND column_name = 'requested_at'
    ) THEN
        RAISE EXCEPTION 'payments/ratings already contain requested_at; check the database state.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM uber.trips) THEN
        RAISE EXCEPTION 'uber.trips is empty. Load large_data before partitioning.';
    END IF;

    IF EXISTS (
        SELECT trip_id
        FROM uber.trips
        GROUP BY trip_id
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION 'trip_id is not globally unique. Resolve duplicates before RANGE partitioning.';
    END IF;
END
$$;

-- Add the partition timestamp to child tables so their foreign keys can
-- reference the partitioned table's composite primary key.
ALTER TABLE uber.payments ADD COLUMN requested_at TIMESTAMPTZ;
ALTER TABLE uber.ratings  ADD COLUMN requested_at TIMESTAMPTZ;

UPDATE uber.payments p
SET requested_at = t.requested_at
FROM uber.trips t
WHERE t.trip_id = p.trip_id;

UPDATE uber.ratings r
SET requested_at = t.requested_at
FROM uber.trips t
WHERE t.trip_id = r.trip_id;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM uber.payments WHERE requested_at IS NULL) THEN
        RAISE EXCEPTION 'Could not map every payment to a trip timestamp.';
    END IF;
    IF EXISTS (SELECT 1 FROM uber.ratings WHERE requested_at IS NULL) THEN
        RAISE EXCEPTION 'Could not map every rating to a trip timestamp.';
    END IF;
END
$$;

ALTER TABLE uber.payments ALTER COLUMN requested_at SET NOT NULL;
ALTER TABLE uber.ratings  ALTER COLUMN requested_at SET NOT NULL;

-- Remove the old single-column foreign keys before replacing the trips table.
ALTER TABLE uber.payments DROP CONSTRAINT IF EXISTS fk_payments_trip;
ALTER TABLE uber.ratings  DROP CONSTRAINT IF EXISTS fk_ratings_trip;

-- LIKE copies columns, NOT NULL settings, defaults, and CHECK constraints.
-- Primary/foreign keys are deliberately defined below for the partitioned
-- design; LIKE does not copy foreign keys.
CREATE TABLE uber.trips_partitioned_new
    (LIKE uber.trips INCLUDING DEFAULTS INCLUDING CONSTRAINTS)
PARTITION BY RANGE (requested_at);

-- The partition key must be included in the primary key.
ALTER TABLE uber.trips_partitioned_new
    ADD CONSTRAINT trips_partitioned_new_pkey
    PRIMARY KEY (trip_id, requested_at);

-- Recreate the trips-to-dimension foreign keys on the new parent.
ALTER TABLE uber.trips_partitioned_new
    ADD CONSTRAINT fk_trips_partitioned_rider
    FOREIGN KEY (rider_id) REFERENCES uber.riders(rider_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_trips_partitioned_driver
    FOREIGN KEY (driver_id) REFERENCES uber.drivers(driver_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_trips_partitioned_vehicle
    FOREIGN KEY (vehicle_id) REFERENCES uber.vehicles(vehicle_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_trips_partitioned_city
    FOREIGN KEY (city_id) REFERENCES uber.cities(city_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_trips_partitioned_promo
    FOREIGN KEY (promo_code) REFERENCES uber.promo_codes(promo_code) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_trips_partitioned_vehicle_driver
    FOREIGN KEY (vehicle_id, driver_id)
    REFERENCES uber.vehicles(vehicle_id, driver_id) ON DELETE RESTRICT;

-- Build one partition per calendar month, from the actual minimum to maximum
-- requested_at in the loaded large dataset. A DEFAULT partition catches dates
-- outside the current range (for example, future trips).
DO $$
DECLARE
    v_month_start TIMESTAMPTZ;
    v_max_month   TIMESTAMPTZ;
    v_month_end   TIMESTAMPTZ;
    v_partition   TEXT;
BEGIN
    SELECT date_trunc('month', min(requested_at)),
           date_trunc('month', max(requested_at))
    INTO v_month_start, v_max_month
    FROM uber.trips;

    IF v_month_start IS NULL OR v_max_month IS NULL THEN
        RAISE EXCEPTION 'Could not determine requested_at range for trips.';
    END IF;

    -- Keep the maximum month in a separate variable. Do not overwrite it
    -- while calculating each partition's upper boundary.
    WHILE v_month_start <= v_max_month LOOP
        v_month_end := v_month_start + INTERVAL '1 month';
        v_partition := 'trips_' || to_char(v_month_start, 'YYYY_MM');

        EXECUTE format(
            'CREATE TABLE uber.%I PARTITION OF uber.trips_partitioned_new
             FOR VALUES FROM (%L) TO (%L)',
            v_partition, v_month_start, v_month_end
        );

        v_month_start := v_month_end;
    END LOOP;
END
$$;

CREATE TABLE uber.trips_default
    PARTITION OF uber.trips_partitioned_new DEFAULT;

-- Move every row to its month partition. Column order is unchanged by LIKE.
INSERT INTO uber.trips_partitioned_new
SELECT *
FROM uber.trips
ORDER BY requested_at, trip_id;

-- The original child FKs were dropped above, so the old table can now be
-- replaced without CASCADE. If another table references trips, this DROP
-- fails safely and the transaction rolls back.
DROP TABLE uber.trips;
ALTER TABLE uber.trips_partitioned_new RENAME TO trips;

-- Restore referential integrity using the composite partition-aware key.
ALTER TABLE uber.payments
    ADD CONSTRAINT fk_payments_trip_partitioned
    FOREIGN KEY (trip_id, requested_at)
    REFERENCES uber.trips(trip_id, requested_at)
    ON DELETE RESTRICT;

ALTER TABLE uber.ratings
    ADD CONSTRAINT fk_ratings_trip_partitioned
    FOREIGN KEY (trip_id, requested_at)
    REFERENCES uber.trips(trip_id, requested_at)
    ON DELETE RESTRICT;

COMMENT ON COLUMN uber.payments.requested_at IS
    'Copied from trips to support the composite FK required by RANGE partitioning.';
COMMENT ON COLUMN uber.ratings.requested_at IS
    'Copied from trips to support the composite FK required by RANGE partitioning.';

ANALYZE uber.trips;
ANALYZE uber.payments;
ANALYZE uber.ratings;

COMMIT;

-- Show the partitions created.
SELECT
    child.relname AS partition_name,
    pg_get_expr(child.relpartbound, child.oid) AS partition_bound
FROM pg_inherits i
JOIN pg_class parent ON parent.oid = i.inhparent
JOIN pg_class child  ON child.oid = i.inhrelid
JOIN pg_namespace n  ON n.oid = parent.relnamespace
WHERE n.nspname = 'uber'
  AND parent.relname = 'trips'
ORDER BY child.relname;
