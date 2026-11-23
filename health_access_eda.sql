USE kenya_health_access;

-- 			OBJECTIVES

 --  1. Facility availability by county
 --  2. Inpatient capacity
--   3. Level of care (KEPH)
--   4. Ownership mix
--   5. Opening hours / service availability
--   6. Operational status
--   7. Data quality as a finding

-- =============================================
-- OBJECTIVE 1: Facility availability by county
-- =============================================

--   1a) facilities per 100,000 people and per 1000 sq_km

-- listed counties and their total count of facilities

SELECT c.name, COUNT(h.county) AS facilities
FROM stg_county_population_clean c
LEFT JOIN stg_hospitals_clean h
       ON LOWER(TRIM(h.county)) = LOWER(TRIM(c.name))
GROUP BY c.name
ORDER BY facilities DESC;

-- Facilities per 100,000 people and per 1,000 sq Km

SELECT
    c.name                                                AS county,
    c.population,
    c.land_area_sq_km,
    COUNT(h.county)                                       AS facilities,
    ROUND(COUNT(h.county) * 100000 / c.population, 2)     AS facilities_per_100k,
    ROUND(COUNT(h.county) * 1000 / c.land_area_sq_km, 2)  AS facilities_per_1000_sqkm,
    RANK() OVER (ORDER BY COUNT(h.county) / c.population DESC) AS access_rank
FROM stg_county_population_clean c
LEFT JOIN stg_hospitals_clean h
       ON LOWER(TRIM(h.county)) = LOWER(TRIM(c.name))
GROUP BY c.name, c.population, c.land_area_sq_km
ORDER BY access_rank DESC;

-- b) Top 10 counties with the highest health facilities per 100,000 people
SELECT c.name AS county, c.population, 
				COUNT(h.county) AS facilities,
                ROUND(COUNT(h.county) * 100000 / c.population, 2) AS facilities_per_100k
FROM stg_county_population_clean c
LEFT JOIN stg_hospitals_clean h
	ON h.county = c.name
GROUP BY c.name, c.population
ORDER BY COUNT(h.county) / c.population DESC
LIMIT 10;

-- d) Top 10 counties with the least health facilities per 100,000 people
SELECT c.name AS county, c.population, 
				COUNT(h.county) AS facilities,
                ROUND(COUNT(h.county) * 100000 / c.population, 2) AS facilities_per_100k
FROM stg_county_population_clean c
LEFT JOIN stg_hospitals_clean h
	ON h.county = c.name
GROUP BY c.name, c.population
ORDER BY COUNT(h.county) / c.population ASC
LIMIT 10;

-- Gap between the best and worst served counties
-- (health facilities per 100,000 people)

WITH county_access AS (
	SELECT 
		c.name AS county,
        COUNT(h.county) * 100000 / c.population AS per_100k
	FROM stg_county_population_clean c
    LEFT JOIN stg_hospitals_clean h
		ON h.county = c.name
	GROUP BY c.name, c.population
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY per_100k DESC) AS rn_best,
           ROW_NUMBER() OVER (ORDER BY per_100k ASC)  AS rn_worst
    FROM county_access
)
SELECT
    ROUND(AVG(CASE WHEN rn_best  <= 5 THEN per_100k END), 2) AS top5_avg,
    ROUND(AVG(CASE WHEN rn_worst <= 5 THEN per_100k END), 2) AS bottom5_avg,
    ROUND(AVG(CASE WHEN rn_best  <= 5 THEN per_100k END)
        / NULLIF(AVG(CASE WHEN rn_worst <= 5 THEN per_100k END), 0), 1) AS top5_to_bottom5_ratio
FROM ranked;

-- The 5 best-served counties average 43.78 facilities per 100,000 people, 
-- compared with 16.9 in the 5 least-served, a 2.6-fold difference. 


-- 				OBJECTIVE 2: Inpatient capacity

-- check if beds + cots = `beds and cots`
SELECT
    COUNT(*)                          AS rows_checked,
    SUM(`beds and cots` = beds + cots)  AS equals_sum,
    SUM(`beds and cots` <> beds + cots) AS differs
FROM stg_hospitals_clean
WHERE beds IS NOT NULL AND cots IS NOT NULL AND `beds and cots`IS NOT NULL;  -- ARE EQUAL

-- a) Top 10 Counties with the highest inpatient capacity

