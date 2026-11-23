USE health_access_kenya_db;

SELECT COUNT(*) AS hospital_rows
FROM kmhfl_hospitals_2020;
						-- 12393 rows


SELECT COUNT(*) AS population_rows
FROM knbs_county_population_2019;
						-- 48 rows
                        
-- staging tables

-- kmhfl_hospitals_2020
DROP TABLE IF EXISTS stg_hospitals_raw;
CREATE TABLE stg_hospitals_raw AS
SELECT * FROM kmhfl_hospitals_2020;
    
-- knbs_county_population_2019
DROP TABLE IF EXISTS stg_county_population_raw;
CREATE TABLE stg_county_population_raw AS
SELECT * FROM knbs_county_population_2019;

                        
-- Data Cleaning

-- 1. Removing duplicates
-- 2. Standardize the data
-- 3. Null values or blank values
-- 4. Remove Any irrelevant Columns or Rows

-- =======================
-- COUNTY POPULATION 
-- =======================
SELECT *
FROM stg_county_population_raw;

-- Check for Exact duplicate rows

WITH duplicates AS (
	SELECT *,
		ROW_NUMBER() OVER(
			PARTITION BY `name`, population, land_area_sq_km,population_density
            ORDER BY `name`) AS row_num
	FROM stg_county_population_raw
)
SELECT *
FROM duplicates
WHERE row_num > 1;

-- checking for duplicate county names

SELECT 
    `name`,
    COUNT(*) AS count
FROM stg_county_population_raw
GROUP BY `name`
HAVING COUNT(*) > 1;

-- RESULT:
--   - 0 duplicate county records found

-- 2b. Standardizing county population data 

SELECT *
FROM stg_county_population_raw;

-- create stg_county_population_clean table 

DROP TABLE IF EXISTS stg_county_population_clean;

CREATE TABLE stg_county_population_clean(
	`name` VARCHAR(100),
	population          BIGINT,
    land_area_sq_km     DECIMAL(12,2),
    population_density  DECIMAL(12,2)
);

INSERT INTO stg_county_population_clean
SELECT *
FROM stg_county_population_raw;

-- name column
UPDATE stg_county_population_clean
SET `name` = TRIM(`name`);

-- 2c) check for missing values

SELECT *
FROM stg_county_population_clean;

SELECT 
	COUNT(*) AS total_rows,
    SUM(population IS NULL OR LOWER(TRIM(population)) IN ('', 'none', 'na', 'n/a', 'null')) AS population_missing,
    SUM(land_area_sq_km IS NULL OR LOWER(TRIM(land_area_sq_km)) IN ('', 'none', 'na', 'n/a', 'null')) AS land_area_sq_km_missing,
    SUM(population_density IS NULL OR LOWER(TRIM(population_density)) IN ('', 'none', 'na', 'n/a', 'null')) AS population_density_missing
FROM stg_county_population_clean;

-- 0 missing_values

-- drop 'Kenya' from county population to remain with 47 counties

SELECT *
FROM stg_county_population_clean
WHERE `name` LIKE '%Kenya%';

-- number of counties before
SELECT COUNT(*) AS total_rows
FROM stg_county_population_clean;

-- delete 'Kenya' row
DELETE FROM stg_county_population_clean
WHERE LOWER(TRIM(`name`)) = 'Kenya';

-- validate 'Kenya' row removal
SELECT COUNT(*) AS total_rows,
	       COUNT(DISTINCT TRIM(`name`)) AS distinct_counties
FROM stg_county_population_clean;

-- standardizing county names in population table
SET SQL_SAFE_UPDATES = 0;

