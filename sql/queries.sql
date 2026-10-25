-- ============================================================
-- Bangkok Airbnb | SQL analysis, sections 03-06 (SQLite)
-- Table: listings_clean
-- Price tiers (THB/night): Budget < 1000 | Mid-range 1000-5000 | Luxury > 5000
-- Rule of thumb: price analysis always filters price_status = 'Valid'
-- ============================================================

-- ============================================================
-- 01. MARKET OVERVIEW
-- ============================================================

-- 01a. How many listings, hosts, and neighbourhoods are in the dataset?
-- How many listings have a valid price?
SELECT
    COUNT(*) AS total_listings,
    COUNT(DISTINCT lc.host_id) AS total_hosts,
    COUNT(DISTINCT lc.neighbourhood) AS total_neighbourhoods,
    COUNT(CASE WHEN lc.price_status = 'Valid' THEN 1 END) AS valid_price_listings
FROM listings_clean lc;


-- 01b. Which neighbourhoods have the most Airbnb listings in this dataset?
SELECT
    lc.neighbourhood,
    COUNT(*) AS total_listings
FROM listings_clean lc
GROUP BY lc.neighbourhood
ORDER BY total_listings DESC
LIMIT 10;


-- 01c. How is the listing supply distributed across room types in Bangkok?
SELECT
    lc.room_type,
    COUNT(*) AS total_listings,
    ROUND(
        COUNT(*) * 100.0 /
        (SELECT COUNT(*) FROM listings_clean),
        2
    ) AS percentage
FROM listings_clean lc
GROUP BY lc.room_type
ORDER BY total_listings DESC;


-- 01d. How do nightly listing prices differ across Bangkok neighbourhoods and room types?
SELECT
    lc.neighbourhood,
    lc.room_type,
    COUNT(*) AS total_listings,
    ROUND(AVG(lc.price), 2) AS avg_price
FROM listings_clean lc
WHERE lc.price_status = 'Valid'
GROUP BY lc.neighbourhood, lc.room_type;


-- 01e. Are listings with longer minimum-stay requirements
-- generally priced differently from listings with shorter requirements?
WITH ranked AS (
    SELECT
        stay_category,
        price,
        ROW_NUMBER() OVER (
            PARTITION BY stay_category
            ORDER BY price
        ) AS price_rank,
        COUNT(*) OVER (
            PARTITION BY stay_category
        ) AS category_count
    FROM listings_clean
    WHERE price_status = 'Valid'
)
SELECT
    stay_category,
    COUNT(*) AS total_listings,
    ROUND(AVG(price), 2) AS average_price,
    ROUND(
        AVG(
            CASE
                WHEN price_rank IN (
                    (category_count + 1) / 2,
                    (category_count + 2) / 2
                )
                THEN price
            END
        ),
        2
    ) AS median_price
FROM ranked
GROUP BY stay_category
ORDER BY median_price DESC;


-- ============================================================
-- 02. PRICING ANALYSIS
-- Price tiers (THB/night):
-- Budget < 1000 | Mid-range 1000-5000 | Luxury > 5000
-- Rule: Price analysis always filters price_status = 'Valid'
-- ============================================================

-- 02a. What is the price range (min, max, avg) for each room type?
SELECT
    lc.room_type,
    MIN(lc.price) AS minimum_price,
    MAX(lc.price) AS maximum_price,
    ROUND(AVG(lc.price), 2) AS avg_price
FROM listings_clean lc
WHERE lc.price_status = 'Valid'
GROUP BY lc.room_type
ORDER BY avg_price DESC;


-- 02b. Which neighbourhoods are the most expensive and most affordable on average?
-- Only valid prices; minimum 20 listings per neighbourhood
SELECT *
FROM (
    SELECT
        'Most expensive' AS category,
        lc.neighbourhood,
        COUNT(*) AS total_listings,
        ROUND(AVG(lc.price), 2) AS avg_price
    FROM listings_clean lc
    WHERE lc.price_status = 'Valid'
    GROUP BY lc.neighbourhood
    HAVING COUNT(*) >= 20
    ORDER BY avg_price DESC
    LIMIT 5
)
UNION ALL
SELECT *
FROM (
    SELECT
        'Most affordable' AS category,
        lc.neighbourhood,
        COUNT(*) AS total_listings,
        ROUND(AVG(lc.price), 2) AS avg_price
    FROM listings_clean lc
    WHERE lc.price_status = 'Valid'
    GROUP BY lc.neighbourhood
    HAVING COUNT(*) >= 20
    ORDER BY avg_price ASC
    LIMIT 5
);


