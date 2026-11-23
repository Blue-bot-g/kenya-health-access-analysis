USE health_access_kenya_db;

-- Objectives:
--  1. Facility availability by county
--  2. Inpatient capacity
--  3. Level of care (KEPH)
--  4. Ownership mix
--  5. Opening hours / service availability
--  6. Operational status
--  7. Data quality as a finding

-- PART A: Views
--   v_facility
--   v_county_access  
--   v_quality 

DROP VIEW IF EXISTS v_quality;
DROP VIEW IF EXISTS v_county_access;
DROP VIEW IF EXISTS v_facility_owner;   -- superseded by v_facility
DROP VIEW IF EXISTS v_facility;

-- ---------------------------------------------------------------------
-- A1) v_facility
--   * Flags (Yes/No, 1/0, true/false) are all normalised to 1/0 ('Yes' = 0 is TRUE.).
--   * beds / cots / "beds and cots" are parsed to numbers, thousands
--     separators removed ('1,455' -> 1455). 
--   * KEPH level is reduced to a number and a care tier.
-- ---------------------------------------------------------------------
CREATE VIEW v_facility AS
SELECT
    b.facility_code,
    b.facility_name,
    b.county,
    b.county_key,
    b.sub_county,
    b.keph_num,
    CASE WHEN b.keph_num IS NULL THEN 'Unspecified'
         ELSE CONCAT('Level ', b.keph_num) END                    AS keph_level,
    CASE WHEN b.keph_num IN (2, 3) THEN 'Primary care'
         WHEN b.keph_num = 4       THEN 'Hospital'
         WHEN b.keph_num IN (5, 6) THEN 'Referral'
         ELSE 'Unspecified' END                                   AS care_tier,
    b.owner_type,
    b.owner_group,
    b.beds_n,
    b.cots_n,
    COALESCE(b.total_n, 0)                                        AS inpatient_capacity,
    b.open_24h,
    b.open_weekends,
    b.open_holidays,
    b.open_late_night,
    b.operation_status,
    b.is_active,
    b.has_valid_code,
    b.has_registration,
    b.beds_had_separator,
    CASE WHEN b.total_n IS NULL THEN 1 ELSE 0 END                 AS capacity_unparseable,
    CASE WHEN b.beds_n IS NOT NULL AND b.cots_n IS NOT NULL AND b.total_n IS NOT NULL
              AND b.beds_n + b.cots_n <> b.total_n THEN 1 ELSE 0 END AS capacity_components_mismatch,
    CASE WHEN b.county_key IS NULL OR b.county_key IN ('', 'none') THEN 1 ELSE 0 END AS county_missing,
    CASE WHEN b.sub_county IS NULL OR b.sub_county IN ('', 'None') THEN 1 ELSE 0 END AS sub_county_missing,
    CASE WHEN EXISTS (SELECT 1 FROM stg_county_population_clean p
                      WHERE LOWER(TRIM(p.name)) = b.county_key)
         THEN 1 ELSE 0 END                                        AS county_in_census,
    CASE WHEN b.facility_code IS NOT NULL
              AND COUNT(*) OVER (PARTITION BY b.facility_code) > 1
         THEN 1 ELSE 0 END                                        AS is_duplicate_code,
    CASE WHEN COUNT(*) OVER (PARTITION BY b.facility_name, b.county_key) > 1
         THEN 1 ELSE 0 END                                        AS is_duplicate_name_county
