# CP-1 — Problem understanding (Uber ride-hailing database)

## Business context
Uber India operates in 10 cities. A ride moves through request, driver assignment, pickup, completion or cancellation. The database must support reliable transactions as well as reporting. The supplied workload contains 25 read queries (`R01`–`R25`) and 5 write queries (`W01`–`W05`).

## Problems, stakeholders and workload category

| Problem | Business need in my words | Stakeholder | Category | Related queries |
|---|---|---|---|---|
| P1 — Your Trips is slow | Retrieve a rider's most recent trips quickly, including frequent riders with many records. | Rider / rider app | Customer-facing / real-time | R01, R15 |
| P2 — Earnings page is slow | Calculate a driver's completed trips and earnings for a requested period without a long wait. | Driver / driver app | Customer-facing / real-time | R02, R07, R19 |
| P3 — Email login fails with capital letters | Find a rider regardless of email-letter casing while keeping login lookup efficient. | User / Identity team | Customer-facing / real-time | R03 |
| P4 — Live dispatch refresh is slow | Fetch the newest city requests and oldest still-active trips quickly enough for frequent dispatch refreshes. | City operations | Customer-facing / real-time operations | R04, R05, W01, W02 |
| P5 — Finance reports time out | Summarize revenue, payment methods and failed payments by month or day. | Finance | Reporting / analytics | R08, R20, R22 |
| P6 — Win-back lists are incorrect or empty | Identify riders and drivers who have not taken a trip recently so campaigns reach the correct people. | Marketing / Driver operations | Reporting / analytics | R09, R10, R18 |
| P7 — Fraud checks scan the whole table | Find unusually long or unusually expensive trips efficiently for review. | Trust & Safety | Reporting / analytics (on-demand fraud analysis) | R24, R25 |
| P8 — Admin pagination slows down | Retrieve a later page of trips without repeatedly processing a large number of earlier rows. | Admin | Customer-facing / real-time operations | R16 |
| P9 — Analytics dashboards are slow | Report surge, cancellations, growth and ratings, while preparing for 10–20× more trips. | Analytics / Leadership | Reporting / analytics | R06, R11, R12, R17, R21, R23 |

## Assumptions

1. `trip_id`, `rider_id`, `driver_id`, `vehicle_id`, `city_id` and `payment_id` are identifiers supplied by the export; they are loaded as-is rather than regenerated.
2. A rider can make many trips; a driver and a vehicle can be associated with many trips over time.
3. A driver can register more than one vehicle. A trip's `driver_id` and `vehicle_id` must refer to the same driver–vehicle pairing.
4. A trip can be requested before a driver is assigned. Therefore driver and vehicle references are nullable together.
5. A completed trip has one payment record in this seed dataset. Payment outcome (`SUCCESS`, `FAILED`, `REFUNDED`) is separate from trip status.
6. Each trip can have up to two ratings: one from the rider and one from the driver. A comment is optional.
7. `rider_rating` and `driver_rating` are supplied summary values. The detailed source ratings remain in `ratings`.
8. `fare_amount` is retained as the historical fare on the trip; it is not recalculated from today's city rates when prices change.
9. CSV timestamps include the `+05:30` offset and are stored as `TIMESTAMPTZ`.

The categories above follow the user-facing/operational versus reporting distinction in the problem descriptions. P7 is operational fraud review rather than a periodic dashboard report.