-- 02c. Which neighbourhoods have the highest proportion of luxury listings?
-- Show price-tier counts and only neighbourhoods where luxury listings
-- account for more than 10% of valid-price listings.
-- Minimum 20 valid-price listings per neighbourhood
SELECT
    lc.neighbourhood,
    COUNT(*) AS total_listings,
    COUNT(CASE WHEN lc.price < 1000 THEN 1 END) AS budget,
    COUNT(CASE WHEN lc.price BETWEEN 1000 AND 5000 THEN 1 END) AS mid_range,
    COUNT(CASE WHEN lc.price > 5000 THEN 1 END) AS luxury,
    ROUND(
        COUNT(CASE WHEN lc.price > 5000 THEN 1 END)
        * 100.0 / COUNT(*),
        2
    ) AS luxury_pct
FROM listings_clean lc
WHERE lc.price_status = 'Valid'
GROUP BY lc.neighbourhood
HAVING COUNT(*) >= 20
   AND COUNT(CASE WHEN lc.price > 5000 THEN 1 END)
       * 100.0 / COUNT(*) > 10
ORDER BY luxury_pct DESC;


-- 02d. Which room type has the highest median price,
-- and how does it compare to the average price?
-- SQLite has no built-in MEDIAN(), so use window functions.
WITH ranked AS (
    SELECT
        lc.room_type,
        lc.price,
        ROW_NUMBER() OVER (
            PARTITION BY lc.room_type
            ORDER BY lc.price
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY lc.room_type
        ) AS cnt,
        AVG(lc.price) OVER (
            PARTITION BY lc.room_type
        ) AS avg_price
    FROM listings_clean lc
    WHERE lc.price_status = 'Valid'
)
SELECT
    room_type,
    MAX(cnt) AS total_listings,
    ROUND(AVG(price), 2) AS median_price,
    ROUND(MAX(avg_price), 2) AS avg_price
FROM ranked
WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
GROUP BY room_type
ORDER BY median_price DESC;

-- ============================================================
-- 03. HOST ANALYSIS
-- ============================================================

-- 03a. How many hosts manage more than 1 listing vs hosts with only 1 listing?
-- Two-stage aggregation: (1) listings per host, (2) count hosts per group
WITH host_listings AS (
    SELECT lc.host_id,
           COUNT(*) AS listing_count
    FROM listings_clean lc
    GROUP BY lc.host_id
)
SELECT COUNT(CASE WHEN listing_count > 1 THEN 1 END) AS multi_listing_hosts,
       COUNT(CASE WHEN listing_count = 1 THEN 1 END) AS single_listing_hosts,
       COUNT(*) AS total_hosts,
       ROUND(COUNT(CASE WHEN listing_count > 1 THEN 1 END) * 100.0 / COUNT(*), 2) AS multi_listing_pct
FROM host_listings;


-- 03b. What percentage of total listings belong to hosts with 10+ listings ("power hosts")?
WITH host_listings AS (
    SELECT lc.host_id,
           COUNT(*) AS listing_count
    FROM listings_clean lc
    GROUP BY lc.host_id
)
SELECT COUNT(CASE WHEN listing_count >= 10 THEN 1 END) AS power_hosts,
       SUM(CASE WHEN listing_count >= 10 THEN listing_count ELSE 0 END) AS listings_owned_by_power_hosts,
       SUM(listing_count) AS total_listings,
       ROUND(SUM(CASE WHEN listing_count >= 10 THEN listing_count ELSE 0 END) * 100.0
             / SUM(listing_count), 2) AS pct_of_all_listings
FROM host_listings;


-- 03c. Which host manages listings across the most different neighbourhoods?
SELECT lc.host_id,
       COUNT(DISTINCT lc.neighbourhood) AS distinct_neighbourhoods,
       COUNT(*) AS total_listings
FROM listings_clean lc
GROUP BY lc.host_id
ORDER BY distinct_neighbourhoods DESC, total_listings DESC
LIMIT 5;


-- 03d. Do multi-listing hosts price differently from single-listing hosts?
SELECT CASE WHEN lc.calculated_host_listings_count > 1
            THEN 'Multi-listing host'
            ELSE 'Single-listing host'
       END AS host_type,
       COUNT(*) AS total_listings,
       ROUND(AVG(lc.price), 2) AS avg_price
FROM listings_clean lc
WHERE lc.price_status = 'Valid'
GROUP BY host_type;