SELECT 
	name, 
    SUM(`beds and cots`) AS total_capacity
FROM stg_hospitals_clean
GROUP BY name
ORDER BY total_capacity DESC
LIMIT 10;

--  NOTE: Kenyatta National Hospital should be in the top 10 list indicating that import wizard removed the row 
-- INSERT KNH into stg_hospitals_clean in the cleaning script

-- Top 10 Counties with the least inpatient capacity
SELECT 
	name, 
    SUM(`beds and cots`) AS total_capacity
FROM stg_hospitals_clean
GROUP BY name
ORDER BY total_capacity ASC
LIMIT 10;

-- count of facilities with no inpatient capacity
SELECT COUNT(*) AS facilities,
		SUM(`beds and cots` = 0) AS zero_capacity,
        ROUND(100 * SUM( `beds and cots` = 0) / COUNT(*), 1) AS pct_zero
FROM stg_hospitals_clean;

-- b) capacity per KEPH level

SELECT `keph level`, COUNT(*), SUM(`beds and cots`) AS capacity,
		ROUND(AVG(NULLIF(`beds and cots`, 0)), 1) AS avg_beds_where_present
FROM stg_hospitals_clean
GROUP BY `keph level`
ORDER BY `keph level`;

-- c) Facility owner type capacity:

SELECT `owner type`, COUNT(*) AS facilities, SUM(`beds and cots`) AS capacity,
       ROUND(100 * SUM(`beds and cots`) / SUM(SUM(`beds and cots`)) OVER (), 1) AS pct_of_total
FROM stg_hospitals_clean 
GROUP BY `owner type` 
ORDER BY capacity DESC; 

-- d) Counties with no facility above KEPH level 3 (referral gap):

SELECT TRIM(county) AS county,
       `keph level` AS keph_level,
       COUNT(*) AS facilities,
       SUM(CASE WHEN TRIM(`beds and cots`) REGEXP '^[0-9]+$'
                THEN CAST(TRIM(`beds and cots`) AS UNSIGNED) ELSE 0 END) AS inpatient_capacity
FROM stg_hospitals_clean
WHERE CAST(REGEXP_SUBSTR(`keph level`, '[0-9]+') AS UNSIGNED) < 3
GROUP BY TRIM(county), `keph level`
ORDER BY county, keph_level;

-- ======================
-- OBJECTIVE 3: Level of care (Keph Level)
-- ====================== 
--  3a) National distribution of facilities and inpatient capacity by KEPH level

SELECT `keph level`,COUNT(`keph level`) AS keph_num, COUNT(*) AS facilities,
		ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_facilities,
       SUM(`beds and cots`) AS total_capacity,
       ROUND(100 * SUM(`beds and cots`) / SUM(SUM(`beds and cots`)) OVER (), 1) AS pct_of_capacity
FROM stg_hospitals_clean
GROUP BY `keph level`
ORDER BY `keph level`;

-- 3b) Distribution of level of care by county
       
SELECT TRIM(county) AS county,
       SUM(`keph level` IN ('Level 2', 'Level 3')) AS primary_care,
       SUM(`keph level` = 'Level 4')               AS hospital,
       SUM(`keph level` IN ('Level 5', 'Level 6')) AS referral,
       COUNT(*)                                    AS total_facilities,
       ROUND(100 * SUM(`keph level` IN ('Level 2', 'Level 3')) / COUNT(*), 2) AS pct_primary_care,
       ROUND(100 * SUM(`keph level` = 'Level 4') / COUNT(*), 2)               AS pct_hospital,
       ROUND(100 * SUM(`keph level` IN ('Level 5', 'Level 6')) / COUNT(*), 2) AS pct_referral
FROM stg_hospitals_clean
GROUP BY TRIM(county)
ORDER BY pct_primary_care DESC;

-- 3c) Facilities per 100,000 people 
SELECT h.county,
       p.population,
       ROUND(SUM(`keph level` IN ('Level 2', 'Level 3')) / p.population * 100000, 2) AS primary_care_per_100k,
       ROUND(SUM(`keph level` = 'Level 4') / p.population * 100000, 2) AS hospital_per_100k,
       ROUND(SUM(`keph level` IN ('Level 5', 'Level 6')) / p.population * 100000, 2) AS referral_per_100k
FROM stg_hospitals_clean h
JOIN stg_county_population_clean p 
	ON p.name = LOWER(h.county)