FROM (
    SELECT
        CASE WHEN code IS NULL OR TRIM(code) IN ('', 'None') THEN NULL
             ELSE TRIM(code) END                                  AS facility_code,
        CASE WHEN code IS NULL OR TRIM(code) IN ('', 'None') THEN 0 ELSE 1 END AS has_valid_code,
        TRIM(name)                                                AS facility_name,
        TRIM(county)                                              AS county,
        LOWER(TRIM(county))                                       AS county_key,
        TRIM(`sub county`)                                        AS sub_county,
        CAST(REGEXP_SUBSTR(`keph level`, '[0-9]+') AS UNSIGNED)   AS keph_num,
        TRIM(`owner type`)                                        AS owner_type,
        CASE TRIM(`owner type`)
            WHEN 'Ministry of Health'             THEN 'Public'
            WHEN 'Private Practice'               THEN 'Private'
            WHEN 'Faith Based Organization'       THEN 'Faith-based'
            WHEN 'Non-Governmental Organizations' THEN 'NGO'
            ELSE 'Other'
        END                                                       AS owner_group,
        CASE WHEN REPLACE(TRIM(beds), ',', '') REGEXP '^[0-9]+$'
             THEN CAST(REPLACE(TRIM(beds), ',', '') AS UNSIGNED) END   AS beds_n,
        CASE WHEN REPLACE(TRIM(cots), ',', '') REGEXP '^[0-9]+$'
             THEN CAST(REPLACE(TRIM(cots), ',', '') AS UNSIGNED) END   AS cots_n,
        CASE WHEN REPLACE(TRIM(`beds and cots`), ',', '') REGEXP '^[0-9]+$'
             THEN CAST(REPLACE(TRIM(`beds and cots`), ',', '') AS UNSIGNED) END AS total_n,
        CASE WHEN `beds and cots` LIKE '%,%' THEN 1 ELSE 0 END    AS beds_had_separator,
        CASE WHEN LOWER(TRIM(open_whole_day))       IN ('yes','y','1','true') THEN 1 ELSE 0 END AS open_24h,
        CASE WHEN LOWER(TRIM(open_weekends))        IN ('yes','y','1','true') THEN 1 ELSE 0 END AS open_weekends,
        CASE WHEN LOWER(TRIM(open_public_holidays)) IN ('yes','y','1','true') THEN 1 ELSE 0 END AS open_holidays,
        CASE WHEN LOWER(TRIM(open_late_night))      IN ('yes','y','1','true') THEN 1 ELSE 0 END AS open_late_night,
        `operation status`                                        AS operation_status,
        CASE WHEN LOWER(TRIM(closed)) IN ('no','n','0','false')
                  AND LOWER(TRIM(`operation status`)) = 'operational'
             THEN 1 ELSE 0 END                                    AS is_active,
        CASE WHEN registration_number IS NULL
                  OR TRIM(registration_number) IN ('', 'None')
             THEN 0 ELSE 1 END                                    AS has_registration
    FROM stg_hospitals_clean
) b;

-- ---------------------------------------------------------------------
-- A2) v_county_access  (47 rows)
-- ---------------------------------------------------------------------
CREATE VIEW v_county_access AS
SELECT
    c.name                                                        AS county,
    c.population,
    c.land_area_sq_km,
    COUNT(f.county_key)                                           AS facilities,
    COALESCE(SUM(f.inpatient_capacity), 0)                        AS inpatient_capacity,

    -- access metrics
    ROUND(COUNT(f.county_key) * 100000 / NULLIF(c.population, 0), 2)               AS facilities_per_100k,
    ROUND(COUNT(f.county_key) * 1000   / NULLIF(c.land_area_sq_km, 0), 2)          AS facilities_per_1000_sqkm,
    ROUND(COALESCE(SUM(f.inpatient_capacity), 0) * 100000 / NULLIF(c.population, 0), 1) AS beds_per_100k,
    RANK() OVER (ORDER BY COUNT(f.county_key) / NULLIF(c.population, 0) DESC)      AS access_rank,   -- 1 = best served

    -- level of care
    COALESCE(SUM(f.care_tier = 'Primary care'), 0)                AS primary_care_facilities,
    COALESCE(SUM(f.care_tier = 'Hospital'), 0)                    AS hospital_facilities,
    COALESCE(SUM(f.care_tier = 'Referral'), 0)                    AS referral_facilities,
    COALESCE(SUM(f.keph_num = 5), 0)                              AS level_5_facilities,
    COALESCE(SUM(f.keph_num = 6), 0)                              AS level_6_facilities,
    MAX(f.keph_num)                                               AS highest_keph_level,
    ROUND(COALESCE(SUM(f.care_tier = 'Primary care'), 0) * 100000 / NULLIF(c.population, 0), 2) AS primary_care_per_100k,
    ROUND(COALESCE(SUM(f.care_tier = 'Hospital'), 0)     * 100000 / NULLIF(c.population, 0), 2) AS hospital_per_100k,
    ROUND(COALESCE(SUM(f.care_tier = 'Referral'), 0)     * 100000 / NULLIF(c.population, 0), 2) AS referral_per_100k,

    -- opening hours
    ROUND(100 * COALESCE(SUM(f.open_24h), 0)        / NULLIF(COUNT(f.county_key), 0), 1) AS pct_24h,
    ROUND(100 * COALESCE(SUM(f.open_weekends), 0)   / NULLIF(COUNT(f.county_key), 0), 1) AS pct_weekends,
    ROUND(100 * COALESCE(SUM(f.open_holidays), 0)   / NULLIF(COUNT(f.county_key), 0), 1) AS pct_holidays,
    ROUND(100 * COALESCE(SUM(f.open_late_night), 0) / NULLIF(COUNT(f.county_key), 0), 1) AS pct_late_night,
    COALESCE(SUM(CASE WHEN f.open_24h = 1 THEN f.inpatient_capacity END), 0)            AS beds_in_24h_facilities,
    ROUND(100 * COALESCE(SUM(CASE WHEN f.open_24h = 1 THEN f.inpatient_capacity END), 0)
              / NULLIF(SUM(f.inpatient_capacity), 0), 1)                                 AS pct_beds_24h,

    -- ownership mix
    COALESCE(SUM(f.owner_group = 'Public'), 0)                    AS public_facilities,
    COALESCE(SUM(f.owner_group = 'Private'), 0)                   AS private_facilities,
    COALESCE(SUM(f.owner_group = 'Faith-based'), 0)               AS faith_based_facilities,
    COALESCE(SUM(f.owner_group = 'NGO'), 0)                       AS ngo_facilities,
    ROUND(100 * COALESCE(SUM(f.owner_group = 'Public'), 0)  / NULLIF(COUNT(f.county_key), 0), 1) AS pct_public,
    ROUND(100 * COALESCE(SUM(f.owner_group = 'Private'), 0) / NULLIF(COUNT(f.county_key), 0), 1) AS pct_private