-- ============================================================
-- 04. AVAILABILITY & OCCUPANCY SIGNALS
-- ============================================================

-- 04a. What percentage of listings are available less than 30 days a year?
-- (note: includes availability_365 = 0)
SELECT COUNT(CASE WHEN lc.availability_365 < 30 THEN 1 END) AS low_availability_listings,
       COUNT(*) AS total_listings,
       ROUND(COUNT(CASE WHEN lc.availability_365 < 30 THEN 1 END) * 100.0 / COUNT(*), 2) AS pct_low_availability
FROM listings_clean lc;


-- 04b. High availability (>300 days) vs low availability (<30 days): does scarcity correlate with price?
SELECT CASE WHEN lc.availability_365 > 300 THEN 'High availability (>300)'
            WHEN lc.availability_365 < 30  THEN 'Low availability (<30)'
       END AS availability_group,
       COUNT(*) AS total_listings,
       ROUND(AVG(lc.price), 2) AS avg_price
FROM listings_clean lc
WHERE lc.price_status = 'Valid'
  AND (lc.availability_365 > 300 OR lc.availability_365 < 30)
GROUP BY availability_group;


-- 04c. Which neighbourhoods have the highest proportion of "No availability" listings?
-- (min 20 listings to avoid tiny-sample bias)
SELECT lc.neighbourhood,
       COUNT(*) AS total_listings,
       COUNT(CASE WHEN lc.availability_status = 'No availability' THEN 1 END) AS no_availability,
       ROUND(COUNT(CASE WHEN lc.availability_status = 'No availability' THEN 1 END) * 100.0 / COUNT(*), 2) AS no_availability_pct
FROM listings_clean lc
GROUP BY lc.neighbourhood
HAVING COUNT(*) >= 20
ORDER BY no_availability_pct DESC
LIMIT 10;


-- 04d. Relationship between minimum_nights and availability_365 (via stay_category)
SELECT lc.stay_category,
       COUNT(*) AS total_listings,
       ROUND(AVG(lc.availability_365), 1) AS avg_availability_days,
       ROUND(COUNT(CASE WHEN lc.availability_status = 'No availability' THEN 1 END) * 100.0 / COUNT(*), 2) AS no_availability_pct
FROM listings_clean lc
GROUP BY lc.stay_category
ORDER BY CASE lc.stay_category
             WHEN 'Short stay' THEN 1
             WHEN 'Extended stay' THEN 2
             WHEN 'Monthly/long stay' THEN 3
             WHEN 'Very long stay' THEN 4
         END;


-- ============================================================
-- 05. GUEST ENGAGEMENT (REVIEWS)
-- ============================================================

-- 05a. Which neighbourhoods have the highest average number_of_reviews per listing?
-- (proxy for popularity; min 20 listings)
SELECT lc.neighbourhood,
       COUNT(*) AS total_listings,
       ROUND(AVG(lc.number_of_reviews), 2) AS avg_reviews_per_listing
FROM listings_clean lc
GROUP BY lc.neighbourhood
HAVING COUNT(*) >= 20
ORDER BY avg_reviews_per_listing DESC
LIMIT 10;


-- 05b. What percentage of listings have never received a review?
SELECT COUNT(CASE WHEN lc.number_of_reviews = 0 THEN 1 END) AS never_reviewed,
       COUNT(*) AS total_listings,
       ROUND(COUNT(CASE WHEN lc.number_of_reviews = 0 THEN 1 END) * 100.0 / COUNT(*), 2) AS never_reviewed_pct
FROM listings_clean lc;


-- 05c. Among listings with at least 1 review, average reviews_per_month by room_type
SELECT lc.room_type,
       COUNT(*) AS reviewed_listings,
       ROUND(AVG(lc.reviews_per_month), 3) AS avg_reviews_per_month
FROM listings_clean lc
WHERE lc.number_of_reviews >= 1
GROUP BY lc.room_type
ORDER BY avg_reviews_per_month DESC;


-- 05d. Listings with a big drop in recent activity:
-- plenty of review history (>= 50 total) but zero reviews in the last 12 months
SELECT lc.id,
       lc.name,
       lc.neighbourhood,
       lc.number_of_reviews,
       lc.number_of_reviews_ltm,
       lc.last_review
FROM listings_clean lc
WHERE lc.number_of_reviews >= 50
  AND lc.number_of_reviews_ltm = 0
ORDER BY lc.number_of_reviews DESC
LIMIT 20;

