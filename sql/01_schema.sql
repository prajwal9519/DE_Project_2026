-- CP-1 Phase 2: Uber ride-hailing schema
-- Run against an EMPTY database. No tuning indexes are created in this phase.
\set ON_ERROR_STOP on

CREATE SCHEMA uber;
SET search_path TO uber, public;

-- City master data
CREATE TABLE uber.cities (
    city_id       INTEGER       PRIMARY KEY,
    city_name     VARCHAR(40)  NOT NULL UNIQUE,
    state         VARCHAR(50)  NOT NULL,
    base_fare     NUMERIC(8,2) NOT NULL CHECK (base_fare > 0),
    per_km_rate   NUMERIC(8,2) NOT NULL CHECK (per_km_rate > 0),
    per_min_rate  NUMERIC(8,2) NOT NULL CHECK (per_min_rate >= 0),
    launched_on   DATE          NOT NULL
);

-- Riders can have no summary rating yet, so rider_rating is nullable.
CREATE TABLE uber.riders (
    rider_id      INTEGER       PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    email         VARCHAR(254) NOT NULL UNIQUE,
    phone         VARCHAR(20)  NOT NULL UNIQUE,
    home_city_id  INTEGER       NOT NULL,
    signup_date   DATE          NOT NULL,
    rider_rating  NUMERIC(2,1)  CHECK (rider_rating BETWEEN 1.0 AND 5.0),
    is_active     BOOLEAN       NOT NULL,
    CONSTRAINT fk_riders_home_city
        FOREIGN KEY (home_city_id) REFERENCES uber.cities(city_id) ON DELETE RESTRICT
);

-- Driver status is distinct from trip status.
CREATE TABLE uber.drivers (
    driver_id     INTEGER       PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    phone         VARCHAR(20)  NOT NULL UNIQUE,
    license_no    VARCHAR(30)  NOT NULL UNIQUE,
    city_id       INTEGER       NOT NULL,
    joined_on     DATE          NOT NULL,
    driver_rating NUMERIC(2,1)  NOT NULL CHECK (driver_rating BETWEEN 1.0 AND 5.0),
    status        VARCHAR(15)   NOT NULL CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')),
    CONSTRAINT fk_drivers_city
        FOREIGN KEY (city_id) REFERENCES uber.cities(city_id) ON DELETE RESTRICT
);

-- A driver may register multiple vehicles. The pair UNIQUE supports a
-- composite FK from trips so a trip cannot pair a driver with another
-- driver's vehicle.
CREATE TABLE uber.vehicles (
    vehicle_id       INTEGER      PRIMARY KEY,
    driver_id        INTEGER      NOT NULL,
    registration_no  VARCHAR(20)  NOT NULL UNIQUE,
    make             VARCHAR(40)  NOT NULL,
    model            VARCHAR(40)  NOT NULL,
    manufacture_year SMALLINT     NOT NULL CHECK (manufacture_year BETWEEN 1900 AND 2100),
    vehicle_type     VARCHAR(10)  NOT NULL CHECK (vehicle_type IN ('MINI', 'SEDAN', 'SUV', 'AUTO', 'BIKE')),
    seat_capacity    SMALLINT     NOT NULL CHECK (seat_capacity > 0),
    CONSTRAINT fk_vehicles_driver
        FOREIGN KEY (driver_id) REFERENCES uber.drivers(driver_id) ON DELETE RESTRICT,
    CONSTRAINT uq_vehicles_vehicle_driver UNIQUE (vehicle_id, driver_id),
    CONSTRAINT ck_vehicle_type_capacity CHECK (
        (vehicle_type = 'BIKE' AND seat_capacity = 1) OR
        (vehicle_type = 'AUTO' AND seat_capacity = 3) OR
        (vehicle_type IN ('MINI', 'SEDAN') AND seat_capacity = 4) OR
        (vehicle_type = 'SUV' AND seat_capacity IN (6, 7))
    )
);

CREATE TABLE uber.promo_codes (
    promo_code    VARCHAR(20)  PRIMARY KEY,
    discount_pct  NUMERIC(5,2) NOT NULL CHECK (discount_pct BETWEEN 1 AND 100),
    max_discount  NUMERIC(10,2) NOT NULL CHECK (max_discount > 0),
    valid_from    DATE         NOT NULL,
    valid_to      DATE         NOT NULL,
    is_active     BOOLEAN      NOT NULL,
    CONSTRAINT ck_promo_validity CHECK (valid_to >= valid_from)
);