UPDATE stg_county_population_clean
SET name = REPLACE(REPLACE(TRIM(name), '-', ' '), '''', '');

SET SQL_SAFE_UPDATES = 1;


-- =====================
-- HOSPITAL DATA
-- =====================

-- 1B) hospital data

SELECT *
FROM stg_hospitals_raw;



-- The potential duplicates investigated
-- some records contain diffrent beds,cots , beds and cots capacities,
-- regulatory information and operating schedules.
--
-- Because there is currently no established timestamp or
-- version field to determine which record is more current,
-- these records are RETAINED rather than arbitrarily deleted.


-- 2B) Hospital data 

SELECT *
FROM stg_hospitals_raw;

SELECT COUNT(*) AS total_rows,
		COUNT(`name`) AS non_null_names
FROM stg_hospitals_raw;

DROP TABLE IF EXISTS stg_hospitals_clean;

CREATE TABLE stg_hospitals_clean AS
SELECT *
FROM stg_hospitals_raw;

SELECT COUNT(*) AS total_rows,
       COUNT(name) AS non_null_names
FROM stg_hospitals_clean;

SELECT name
FROM stg_hospitals_clean
LIMIT 10;

-- finding duplicate records

-- 1.standardize the hospital nanmes

SET SQL_SAFE_UPDATES = 0;

UPDATE stg_hospitals_clean
SET
	`name` = TRIM(`name`),
    officialname = TRIM(officialname),
    registration_number = TRIM(registration_number),
    `keph level` = TRIM(`keph level`),
    `facility type` = TRIM(`facility type`),
    facility_type_category = TRIM(facility_type_category),
    `owner` = TRIM(`owner`),
    `owner type` = TRIM(`owner type`),
    `regulatory body` = TRIM(`regulatory body`),
    beds = TRIM(beds),
    cots = TRIM(cots),
    `beds and cots` = TRIM(`beds and cots`),
    county = TRIM(county),
    `sub county` = TRIM(`sub county`),
    ward = TRIM(ward),
    `operation status` = TRIM(`operation status`),
    open_whole_day = TRIM(open_whole_day),
    open_public_holidays = TRIM(open_public_holidays),
    open_weekends = TRIM(open_weekends),
    open_late_night = TRIM(open_late_night),
    service_names = TRIM(service_names),
    approved = TRIM(approved),
    `public visible` = TRIM(`public visible`),
    closed = TRIM(closed);
    
SET SQL_SAFE_UPDATES = 1;


-- a)create title case function to standardize hospital names

DROP FUNCTION IF EXISTS title_case;

DELIMITER //

CREATE FUNCTION title_case(str VARCHAR(255))
RETURNS VARCHAR(255)
DETERMINISTIC
BEGIN
    DECLARE result VARCHAR(255) DEFAULT '';
    DECLARE i INT DEFAULT 1;
    DECLARE n INT;

    IF str IS NULL THEN
        RETURN NULL;
    END IF;

    SET str = LOWER(TRIM(str));
    SET n = CHAR_LENGTH(str);

    WHILE i <= n DO
        IF i = 1 OR SUBSTRING(str, i - 1, 1) = ' ' THEN
            SET result = CONCAT(result, UPPER(SUBSTRING(str, i, 1)));
        ELSE
            SET result = CONCAT(result, SUBSTRING(str, i, 1));
        END IF;

        SET i = i + 1;
    END WHILE;

    RETURN result;
END //

DELIMITER ;

-- testing the title case function
SELECT
    name AS original_name,
    title_case(name) AS standardized_name
FROM stg_hospitals_clean
LIMIT 10;

-- applying title case function
UPDATE stg_hospitals_clean
SET name = title_case(name);

-- validate
SELECT
    COUNT(*) AS total_rows,
    COUNT(name) AS non_null_names,
    SUM(name <> TRIM(name)) AS names_with_extra_spaces
FROM stg_hospitals_clean;

-- b) check for duplicates
SELECT
    `Name`,
    `County`,
    COUNT(*) AS total_records
FROM stg_hospitals_clean
GROUP BY `name`, `county`
HAVING COUNT(*) > 1
ORDER BY total_records DESC;

-- inspect the duplicate records
SELECT *
FROM stg_hospitals_clean
WHERE (`Name`, `County`) IN (
    ('Mukavakava', 'Nyeri'),
    ('Mukavakava', 'Kirinyaga'),
    ('Mukavakava', 'Kiambu'),
    ('Mukavakava', 'Migori'),
    ('Mukavakava', 'Garissa'),
    ('Emenyenche dispensary', 'Nyamira'),
    ('Kibunga sub-district Hospital', 'Tharaka Nithi'),
    ('Royal Medical clinic', 'Nakuru'),
    ('Ajam Mission Health centre', 'Kajiado'),
    ('Elwakana Dispensary', 'Kakamega'),
    ('Obwogre Dispensary', 'Siaya')
)
ORDER BY `Name`, `County`;


SELECT *
FROM stg_hospitals_raw
WHERE name = 'Mukavakava';

SELECT name, Officialname, Registration_number, county, constituency, `sub county`, ward
FROM stg_hospitals_clean
WHERE name = 'Mukavakava';

-- replace name = 'Mukavakava' with the officialname in its row
SELECT
	`name` AS current_name,
    Officialname AS corrected_name,
    county,
    constituency,
    `sub county`,
    ward
FROM stg_hospitals_clean
WHERE LOWER(TRIM(`name`)) = 'Mukavakava'
	AND LOWER(TRIM(officialname)) <> 'Mukavakava'
    AND officialname IS NOT NULL
  AND TRIM(officialname) <> ''
  AND LOWER(TRIM(officialname)) NOT IN ('none', 'n/a', 'na', 'null')
ORDER BY county, officialname;
    
-- updating the incorrect names

START TRANSACTION;

UPDATE stg_hospitals_clean
SET `name` = TRIM(`Officialname`)
WHERE LOWER(TRIM(`name`)) = 'Mukavakava'
  AND LOWER(TRIM(Officialname)) <> 'Mukavakava'
  AND Officialname IS NOT NULL
  AND TRIM(Officialname) <> ''
  AND LOWER(TRIM(Officialname)) NOT IN ('none', 'n/a', 'na', 'null');

-- verify changes
SELECT name, officialname, county
FROM stg_hospitals_clean
WHERE name = 'Mukavakava';

-- ============????????????????????????????????????????????

-- ================================================  
--  finding the missing values

SELECT
	COUNT(*) AS total_rows,
    SUM(COALESCE(LOWER(TRIM(`code`)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS code_missing,
	SUM(COALESCE(LOWER(TRIM(`name`)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS name_missing,
	SUM(COALESCE(LOWER(TRIM(officialname)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS official_name_missing,
    SUM(COALESCE(LOWER(TRIM(registration_number)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS registration_number_missing,
    SUM(COALESCE(LOWER(TRIM(`keph level`)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS keph_level_missing,
    SUM(COALESCE(LOWER(TRIM(`facility type`)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS facility_type_missing,
    SUM(COALESCE(LOWER(TRIM(facility_type_category)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS facility_type_category_missing,
    SUM(COALESCE(LOWER(TRIM(`owner`)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS owner_missing,
    SUM(COALESCE(LOWER(TRIM(`owner type`)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS owner_type_missing,
    SUM(COALESCE(LOWER(TRIM(`regulatory body`)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS regulatory_body_missing,
    SUM(COALESCE(LOWER(TRIM(beds)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS beds_missing,
    SUM(COALESCE(LOWER(TRIM(cots)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS cots_missing,
    SUM(COALESCE(LOWER(TRIM(`beds and cots`)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS beds_and_cots_missing,
    SUM(COALESCE(LOWER(TRIM(county)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS county_missing,
	SUM(COALESCE(LOWER(TRIM(constituency)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS county_missing,
    SUM(COALESCE(LOWER(TRIM(`sub county`)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS sub_county_missing,
    SUM(COALESCE(LOWER(TRIM(ward)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS ward_missing,
    SUM(COALESCE(LOWER(TRIM(`operation status`)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS operation_status_missing,
    SUM(COALESCE(LOWER(TRIM(open_whole_day)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS open_whole_day_missing,
    SUM(COALESCE(LOWER(TRIM(open_public_holidays)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS open_public_holidays_missing,
    SUM(COALESCE(LOWER(TRIM(open_weekends)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS open_weekends_missing,
    SUM(COALESCE(LOWER(TRIM(open_late_night)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS open_late_night_missing,
    SUM(COALESCE(LOWER(TRIM(service_names)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS service_names_missing,
    SUM(COALESCE(LOWER(TRIM(approved)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS approved_missing,
    SUM(COALESCE(LOWER(TRIM(`public visible`)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS public_visible_missing,
    SUM(COALESCE(LOWER(TRIM(closed)), '') IN ('', 'none', 'na', 'n/a', 'null')) AS closed_missing
    
FROM stg_hospitals_clean;

-- handling the missing values

-- `code` column
SELECT *
FROM stg_hospitals_clean
WHERE `code` IS NULL OR LOWER(TRIM(`code`)) IN ('', 'none', 'na', 'n/a', 'null')
LIMIT 20;

SET SQL_SAFE_UPDATES = 0;

UPDATE stg_hospitals_clean
SET code = NULL 
WHERE LOWER(TRIM(`code`)) IN ('', 'none', 'na', 'n/a', 'null');


-- registration_number column

SELECT registration_number
FROM stg_hospitals_clean
WHERE LOWER(TRIM(registration_number)) IN ('', 'none', 'na', 'n/a', 'null');

UPDATE stg_hospitals_clean
SET registration_number = NULL
WHERE LOWER(TRIM(registration_number)) IN ('', 'none', 'na', 'n/a', 'null');

-- keph_level_missing  

SELECT `keph level`
FROM stg_hospitals_clean;

UPDATE stg_hospitals_clean
SET `keph level` = NULL 
WHERE LOWER(TRIM(`keph level`)) IN ('', 'none', 'na', 'n/a', 'null');

SET SQL_SAFE_UPDATES = 0;
UPDATE stg_hospitals_clean SET `keph level` = 'Unspecified' 
WHERE `keph level` IS NULL;
SET SQL_SAFE_UPDATES = 1;

-- facility_type_category missing 25

SELECT `facility type`, (facility_type_category)
FROM stg_hospitals_clean;
    
--   inspecting if the facility_type & facility_type_category are similar
SELECT
    COUNT(*) AS total_rows,
    SUM(LOWER(TRIM(`facility type`)) = LOWER(TRIM(facility_type_category))) AS identical,
    SUM(LOWER(TRIM(`facility type`)) != LOWER(TRIM(facility_type_category))) AS different,
    SUM(facility_type_category IS NULL OR LOWER(TRIM(facility_type_category)) IN ('', 'none', 'na', 'n/a', 'null')) AS category_missing
FROM stg_hospitals_clean;    

-- check the different values
SELECT `facility type`, facility_type_category, COUNT(*) AS n
FROM stg_hospitals_clean
WHERE LOWER(TRIM(`facility type`)) != LOWER(TRIM(facility_type_category))
GROUP BY `facility type`, facility_type_category
ORDER BY `facility type`, n DESC;
-- diffrent names on the columns facility_type and facility_type_category suggest the columns have diffrent values

SELECT
	h.*,
    CASE
		WHEN LOWER(TRIM(facility_type_category)) NOT IN ('', 'none', 'na', 'n/a', 'null')
			AND facility_type_category IS NOT NULL
            THEN REPLACE(TRIM(facility_type_category), ' ', ' ') -- to fix 'Primary health  care services'
		WHEN UPPER(TRIM(`facility type`)) IN ('HEALTH CENTRE', 'HOSPITALS', 'NURSING HOME')
			THEN UPPER(TRIM(`facility type`))
		
		WHEN UPPER(TRIM(`facility type`)) = 'DISPENSARY'
            THEN 'Primary health care services'
        WHEN UPPER(TRIM(`facility type`)) IN ('MEDICAL CLINIC', 'MEDICAL CENTER')
            THEN UPPER(TRIM(`facility type`))
        ELSE 'Unknown'
    END AS facility_type_category_clean
FROM stg_hospitals_clean h;

SELECT facility_type_category, COUNT(*)
FROM stg_hospitals_clean
GROUP BY 1;

UPDATE stg_hospitals_clean
SET facility_type_category = NULL
WHERE LOWER(TRIM(facility_type_category)) IN ('', 'none', 'na', 'n/a', 'null');

-- convert the 'none' values to 'NULL'
SELECT facility_type_category
FROM stg_hospitals_clean
WHERE facility_type_category = NULL; -- confirming Null values are filled

-- change facility_type category from  UPPER case to title case
DELIMITER $$

CREATE FUNCTION INITCAP(str VARCHAR(255))
RETURNS VARCHAR(255)
DETERMINISTIC
BEGIN
	DECLARE c CHAR(1);
    DECLARE res VARCHAR(255) DEFAULT '';
    DECLARE i INT DEFAULT 1;
    DECLARE bool INT DEFAULT 1;

    WHILE i <= LENGTH(str) DO
        SET c = SUBSTRING(str, i, 1);
        IF bool = 1 THEN
            SET res = CONCAT(res, UPPER(c));
            SET bool = 0;
        ELSE
            SET res = CONCAT(res, LOWER(c));
        END IF;
        
        IF c = ' ' THEN
            SET bool = 1;
        END IF;
        
        SET i = i + 1;
    END WHILE;
    
    RETURN res;
END$$

DELIMITER ;

UPDATE stg_hospitals_clean
SET facility_type_category = INITCAP(facility_type_category);
    
SELECT *
FROM stg_hospitals_clean;    

-- ==== regulatory_body_missing 625===
SELECT `regulatory body`
FROM stg_hospitals_clean;

UPDATE stg_hospitals_clean
SET `regulatory body` = NULL 
WHERE LOWER(TRIM(`regulatory body`)) IN ('', 'none', 'na', 'n/a', 'null');

SELECT `regulatory body`
FROM stg_hospitals_clean; -- NULL values filled

-- service_names column
SELECT COUNT(*) AS total_rows,
		SUM(service_names IS NULL OR LOWER(TRIM(service_names)) IN ('', 'none', 'na', 'n/a', 'null')) AS missing
FROM stg_hospitals_clean;

-- 	service_names column is 100% missing therefore drop the column
ALTER TABLE stg_hospitals_clean DROP COLUMN service_names;

-- standardizing county names in hospital table

UPDATE stg_hospitals_clean
SET name = REPLACE(REPLACE(TRIM(name), '-', ' '), '''', '');

SET SQL_SAFE_UPDATES = 1;


-- inserting the missing Kenyatta National Hospital row

-- confirm the row is missing
SELECT *
FROM stg_hospitals_clean
WHERE name LIKE '%Kenyatta%';
			-- Kenyatta National hospital is missing
             
--  Insert the row
USE health_access_kenya_db;

-- Confirm it's missing first (should return 0)
SELECT COUNT(*) FROM stg_hospitals_clean WHERE code = '13023';

INSERT INTO stg_hospitals_clean
SET code                   = '13023',
    name                   = 'Kenyatta National Hospital',
    officialname           = 'Kenyatta National Hospital',
    registration_number    = 'None',
    `keph level`             = 'Level 6',
    `facility type`          = 'Comprehensive Teaching & Tertiary Referral Hospital',
    facility_type_category = 'HOSPITALS',
    owner                  = 'Ministry of Health',
    `owner type`             = 'Ministry of Health',
    `regulatory body`        = 'Ministry of Health',
    beds                   = '1455',
    cots                   = '427',
    `beds and cots`          = '1882',
    county                 = 'Nairobi',
    constituency           = 'Kibra',
    `sub county`             = 'Kibra',
    ward                   = 'Woodley/Kenyatta Golf Course',
    `operation status`       = 'Operational',
    open_whole_day         = 'Yes',
    open_public_holidays   = 'No',
    open_weekends          = 'Yes',
    open_late_night        = 'No',
    approved               = 'Yes',
    `public visible`         = 'Yes',
    closed                 = 'No';

SELECT COUNT(*) FROM stg_hospitals_clean;   -- 12,394

-- Verify
SELECT COUNT(*) FROM stg_hospitals_clean;   -- 12,394
SELECT code, name, beds, cots, `beds and cots`, county
FROM stg_hospitals_clean WHERE code = '13023';