GROUP BY h.county, p.population
ORDER BY referral_per_100k;

-- 3d) Counties missing higher levels of care

SELECT county,
		COUNT(*) AS total_facilities,
		SUM(`keph level` = 'Level 5') AS level_5_facilities,
        MAX(CAST(REGEXP_SUBSTR(`keph level`, '[0-9]+') AS UNSIGNED)) AS highest_level
FROM stg_hospitals_clean
GROUP BY county
HAVING SUM(`keph level`  = 'Level 6') = 0
ORDER BY highest_level, county;

-- 3e) Counties with a Level 6 facility
SELECT county, COUNT(*) AS level_6_facilities
FROM stg_hospitals_clean
WHERE `keph level` = 'Level 6'
GROUP BY county;

-- ========================================
-- OBJECTIVE: 4a) Who runs Kenya's health facilities, and who holds the beds?
-- Share of facilities vs share of inpatient capacity by ownership group (open, operational facilities only)
-- ======================================== 

CREATE OR REPLACE VIEW v_facility_owner AS
SELECT code AS facility_code,
		name AS facility_name,
        county,
        `keph level`,
        `owner type`,
        CASE TRIM(`owner type`)
			WHEN 'Ministry of Health'              THEN 'Public'
			WHEN 'Private Practice'                THEN 'Private'
			WHEN 'Faith Based Organization'        THEN 'Faith-based'
			WHEN 'Non-Governmental Organizations'  THEN 'NGO'
			ELSE 'Other'
        END AS owner_group,
        CASE WHEN REPLACE(TRIM(`beds and cots`), ',', '') REGEXP '^[0-9]+$'
            THEN CAST(REPLACE(TRIM(`beds and cots`), ',', '') AS UNSIGNED) ELSE 0 END AS inpatient_capacity
FROM stg_hospitals_clean
WHERE closed = 'no'
  AND `operation status` = 'operational';
  
SELECT owner_group,
       COUNT(*) AS facilities,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_facilities,
       SUM(inpatient_capacity) AS total_capacity,
       ROUND(100 * SUM(inpatient_capacity) / SUM(SUM(inpatient_capacity)) OVER (), 2) AS pct_of_capacity
FROM v_facility_owner
GROUP BY owner_group
ORDER BY facilities DESC;

-- 4b) Ownership mix by level of care (KEPH level) (counts and % within each level)

SELECT COALESCE(`keph level`, 'Unspecified') AS level_of_care,
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

FROM v_facility_owner
GROUP BY COALESCE(`keph level`, 'Unspecified')
ORDER BY COALESCE(`keph level`, 'Unspecified');

-- 4c) Ownership mix by county (counts and % public / private)
SELECT county,
       COUNT(*) AS total_facilities,
       SUM(owner_group = 'Public')      AS public,
       SUM(owner_group = 'Private')     AS private,
       SUM(owner_group = 'Faith-based') AS faith_based,
       SUM(owner_group = 'NGO')         AS ngo,
       ROUND(100 * SUM(owner_group = 'Public')  / COUNT(*), 1) AS pct_public,
       ROUND(100 * SUM(owner_group = 'Private') / COUNT(*), 1) AS pct_private
FROM v_facility_owner
GROUP BY county
ORDER BY pct_private DESC;

-- =================================================
-- OBJECTIVE 5: Opening hours / service availability
-- ==================================================

-- 5a) National picture: how many facilities are open 24h, weekends, holidays, late night?
SELECT COUNT(*) AS facilities,
       SUM(Open_whole_day = 'Yes')        AS open_24h,        ROUND(100 * SUM(open_whole_day  = 'Yes')        / COUNT(*), 1) AS pct_24h,
       SUM(open_weekends  = 'Yes')   AS open_weekends,   ROUND(100 * SUM(open_weekends  = 'Yes')   / COUNT(*), 1) AS pct_weekends,
       SUM(Open_public_holidays  = 'Yes')   AS open_holidays,   ROUND(100 * SUM(open_public_holidays = 'Yes')   / COUNT(*), 1) AS pct_holidays,
       SUM(open_late_night  = 'Yes') AS open_late_night, ROUND(100 * SUM(open_late_night  = 'Yes') / COUNT(*), 1) AS pct_late_night
FROM stg_hospitals_clean;