-- Nullable columns reflect trips that are requested, accepted, ongoing or cancelled.
CREATE TABLE uber.trips (
    trip_id         INTEGER        PRIMARY KEY,
    rider_id        INTEGER        NOT NULL,
    driver_id       INTEGER,
    vehicle_id      INTEGER,
    city_id         INTEGER        NOT NULL,
    promo_code      VARCHAR(20),
    requested_at    TIMESTAMPTZ    NOT NULL,
    pickup_at       TIMESTAMPTZ,
    dropoff_at      TIMESTAMPTZ,
    pickup_lat      NUMERIC(9,6)   NOT NULL CHECK (pickup_lat BETWEEN -90 AND 90),
    pickup_lng      NUMERIC(9,6)   NOT NULL CHECK (pickup_lng BETWEEN -180 AND 180),
    drop_lat        NUMERIC(9,6)   NOT NULL CHECK (drop_lat BETWEEN -90 AND 90),
    drop_lng        NUMERIC(9,6)   NOT NULL CHECK (drop_lng BETWEEN -180 AND 180),
    distance_km     NUMERIC(7,2)   CHECK (distance_km >= 0),
    duration_min    SMALLINT       CHECK (duration_min >= 0),
    surge_multiplier NUMERIC(4,2)  NOT NULL CHECK (surge_multiplier >= 1.00),
    fare_amount     NUMERIC(10,2)  CHECK (fare_amount >= 0),
    status          VARCHAR(25)    NOT NULL CHECK (status IN (
        'REQUESTED', 'ACCEPTED', 'ONGOING', 'COMPLETED',
        'CANCELLED_BY_RIDER', 'CANCELLED_BY_DRIVER'
    )),
    CONSTRAINT fk_trips_rider
        FOREIGN KEY (rider_id) REFERENCES uber.riders(rider_id) ON DELETE RESTRICT,
    CONSTRAINT fk_trips_driver
        FOREIGN KEY (driver_id) REFERENCES uber.drivers(driver_id) ON DELETE RESTRICT,
    CONSTRAINT fk_trips_vehicle
        FOREIGN KEY (vehicle_id) REFERENCES uber.vehicles(vehicle_id) ON DELETE RESTRICT,
    CONSTRAINT fk_trips_city
        FOREIGN KEY (city_id) REFERENCES uber.cities(city_id) ON DELETE RESTRICT,
    CONSTRAINT fk_trips_promo
        FOREIGN KEY (promo_code) REFERENCES uber.promo_codes(promo_code) ON DELETE RESTRICT,
    CONSTRAINT fk_trips_vehicle_driver
        FOREIGN KEY (vehicle_id, driver_id)
        REFERENCES uber.vehicles(vehicle_id, driver_id) ON DELETE RESTRICT,
    CONSTRAINT ck_trip_driver_vehicle_pair
        CHECK ((driver_id IS NULL) = (vehicle_id IS NULL)),
    CONSTRAINT ck_trip_pickup_after_request
        CHECK (pickup_at IS NULL OR pickup_at >= requested_at),
    CONSTRAINT ck_trip_dropoff_after_pickup
        CHECK (dropoff_at IS NULL OR (pickup_at IS NOT NULL AND dropoff_at >= pickup_at)),
    CONSTRAINT ck_trip_requested_fields CHECK (
        status <> 'REQUESTED' OR
        (driver_id IS NULL AND vehicle_id IS NULL AND pickup_at IS NULL AND
         dropoff_at IS NULL AND distance_km IS NULL AND duration_min IS NULL AND fare_amount IS NULL)
    ),
    CONSTRAINT ck_trip_accepted_fields CHECK (
        status <> 'ACCEPTED' OR
        (driver_id IS NOT NULL AND vehicle_id IS NOT NULL AND pickup_at IS NULL AND
         dropoff_at IS NULL AND distance_km IS NULL AND duration_min IS NULL AND fare_amount IS NULL)
    ),
    CONSTRAINT ck_trip_ongoing_fields CHECK (
        status <> 'ONGOING' OR
        (driver_id IS NOT NULL AND vehicle_id IS NOT NULL AND pickup_at IS NOT NULL AND
         dropoff_at IS NULL AND distance_km IS NULL AND duration_min IS NULL AND fare_amount IS NULL)
    ),
    CONSTRAINT ck_trip_completed_fields CHECK (
        status <> 'COMPLETED' OR
        (driver_id IS NOT NULL AND vehicle_id IS NOT NULL AND pickup_at IS NOT NULL AND
         dropoff_at IS NOT NULL AND distance_km IS NOT NULL AND duration_min IS NOT NULL AND fare_amount IS NOT NULL)
    ),
    CONSTRAINT ck_trip_driver_cancel_fields CHECK (
        status <> 'CANCELLED_BY_DRIVER' OR
        (driver_id IS NOT NULL AND vehicle_id IS NOT NULL AND pickup_at IS NULL AND
         dropoff_at IS NULL AND distance_km IS NULL AND duration_min IS NULL AND fare_amount IS NULL)
    ),
    CONSTRAINT ck_trip_rider_cancel_fields CHECK (
        status <> 'CANCELLED_BY_RIDER' OR
        (pickup_at IS NULL AND dropoff_at IS NULL AND distance_km IS NULL AND
         duration_min IS NULL AND fare_amount IS NULL)
    )
);

-- Each completed trip has at most one payment record in this export.
CREATE TABLE uber.payments (
    payment_id     INTEGER        PRIMARY KEY,
    trip_id        INTEGER        NOT NULL UNIQUE,
    amount         NUMERIC(10,2)  NOT NULL CHECK (amount >= 0),
    method         VARCHAR(10)    NOT NULL CHECK (method IN ('UPI', 'CASH', 'CARD', 'WALLET')),
    payment_status VARCHAR(10)    NOT NULL CHECK (payment_status IN ('SUCCESS', 'FAILED', 'REFUNDED')),
    paid_at        TIMESTAMPTZ    NOT NULL,
    CONSTRAINT fk_payments_trip
        FOREIGN KEY (trip_id) REFERENCES uber.trips(trip_id) ON DELETE RESTRICT
);

-- Composite PK: a trip can have one RIDER rating and one DRIVER rating.
CREATE TABLE uber.ratings (
    trip_id    INTEGER      NOT NULL,
    rated_by   VARCHAR(10)  NOT NULL CHECK (rated_by IN ('RIDER', 'DRIVER')),
    stars      SMALLINT     NOT NULL CHECK (stars BETWEEN 1 AND 5),
    comment    TEXT,
    created_at TIMESTAMPTZ  NOT NULL,
    CONSTRAINT pk_ratings PRIMARY KEY (trip_id, rated_by),
    CONSTRAINT fk_ratings_trip
        FOREIGN KEY (trip_id) REFERENCES uber.trips(trip_id) ON DELETE RESTRICT
);

-- No CREATE INDEX statements belong in CP-1. PK/UNIQUE constraints create
-- their own supporting indexes automatically; workload tuning is CP-3.
