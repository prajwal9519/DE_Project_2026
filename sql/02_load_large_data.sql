-- Run this file from the project root (the directory containing large_data/).
-- Empty CSV fields are imported as SQL NULL by PostgreSQL COPY.
\set ON_ERROR_STOP on
SET search_path TO uber, public;

-- Load parent/master tables before tables that reference them.
\copy uber.cities (city_id, city_name, state, base_fare, per_km_rate, per_min_rate, launched_on) FROM 'large_data/cities.csv' WITH (FORMAT csv, HEADER true)
\copy uber.riders (rider_id, full_name, email, phone, home_city_id, signup_date, rider_rating, is_active) FROM 'large_data/riders.csv' WITH (FORMAT csv, HEADER true)
\copy uber.drivers (driver_id, full_name, phone, license_no, city_id, joined_on, driver_rating, status) FROM 'large_data/drivers.csv' WITH (FORMAT csv, HEADER true)
\copy uber.vehicles (vehicle_id, driver_id, registration_no, make, model, manufacture_year, vehicle_type, seat_capacity) FROM 'large_data/vehicles.csv' WITH (FORMAT csv, HEADER true)
\copy uber.promo_codes (promo_code, discount_pct, max_discount, valid_from, valid_to, is_active) FROM 'large_data/promo_codes.csv' WITH (FORMAT csv, HEADER true)
\copy uber.trips (trip_id, rider_id, driver_id, vehicle_id, city_id, promo_code, requested_at, pickup_at, dropoff_at, pickup_lat, pickup_lng, drop_lat, drop_lng, distance_km, duration_min, surge_multiplier, fare_amount, status) FROM 'large_data/trips.csv' WITH (FORMAT csv, HEADER true)
\copy uber.payments (payment_id, trip_id, amount, method, payment_status, paid_at) FROM 'large_data/payments.csv' WITH (FORMAT csv, HEADER true)
\copy uber.ratings (trip_id, rated_by, stars, comment, created_at) FROM 'large_data/ratings.csv' WITH (FORMAT csv, HEADER true)

ANALYZE uber.cities;
ANALYZE uber.riders;
ANALYZE uber.drivers;
ANALYZE uber.vehicles;
ANALYZE uber.promo_codes;
ANALYZE uber.trips;
ANALYZE uber.payments;
ANALYZE uber.ratings;

-- Expected counts are documented in docs/02_schema_design.md.
SELECT 'cities' AS table_name, COUNT(*) AS rows FROM uber.cities
UNION ALL SELECT 'riders', COUNT(*) FROM uber.riders
UNION ALL SELECT 'drivers', COUNT(*) FROM uber.drivers
UNION ALL SELECT 'vehicles', COUNT(*) FROM uber.vehicles
UNION ALL SELECT 'promo_codes', COUNT(*) FROM uber.promo_codes
UNION ALL SELECT 'trips', COUNT(*) FROM uber.trips
UNION ALL SELECT 'payments', COUNT(*) FROM uber.payments
UNION ALL SELECT 'ratings', COUNT(*) FROM uber.ratings
ORDER BY table_name;