FROM stg_county_population_clean c
LEFT JOIN v_facility f
       ON f.county_key = LOWER(TRIM(c.name))
      AND f.is_active = 1
GROUP BY c.name, c.population, c.land_area_sq_km;

-- ---------------------------------------------------------------------
-- A3) v_quality  (long format: category, issue, rows_affected, total_rows, pct)
--     Duplicate counts are RECORDS in a duplicated group, not group counts.
-- ---------------------------------------------------------------------
CREATE VIEW v_quality AS
SELECT 'Completeness' AS category, 'Facility code missing (None/blank)' AS issue,
       SUM(1 - has_valid_code) AS rows_affected, COUNT(*) AS total_rows,
       ROUND(100 * SUM(1 - has_valid_code) / COUNT(*), 2) AS pct
FROM v_facility
UNION ALL
SELECT 'Completeness', 'Registration number missing (None/blank)',
       SUM(1 - has_registration), COUNT(*), ROUND(100 * SUM(1 - has_registration) / COUNT(*), 2)
FROM v_facility
UNION ALL
SELECT 'Completeness', 'KEPH level missing',
       SUM(keph_num IS NULL), COUNT(*), ROUND(100 * SUM(keph_num IS NULL) / COUNT(*), 2)
FROM v_facility
UNION ALL
SELECT 'Completeness', 'County blank',
       SUM(county_missing), COUNT(*), ROUND(100 * SUM(county_missing) / COUNT(*), 2)
FROM v_facility
UNION ALL
SELECT 'Completeness', 'Sub-county blank',
       SUM(sub_county_missing), COUNT(*), ROUND(100 * SUM(sub_county_missing) / COUNT(*), 2)
FROM v_facility
UNION ALL
SELECT 'Consistency', 'County name not found in census table',
       SUM(1 - county_in_census), COUNT(*), ROUND(100 * SUM(1 - county_in_census) / COUNT(*), 2)
FROM v_facility
UNION ALL
SELECT 'Validity', 'Beds stored with thousands separator (e.g. 1,455)',
       SUM(beds_had_separator), COUNT(*), ROUND(100 * SUM(beds_had_separator) / COUNT(*), 2)
FROM v_facility
UNION ALL
SELECT 'Validity', 'Beds and cots not a valid number',
       SUM(capacity_unparseable), COUNT(*), ROUND(100 * SUM(capacity_unparseable) / COUNT(*), 2)
FROM v_facility
UNION ALL
SELECT 'Validity', 'beds + cots <> "beds and cots"',
       SUM(capacity_components_mismatch), COUNT(*), ROUND(100 * SUM(capacity_components_mismatch) / COUNT(*), 2)
