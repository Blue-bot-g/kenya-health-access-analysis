CREATE DATABASE IF NOT EXISTS health_access_kenya_db;
USE health_access_kenya_db;

DROP TABLE IF EXISTS kmhfl_hospitals_beds_2020;
CREATE TABLE kmhfl_hospitals_beds_2020(
	`code` VARCHAR(50),
    `name` VARCHAR(255),
    officialname VARCHAR(255),
    registration_number VARCHAR(100),
    keph_level VARCHAR(50),
    facility_type VARCHAR(100),
    facility_type_category VARCHAR(100),
    owner VARCHAR(255),
    owner_type VARCHAR(255),
    regulatory_body VARCHAR(255),
    beds INT,
    cots INT,
    beds_and_cots INT,
    county VARCHAR(100),
    sub_county VARCHAR(100),
    ward VARCHAR(100),
    operation_status VARCHAR(100),
    open_whole_day VARCHAR(20),
    open_public_holidays VARCHAR(20),
    open_weekends VARCHAR(20),
    open_late_night VARCHAR(20),
    service_names TEXT,
	approved VARCHAR(20),
	public_visible VARCHAR(20),
	closed VARCHAR(20)
    );
    

    
    DROP TABLE IF EXISTS knbs_county_population_2019;
    
    CREATE TABLE knbs_county_population_2019(
	`name` VARCHAR(100),
	population          BIGINT,
    land_area_sq_km     DECIMAL(12,2),
    population_density  DECIMAL(12,2)
);