-- 05d (summary). How many listings fall in that group?
SELECT COUNT(CASE WHEN lc.number_of_reviews_ltm = 0 THEN 1 END) AS no_recent_reviews,
       COUNT(*) AS listings_with_50plus_reviews,
       ROUND(COUNT(CASE WHEN lc.number_of_reviews_ltm = 0 THEN 1 END) * 100.0 / COUNT(*), 2) AS pct
FROM listings_clean lc
WHERE lc.number_of_reviews >= 50;


-- ============================================================
-- 06. CROSS-CUTTING / COMBINED INSIGHTS
-- ============================================================

-- 06a. Relationship between price and reviews: do cheaper listings get reviewed more?
-- (note: reviews_per_month = 0 for never-reviewed listings, so it includes them)
SELECT CASE WHEN lc.price < 1000 THEN '1. Budget'
            WHEN lc.price BETWEEN 1000 AND 5000 THEN '2. Mid-range'
            WHEN lc.price > 5000 THEN '3. Luxury'
       END AS price_tier,
       COUNT(*) AS total_listings,
       ROUND(AVG(lc.number_of_reviews), 2) AS avg_total_reviews,
       ROUND(AVG(lc.reviews_per_month), 3) AS avg_reviews_per_month
FROM listings_clean lc
WHERE lc.price_status = 'Valid'
GROUP BY price_tier
ORDER BY price_tier;


-- 06b. Best "value" neighbourhoods: below-average price but above-average reviews_per_month
-- (compared against the citywide average; min 20 valid-price listings)
WITH neighbourhood_stats AS (
    SELECT lc.neighbourhood,
           COUNT(*) AS total_listings,
           AVG(lc.price) AS avg_price,
           AVG(lc.reviews_per_month) AS avg_rpm
    FROM listings_clean lc
    WHERE lc.price_status = 'Valid'
    GROUP BY lc.neighbourhood
    HAVING COUNT(*) >= 20
),
city_stats AS (
    SELECT AVG(lc.price) AS city_avg_price,
           AVG(lc.reviews_per_month) AS city_avg_rpm
    FROM listings_clean lc
    WHERE lc.price_status = 'Valid'
)
SELECT ns.neighbourhood,
       ns.total_listings,
       ROUND(ns.avg_price, 2) AS avg_price,
       ROUND(ns.avg_rpm, 3) AS avg_reviews_per_month,
       ROUND(cs.city_avg_price, 2) AS city_avg_price,
       ROUND(cs.city_avg_rpm, 3) AS city_avg_rpm
FROM neighbourhood_stats ns
CROSS JOIN city_stats cs
WHERE ns.avg_price < cs.city_avg_price
  AND ns.avg_rpm > cs.city_avg_rpm
ORDER BY ns.avg_rpm DESC;


-- 06c. Rank room types by "demand score" (AVG reviews_per_month) and compare with price rank
WITH room_stats AS (
    SELECT lc.room_type,
           COUNT(*) AS total_listings,
           AVG(lc.reviews_per_month) AS demand_score,
           AVG(lc.price) AS avg_price
    FROM listings_clean lc
    WHERE lc.price_status = 'Valid'
    GROUP BY lc.room_type
)
SELECT room_type,
       total_listings,
       ROUND(demand_score, 3) AS demand_score,
       ROUND(avg_price, 2) AS avg_price,
       RANK() OVER (ORDER BY demand_score DESC) AS demand_rank,
       RANK() OVER (ORDER BY avg_price DESC) AS price_rank
FROM room_stats
ORDER BY demand_rank;


-- 06d. Neighbourhoods that are BOTH top 10 by supply (listing count) AND top 10 by average price
WITH neighbourhood_stats AS (
    SELECT lc.neighbourhood,
           COUNT(*) AS total_listings,
           AVG(lc.price) AS avg_price
    FROM listings_clean lc
    WHERE lc.price_status = 'Valid'
    GROUP BY lc.neighbourhood
),
ranked AS (
    SELECT neighbourhood,
           total_listings,
           avg_price,
           RANK() OVER (ORDER BY total_listings DESC) AS supply_rank,
           RANK() OVER (ORDER BY avg_price DESC) AS price_rank
    FROM neighbourhood_stats
)
SELECT neighbourhood,
       total_listings,
       ROUND(avg_price, 2) AS avg_price,
       supply_rank,
       price_rank
FROM ranked
WHERE supply_rank <= 10
  AND price_rank <= 10
ORDER BY supply_rank;