FROM v_facility
UNION ALL
SELECT 'Plausibility', 'Level 4+ facility with zero beds/cots',
       SUM(keph_num >= 4 AND inpatient_capacity = 0), COUNT(*),
       ROUND(100 * SUM(keph_num >= 4 AND inpatient_capacity = 0) / COUNT(*), 2)
FROM v_facility
UNION ALL
SELECT 'Plausibility', 'Level 2 facility with more than 50 beds/cots',
       SUM(keph_num = 2 AND inpatient_capacity > 50), COUNT(*),
       ROUND(100 * SUM(keph_num = 2 AND inpatient_capacity > 50) / COUNT(*), 2)
FROM v_facility
UNION ALL
SELECT 'Plausibility', 'Open 24 hours but not open late night (contradiction)',
       SUM(open_24h = 1 AND open_late_night = 0), COUNT(*),
       ROUND(100 * SUM(open_24h = 1 AND open_late_night = 0) / COUNT(*), 2)
FROM v_facility
UNION ALL
SELECT 'Uniqueness', 'Records sharing a facility code with another record',
       SUM(is_duplicate_code), COUNT(*), ROUND(100 * SUM(is_duplicate_code) / COUNT(*), 2)
FROM v_facility
UNION ALL
SELECT 'Uniqueness', 'Records sharing name + county with another record',
       SUM(is_duplicate_name_county), COUNT(*), ROUND(100 * SUM(is_duplicate_name_county) / COUNT(*), 2)
FROM v_facility;


-- =====================================================================
-- PART B: SANITY CHECKS (run these first; they validate the views)
-- =====================================================================

-- B1) Row counts: facilities loaded vs active vs census counties
SELECT (SELECT COUNT(*) FROM stg_hospitals_clean)        AS raw_rows,
       (SELECT COUNT(*) FROM v_facility)                 AS view_rows,
       (SELECT SUM(is_active) FROM v_facility)           AS active_rows,
       (SELECT COUNT(*) FROM v_county_access)            AS counties;       -- expect counties = 47

-- B2) Facility county names that don't match the census table (fix spelling, e.g. Nairobi / Nairobi City)
SELECT county, COUNT(*) AS facilities
FROM v_facility
WHERE county_in_census = 0
GROUP BY county
ORDER BY facilities DESC;

-- B3) Census counties that received no facilities (should be 0 rows if names all match)
SELECT county, population FROM v_county_access WHERE facilities = 0;

-- B4) Owner types falling into 'Other' (extend the CASE in v_facility if any matter)
SELECT owner_type, COUNT(*) AS facilities
FROM v_facility
WHERE owner_group = 'Other'
GROUP BY owner_type
ORDER BY facilities DESC;

-- B5) Kenyatta National Hospital present? (code 13023; expect 1 row and a large capacity)
SELECT facility_code, facility_name, county, keph_level, inpatient_capacity
FROM v_facility
WHERE facility_code = '13023' OR facility_name LIKE '%Kenyatta National%';


-- =====================================================================
-- OBJECTIVE 1: Facility availability by county
-- =====================================================================

-- 1a) All counties: facilities, per 100k people, per 1,000 sq km (best served first)
SELECT county, population, land_area_sq_km, facilities,
       facilities_per_100k, facilities_per_1000_sqkm, access_rank
FROM v_county_access
ORDER BY access_rank;

-- 1b) Facilities per 1,000 people, by county and capacity
SELECT
  county,
  population,
  facilities,
  ROUND(facilities / population * 10000, 3) AS facilities_per_10000_people,
  RANK() OVER (ORDER BY facilities / population DESC) AS access_rank
FROM v_county_access
WHERE population > 0
ORDER BY facilities_per_10000_people DESC;

-- National benchmark for comparison
SELECT
  SUM(facilities)                                       AS total_facilities,
  SUM(population)                                  AS total_population,
  ROUND(SUM(facilities) / SUM(population) * 10000, 3) AS national_facilities_per_10000
FROM v_county_access;


-- 1c) Top 10 counties: most facilities per 100,000 people
SELECT county, population, facilities, facilities_per_100k
FROM v_county_access
ORDER BY facilities_per_100k DESC
LIMIT 10;

-- 1d) Bottom 10 counties: fewest facilities per 100,000 people
SELECT county, population, facilities, facilities_per_100k
FROM v_county_access
ORDER BY facilities_per_100k ASC
LIMIT 10;