-- 5b) Opening hours by level of care
SELECT COALESCE(`keph level`, 'Unspecified') AS level_of_care,
       COUNT(*) AS facilities,
       ROUND(100 * SUM(open_whole_day = 'Yes')        / COUNT(*), 1) AS pct_24h,
       ROUND(100 * SUM(open_weekends = 'Yes')   / COUNT(*), 1) AS pct_weekends,
       ROUND(100 * SUM(open_public_holidays = 'Yes')   / COUNT(*), 1) AS pct_holidays,
       ROUND(100 * SUM(open_late_night = 'Yes') / COUNT(*), 1) AS pct_late_night
FROM stg_hospitals_clean
GROUP BY COALESCE(`keph level`, 'Unspecified')
ORDER BY COALESCE(`keph level`, 'Unspecified');

-- 5c) Opening hours by county (least 24-hour access first)
SELECT county,
       COUNT(*) AS facilities,
       ROUND(100 * SUM(open_whole_day = 'Yes')        / COUNT(*), 1) AS pct_24h,
	   ROUND(100 * SUM(open_public_holidays = 'Yes') / COUNT(*), 1) AS pct_holidays,
       ROUND(100 * SUM(open_weekends = 'Yes')   / COUNT(*), 1) AS pct_weekends,
       ROUND(100 * SUM(open_late_night = 'Yes') / COUNT(*), 1) AS pct_late_night
FROM stg_hospitals_clean
GROUP BY county
ORDER BY pct_24h;

-- 5d) Opening hours by ownership group
SELECT `owner type`,
       COUNT(*) AS facilities,
       ROUND(100 * SUM(open_whole_day = 'Yes')      / COUNT(*), 2) AS pct_24h,
       ROUND(100 * SUM(open_weekends = 'Yes') / COUNT(*), 2) AS pct_weekends,
       ROUND(100 * SUM(open_public_holidays = 'Yes') / COUNT(*), 2) AS pct_holidays,
	   ROUND(100 * SUM(open_public_holidays = 'Yes') / COUNT(*), 2) AS pct_late_night

FROM stg_hospitals_clean
GROUP BY `owner type`
ORDER BY facilities DESC;

-- 5e) Share of each county's beds that sit in a facility open 24 hours
SELECT county,
       SUM(`beds and cots`) AS total_capacity,
       SUM(CASE WHEN open_whole_day = 'Yes' THEN `beds and cots` ELSE 0 END) AS capacity_in_24h_facilities,
       ROUND(100 * SUM(CASE WHEN open_whole_day = 'Yes' THEN `beds and cots` ELSE 0 END) / NULLIF(SUM(`beds and cots`), 0), 1) AS pct_beds_24h
FROM stg_hospitals_clean
GROUP BY county
ORDER BY pct_beds_24h DESC;


-- 5f) Hospital-level facilities (Level 4+) that are NOT open 24 hours
SELECT name, county, `keph level`, `owner type`, `beds and cots`
FROM stg_hospitals_clean
WHERE `keph level` IN ('Level 4','Level 5', 'Level 6') 
					AND open_whole_day = 'No'
ORDER BY `beds and cots` DESC;

-- =================================================
-- OBJECTIVE 6: Operational status
-- ==================================================
-- 6a) Operational status distribution
SELECT `operation status`, COUNT(*) AS facilities,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM stg_hospitals_clean
GROUP BY `operation status`;

-- 6b) Status, closed, approved and public-visible flags together
SELECT `operation status`, closed, approved, `public visible`, COUNT(*) AS facilities
FROM stg_hospitals_clean
GROUP BY `operation status`, closed, approved, `public visible`;

-- 6c) Any county with a non-operational or closed facility? (expect 0 rows)
SELECT county,
       SUM(`operation status` <> 'Operational') AS not_operational,
       SUM(closed <> 'No')                    AS closed_facilities
FROM stg_hospitals_clean
GROUP BY county
HAVING not_operational > 0 OR closed_facilities > 0;


-- 6d) "Operational" in name only: facilities open on none of the four extended-hours flags
--     (weekday daytime service at best), by level of care
SELECT COALESCE(`keph level`, 'Unspecified') AS level_of_care,
       COUNT(*) AS facilities,
       SUM(open_whole_day = 0 AND open_weekends = 0 AND open_public_holidays = 0 AND open_late_night = 0) AS weekday_hours_only,
       ROUND(100 * SUM(open_whole_day = 0 AND open_weekends = 0 AND open_public_holidays = 0 AND open_late_night = 0) / COUNT(*), 1) AS pct_weekday_only
