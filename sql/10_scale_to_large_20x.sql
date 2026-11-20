-- CP-4 helper: deterministic 20x synthetic scale-up of the official seed data
-- Used ONLY when faculty large_data.zip is unavailable, on a fresh uber_large DB
-- after sql/01_schema.sql and sql/02_load_data.sql (BEFORE 08_partitioning.sql).
-- Preserves batch 0 verbatim and enforces every CP-1 PK, UNIQUE, FK, and CHECK.

\set ON_ERROR_STOP on
SET TIME ZONE 'Asia/Kolkata';
SET search_path TO uber, public;

DO $$
DECLARE
    v_trip_count   BIGINT;
    v_max_rider    INTEGER;
    v_max_driver   INTEGER;
    v_max_vehicle  INTEGER;
    v_max_trip     INTEGER;
    v_max_payment  INTEGER;
BEGIN
    IF current_database() IN ('uber_cp1', 'uber_cp4_partition_test') THEN
        RAISE EXCEPTION 'Refusing to run 20x generator on protected database %.', current_database();
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_partitioned_table WHERE partrelid = 'uber.trips'::regclass
    ) THEN
        RAISE EXCEPTION 'Run 10_scale_to_large_20x.sql BEFORE 08_partitioning.sql.';
    END IF;

    SELECT count(*) INTO v_trip_count FROM uber.trips;
    IF v_trip_count <> 300000 THEN
        RAISE EXCEPTION 'Expected 300000 seed trips before scaling, found %.', v_trip_count;
    END IF;

    SELECT max(rider_id)   INTO v_max_rider   FROM uber.riders;
    SELECT max(driver_id)  INTO v_max_driver  FROM uber.drivers;
    SELECT max(vehicle_id) INTO v_max_vehicle FROM uber.vehicles;
    SELECT max(trip_id)    INTO v_max_trip    FROM uber.trips;
    SELECT max(payment_id) INTO v_max_payment FROM uber.payments;

    RAISE NOTICE 'Scaling riders to 20x...';
    INSERT INTO uber.riders (
        rider_id, full_name, email, phone, home_city_id,
        signup_date, rider_rating, is_active
    )
    SELECT
        r.rider_id + g * v_max_rider,
        r.full_name,
        CASE
            WHEN strpos(r.email, '@') > 0
                THEN regexp_replace(r.email, '@', '_b' || lpad(g::text, 2, '0') || '@')
            ELSE r.email || '_b' || lpad(g::text, 2, '0')
        END,
        'R' || lpad(g::text, 2, '0') || '-' || lpad(r.rider_id::text, 7, '0'),
        r.home_city_id,
        r.signup_date,
        r.rider_rating,
        r.is_active
    FROM uber.riders r
    CROSS JOIN generate_series(1, 19) AS g;

    RAISE NOTICE 'Scaling drivers to 20x...';
    INSERT INTO uber.drivers (
        driver_id, full_name, phone, license_no, city_id,
        joined_on, driver_rating, status
    )
    SELECT
        d.driver_id + g * v_max_driver,
        d.full_name,
        'D' || lpad(g::text, 2, '0') || '-' || lpad(d.driver_id::text, 7, '0'),
        'DLB' || lpad(g::text, 2, '0') || '-' || lpad(d.driver_id::text, 7, '0'),
        d.city_id,
        d.joined_on,
        d.driver_rating,
        d.status
    FROM uber.drivers d
    CROSS JOIN generate_series(1, 19) AS g;

    RAISE NOTICE 'Scaling vehicles to 20x...';
    INSERT INTO uber.vehicles (
        vehicle_id, driver_id, registration_no, make, model,
        manufacture_year, vehicle_type, seat_capacity
    )
    SELECT
        v.vehicle_id + g * v_max_vehicle,
        v.driver_id  + g * v_max_driver,
        'V' || lpad(g::text, 2, '0') || '-' || lpad(v.vehicle_id::text, 7, '0'),
        v.make,
        v.model,
        v.manufacture_year,
        v.vehicle_type,
        v.seat_capacity
    FROM uber.vehicles v
    CROSS JOIN generate_series(1, 19) AS g;

    RAISE NOTICE 'Scaling trips to 20x (6,000,000 rows)...';
    INSERT INTO uber.trips (
        trip_id, rider_id, driver_id, vehicle_id, city_id, promo_code,
        requested_at, pickup_at, dropoff_at,
        pickup_lat, pickup_lng, drop_lat, drop_lng,
        distance_km, duration_min, surge_multiplier, fare_amount, status
    )
    SELECT
        t.trip_id  + g * v_max_trip,
        t.rider_id + g * v_max_rider,
        CASE WHEN t.driver_id  IS NOT NULL THEN t.driver_id  + g * v_max_driver  END,
        CASE WHEN t.vehicle_id IS NOT NULL THEN t.vehicle_id + g * v_max_vehicle END,
        t.city_id,
        t.promo_code,
        t.requested_at,
        t.pickup_at,
        t.dropoff_at,
        t.pickup_lat,
        t.pickup_lng,
        t.drop_lat,
        t.drop_lng,
        t.distance_km,
        t.duration_min,
        t.surge_multiplier,
        t.fare_amount,
        t.status
    FROM uber.trips t
    CROSS JOIN generate_series(1, 19) AS g;

    RAISE NOTICE 'Scaling payments to 20x (~4.92M rows)...';
    INSERT INTO uber.payments (
        payment_id, trip_id, amount, method, payment_status, paid_at
    )
    SELECT
        p.payment_id + g * v_max_payment,
        p.trip_id    + g * v_max_trip,
        p.amount,
        p.method,
        p.payment_status,
        p.paid_at
    FROM uber.payments p
    CROSS JOIN generate_series(1, 19) AS g;

    RAISE NOTICE 'Scaling ratings to 20x (~6.14M rows)...';
    INSERT INTO uber.ratings (
        trip_id, rated_by, stars, comment, created_at
    )
    SELECT
        r.trip_id + g * v_max_trip,
        r.rated_by,
        r.stars,
        r.comment,
        r.created_at
    FROM uber.ratings r
    CROSS JOIN generate_series(1, 19) AS g;

    RAISE NOTICE '20x synthetic scale-up complete.';
END
$$;

ANALYZE;