-- 1e) Gap between best and worst served counties (top 5 vs bottom 5 average)
WITH ranked AS (
    SELECT facilities_per_100k,
           ROW_NUMBER() OVER (ORDER BY facilities_per_100k DESC) AS rn_best,
           ROW_NUMBER() OVER (ORDER BY facilities_per_100k ASC)  AS rn_worst
    FROM v_county_access
)
SELECT ROUND(AVG(CASE WHEN rn_best  <= 5 THEN facilities_per_100k END), 2) AS top5_avg,
       ROUND(AVG(CASE WHEN rn_worst <= 5 THEN facilities_per_100k END), 2) AS bottom5_avg,
       ROUND(AVG(CASE WHEN rn_best  <= 5 THEN facilities_per_100k END)
           / NULLIF(AVG(CASE WHEN rn_worst <= 5 THEN facilities_per_100k END), 0), 1) AS top5_to_bottom5_ratio
FROM ranked;
-- Re-check your headline (43.78 vs 16.9, 2.6x) against this output after the join fixes.


-- =====================================================================
-- OBJECTIVE 2: Inpatient capacity
-- =====================================================================

-- 2a) Top 10 counties by total inpatient capacity (with beds per 100k)
SELECT county, population, inpatient_capacity, beds_per_100k
FROM v_county_access
ORDER BY inpatient_capacity DESC
LIMIT 10;

-- 2b) Bottom 10 counties by total inpatient capacity
SELECT county, population, inpatient_capacity, beds_per_100k
FROM v_county_access
ORDER BY inpatient_capacity ASC
LIMIT 10;

-- 2c) Top 10 individual facilities by capacity (KNH should appear)
SELECT facility_name, county, keph_level, owner_group, inpatient_capacity
FROM v_facility
WHERE is_active = 1
ORDER BY inpatient_capacity DESC
LIMIT 10;

-- 2d) Facilities with no inpatient capacity
SELECT COUNT(*) AS facilities,
       SUM(inpatient_capacity = 0) AS zero_capacity,
       ROUND(100 * SUM(inpatient_capacity = 0) / COUNT(*), 1) AS pct_zero
FROM v_facility
WHERE is_active = 1;

-- 2e) Capacity by KEPH level
SELECT keph_level,
       COUNT(*) AS facilities,
       SUM(inpatient_capacity) AS capacity,
       ROUND(AVG(NULLIF(inpatient_capacity, 0)), 1) AS avg_beds_where_present
FROM v_facility
WHERE is_active = 1
GROUP BY keph_level
ORDER BY keph_level;

-- 2f) Capacity by owner type
SELECT owner_type,
       COUNT(*) AS facilities,
       SUM(inpatient_capacity) AS capacity,
       ROUND(100 * SUM(inpatient_capacity) / SUM(SUM(inpatient_capacity)) OVER (), 1) AS pct_of_total
FROM v_facility
WHERE is_active = 1
GROUP BY owner_type
ORDER BY capacity DESC;

-- 2g) Referral gap: counties whose highest-level facility is Level 3 or below (or none at all)
SELECT county, population, facilities, highest_keph_level, inpatient_capacity
FROM v_county_access
WHERE highest_keph_level IS NULL OR highest_keph_level <= 3
ORDER BY highest_keph_level, county;


-- =====================================================================
-- OBJECTIVE 3: Level of care (KEPH)
-- =====================================================================

-- 3a) National distribution of facilities and capacity by KEPH level
SELECT keph_level,
       COUNT(*) AS facilities,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_facilities,
       SUM(inpatient_capacity) AS total_capacity,
       ROUND(100 * SUM(inpatient_capacity) / SUM(SUM(inpatient_capacity)) OVER (), 1) AS pct_of_capacity
FROM v_facility
WHERE is_active = 1
GROUP BY keph_level
ORDER BY keph_level;

-- 3b) Care-tier mix by county (counts and % of the county's facilities)
SELECT county, facilities,
       primary_care_facilities, hospital_facilities, referral_facilities,
       ROUND(100 * primary_care_facilities / NULLIF(facilities, 0), 2) AS pct_primary_care,
       ROUND(100 * hospital_facilities     / NULLIF(facilities, 0), 2) AS pct_hospital,
       ROUND(100 * referral_facilities     / NULLIF(facilities, 0), 2) AS pct_referral
FROM v_county_access
ORDER BY pct_primary_care DESC;

-- 3c) Facilities per 100,000 people by care tier (lowest referral access first)
SELECT county, population, primary_care_per_100k, hospital_per_100k, referral_per_100k
FROM v_county_access
ORDER BY referral_per_100k, hospital_per_100k;