FROM stg_hospitals_clean
GROUP BY COALESCE(`keph level`, 'Unspecified')
ORDER BY COALESCE(`keph level`, 'Unspecified');

-- =================================================
-- OBJECTIVE 7: Data Quality as a Finding
-- ==================================================

-- 7a) Data quality scorecard: issue, rows affected, % of all facilities

SELECT 'Facility code is a placeholder (None)' AS issue,
       SUM(TRIM(code) IN ('None', '')) AS rows_affected,
       ROUND(100 * SUM(TRIM(code) IN ('None', '')) / COUNT(*), 2) AS pct
FROM stg_hospitals_clean
UNION ALL
SELECT 'Registration number missing (None/blank)',
       SUM(TRIM(registration_number) IN ('None', '')),
       ROUND(100 * SUM(TRIM(registration_number) IN ('None', '')) / COUNT(*), 2)
FROM stg_hospitals_clean
UNION ALL
SELECT 'KEPH level missing',
       SUM(`keph level` IS NULL), ROUND(100 * SUM(`keph level`IS NULL) / COUNT(*), 2)
FROM stg_hospitals_clean
UNION ALL
SELECT 'Beds stored with a thousands separator (e.g. 1,455)',
       SUM(`beds and cots` LIKE '%,%'), ROUND(100 * SUM(`beds and cots` LIKE '%,%') / COUNT(*), 2)
FROM stg_hospitals_clean
UNION ALL
SELECT 'Level 4+ facility with zero beds/cots',
       SUM(`keph level` IN ('Level 4', 'Level 5', 'Level 6')  AND `beds and cots` = 0),
       ROUND(100 * SUM(`keph level` IN ('Level 4', 'Level 5', 'Level 6') AND `beds and cots` = 0) / COUNT(*), 2)
FROM stg_hospitals_clean
UNION ALL
SELECT 'Level 2 facility with more than 50 beds/cots',
       SUM(`keph level`= 2 AND `beds and cots` > 50),
       ROUND(100 * SUM(`keph level` = 2 AND `beds and cots` > 50) / COUNT(*), 2)
FROM stg_hospitals_clean
UNION ALL
SELECT 'Open 24 hours but not open late night (contradiction)',
       SUM(Open_whole_day = 1 AND open_late_night = 0),
       ROUND(100 * SUM(open_whole_day = 1 AND open_late_night = 0) / COUNT(*), 2)
FROM stg_hospitals_clean;

-- 7b) Duplicates
SELECT 'Duplicate facility codes (excluding None)' AS issue, COUNT(*) AS rows_affected
FROM (SELECT code FROM stg_hospitals_clean
      WHERE code <> 'None'
      GROUP BY code HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'Duplicate name + county', COUNT(*)
FROM (SELECT name, county FROM stg_hospitals_clean
      GROUP BY name, county HAVING COUNT(*) > 1) d;

-- 7c) Do beds + cots equal "beds and cots"? (rows where they disagree)
SELECT code, name, beds, cots, `beds and cots`
FROM stg_hospitals_clean
WHERE REPLACE(TRIM(beds), ',', '')  REGEXP '^[0-9]+$'
  AND TRIM(cots)                    REGEXP '^[0-9]+$'
  AND REPLACE(TRIM(`beds and cots`), ',', '') REGEXP '^[0-9]+$'
  AND CAST(REPLACE(TRIM(beds), ',', '') AS UNSIGNED) + CAST(TRIM(Cots) AS UNSIGNED)
      <> CAST(REPLACE(TRIM(`beds and cots`), ',', '') AS UNSIGNED);

-- 7d) Where is the missing registration data concentrated? (by owner type)
SELECT `owner type`,
       COUNT(*) AS facilities,
       SUM(TRIM(registration_number) IN ('None', '')) AS missing_registration,
       ROUND(100 * SUM(TRIM(registration_number) IN ('None', '')) / COUNT(*), 1) AS pct_missing
FROM stg_hospitals_clean
GROUP BY `owner type`
ORDER BY pct_missing DESC;

-- 7e) Completeness of county fields
SELECT SUM(TRIM(county) IN ('', 'None'))       AS blank_county,
       SUM(TRIM(`sub county`) IN ('', 'None'))   AS blank_sub_county
FROM (SELECT county, `sub county` FROM stg_hospitals_clean)x;