-- 3d) Highest level of care available in each county, with a Level 5/6 flag
SELECT county, facilities, level_5_facilities, level_6_facilities, highest_keph_level,
       CASE WHEN level_5_facilities + level_6_facilities = 0 THEN 'No Level 5/6' ELSE 'Has Level 5/6' END AS referral_status
FROM v_county_access
ORDER BY highest_keph_level, county;

-- 3e) Counties with a Level 6 facility
SELECT county, level_6_facilities
FROM v_county_access
WHERE level_6_facilities > 0
ORDER BY level_6_facilities DESC;


-- =====================================================================
-- OBJECTIVE 4: Ownership mix (active facilities only, via v_facility)
-- =====================================================================

-- 4a) Share of facilities vs share of beds by owner group
SELECT owner_group,
       COUNT(*) AS facilities,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_facilities,
       SUM(inpatient_capacity) AS total_capacity,
       ROUND(100 * SUM(inpatient_capacity) / SUM(SUM(inpatient_capacity)) OVER (), 2) AS pct_of_capacity
FROM v_facility
WHERE is_active = 1
GROUP BY owner_group
ORDER BY facilities DESC;

-- 4b) Ownership mix by KEPH level (counts and % within each level)
SELECT keph_level,
       SUM(owner_group = 'Public')      AS public,
       SUM(owner_group = 'Private')     AS private,
       SUM(owner_group = 'Faith-based') AS faith_based,
       SUM(owner_group = 'NGO')         AS ngo,
       SUM(owner_group = 'Other')       AS other,
       COUNT(*)                         AS total,
       ROUND(100 * SUM(owner_group = 'Public')      / COUNT(*), 1) AS pct_public,
       ROUND(100 * SUM(owner_group = 'Private')     / COUNT(*), 1) AS pct_private,
       ROUND(100 * SUM(owner_group = 'Faith-based') / COUNT(*), 1) AS pct_faith_based,
       ROUND(100 * SUM(owner_group = 'NGO')         / COUNT(*), 1) AS pct_ngo
FROM v_facility
WHERE is_active = 1
GROUP BY keph_level
ORDER BY keph_level;

-- 4c) Ownership mix by county (most private first)
SELECT county, facilities,
       public_facilities, private_facilities, faith_based_facilities, ngo_facilities,
       pct_public, pct_private
FROM v_county_access
ORDER BY pct_private DESC;


-- =====================================================================
-- OBJECTIVE 5: Opening hours / service availability
-- =====================================================================

-- 5a) National picture
SELECT COUNT(*) AS facilities,
       SUM(open_24h)        AS open_24h,        ROUND(100 * SUM(open_24h)        / COUNT(*), 1) AS pct_24h,
       SUM(open_weekends)   AS open_weekends,   ROUND(100 * SUM(open_weekends)   / COUNT(*), 1) AS pct_weekends,
       SUM(open_holidays)   AS open_holidays,   ROUND(100 * SUM(open_holidays)   / COUNT(*), 1) AS pct_holidays,
       SUM(open_late_night) AS open_late_night, ROUND(100 * SUM(open_late_night) / COUNT(*), 1) AS pct_late_night
FROM v_facility
WHERE is_active = 1;

-- 5b) By KEPH level
SELECT keph_level,
       COUNT(*) AS facilities,
       ROUND(100 * SUM(open_24h)        / COUNT(*), 1) AS pct_24h,
       ROUND(100 * SUM(open_weekends)   / COUNT(*), 1) AS pct_weekends,
       ROUND(100 * SUM(open_holidays)   / COUNT(*), 1) AS pct_holidays,
       ROUND(100 * SUM(open_late_night) / COUNT(*), 1) AS pct_late_night
FROM v_facility
WHERE is_active = 1
GROUP BY keph_level
ORDER BY keph_level;

-- 5c) By county (least 24-hour access first)
SELECT county, facilities, pct_24h, pct_weekends, pct_holidays, pct_late_night
FROM v_county_access
ORDER BY pct_24h;

-- 5d) By owner group  (FIX: late-night column previously repeated the holiday flag)
SELECT owner_group,
       COUNT(*) AS facilities,
       ROUND(100 * SUM(open_24h)        / COUNT(*), 2) AS pct_24h,
       ROUND(100 * SUM(open_weekends)   / COUNT(*), 2) AS pct_weekends,
       ROUND(100 * SUM(open_holidays)   / COUNT(*), 2) AS pct_holidays,
       ROUND(100 * SUM(open_late_night) / COUNT(*), 2) AS pct_late_night
FROM v_facility
WHERE is_active = 1
GROUP BY owner_group
ORDER BY facilities DESC;

-- 5e) Share of each county's beds in a facility open 24 hours
SELECT county, inpatient_capacity, beds_in_24h_facilities, pct_beds_24h
FROM v_county_access
ORDER BY pct_beds_24h DESC;

-- 5f) Hospital-level facilities (Level 4+) NOT open 24 hours 
SELECT facility_name, county, keph_level, owner_group, inpatient_capacity
FROM v_facility
WHERE is_active = 1
  AND keph_num >= 4
  AND open_24h = 0
ORDER BY inpatient_capacity DESC;


-- =====================================================================
-- OBJECTIVE 6: Operational status
-- =====================================================================

-- 6a) Operational status distribution (all rows)
SELECT operation_status,
       COUNT(*) AS facilities,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM v_facility
GROUP BY operation_status;

-- 6b) Status vs closed / approved / public-visible flags (raw table, as these are not in the views)
SELECT `operation status`, closed, approved, `public visible`, COUNT(*) AS facilities
FROM stg_hospitals_clean
GROUP BY `operation status`, closed, approved, `public visible`;

-- 6c) Any non-active facility? (expect 0 rows)
SELECT county, COUNT(*) AS inactive_facilities
FROM v_facility
WHERE is_active = 0
GROUP BY county;

-- 6d) "Operational" in name only: none of the four extended-hours flags, by KEPH level
--     (FIX: flags are now true 0/1 values; before, text 'Yes' = 0 evaluated TRUE in MySQL)
SELECT keph_level,
       COUNT(*) AS facilities,
       SUM(open_24h = 0 AND open_weekends = 0 AND open_holidays = 0 AND open_late_night = 0) AS weekday_hours_only,
       ROUND(100 * SUM(open_24h = 0 AND open_weekends = 0 AND open_holidays = 0 AND open_late_night = 0)
                 / COUNT(*), 1) AS pct_weekday_only
FROM v_facility
WHERE is_active = 1
GROUP BY keph_level
ORDER BY keph_level;


-- =====================================================================
-- OBJECTIVE 7: Data quality as a finding
-- =====================================================================

-- 7a) Scorecard (largest issues first)
SELECT category, issue, rows_affected, total_rows, pct
FROM v_quality
ORDER BY pct DESC;

-- 7b) Where is missing registration data concentrated? (by owner type)
SELECT owner_type,
       COUNT(*) AS facilities,
       SUM(1 - has_registration) AS missing_registration,
       ROUND(100 * SUM(1 - has_registration) / COUNT(*), 1) AS pct_missing
FROM v_facility
GROUP BY owner_type
ORDER BY pct_missing DESC;

-- 7c) Records where beds + cots disagree with "beds and cots"
SELECT facility_code, facility_name, beds_n, cots_n, inpatient_capacity
FROM v_facility
WHERE capacity_components_mismatch = 1;

-- 7d) Duplicate records (inspect, then decide whether to drop)
SELECT facility_code, facility_name, county, keph_level, inpatient_capacity,
       is_duplicate_code, is_duplicate_name_county
FROM v_facility
WHERE is_duplicate_code = 1 OR is_duplicate_name_county = 1
ORDER BY facility_name, county;


-- view to be used on the dashboard

CREATE VIEW vw_county_access AS
SELECT
  p.name,
  p.population,
  COUNT(h.code)                              AS facilities,
  SUM(COALESCE(h.`beds and cots`, 0))                       AS beds,
  COUNT(h.code) / p.population * 100000 AS facilities_per_100k,
  SUM(COALESCE(h.`beds and cots`, 0)) / p.population * 10000 AS beds_per_10k
FROM stg_county_population_clean p
LEFT JOIN stg_hospitals_clean h ON h.county = p.name
GROUP BY p.name, p.population;






