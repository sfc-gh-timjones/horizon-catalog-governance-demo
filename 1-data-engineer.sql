/***************************************************************************************************
| H | O | R | I | Z | O | N |   | L | A | B | S |

Demo:         Horizon Catalog - Lab 1: Data Engineer (RBAC + Data Quality)
Version:      HLab v2.1 (Idempotent)
***************************************************************************************************/

/*=============================================================================
  RBAC & DAC FUNDAMENTALS
=============================================================================*/

USE ROLE HRZN_DATA_ENGINEER;
USE WAREHOUSE HRZN_WH;
USE DATABASE HRZN_DB;
USE SCHEMA HRZN_SCH;

SHOW ROLES;

SELECT "name", "comment"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "name" IN ('ORGADMIN','ACCOUNTADMIN','SYSADMIN','USERADMIN','SECURITYADMIN','PUBLIC');

/*=============================================================================
  ROLE CREATION + GRANT DEMO
  
  Demonstrates DAC: create a role, grant access incrementally.
=============================================================================*/

USE ROLE USERADMIN;
CREATE OR REPLACE ROLE HRZN_DATA_ANALYST COMMENT = 'Analyst Role';

USE ROLE SECURITYADMIN;
GRANT ALL ON WAREHOUSE HRZN_WH TO ROLE HRZN_DATA_ANALYST;
GRANT OPERATE, USAGE ON WAREHOUSE HRZN_WH TO ROLE HRZN_DATA_ANALYST;

GRANT ROLE HRZN_DATA_ANALYST TO USER identifier(CURRENT_USER());

GRANT USAGE ON DATABASE HRZN_DB TO ROLE HRZN_DATA_ANALYST;
GRANT USAGE ON ALL SCHEMAS IN DATABASE HRZN_DB TO ROLE HRZN_DATA_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA HRZN_DB.HRZN_SCH TO ROLE HRZN_DATA_ANALYST;
GRANT SELECT ON ALL VIEWS IN SCHEMA HRZN_DB.HRZN_SCH TO ROLE HRZN_DATA_ANALYST;

USE ROLE HRZN_DATA_ANALYST;
SELECT * FROM HRZN_DB.HRZN_SCH.CUSTOMER LIMIT 5;

/*=============================================================================
  DATA QUALITY MONITORING — SALES_LEADS Table
  
  The SALES_LEADS table has intentional quality issues baked in:
    ~115 NULL emails, ~103 blank phones, ~71 duplicate emails,
    ~63 invalid statuses, ~37 out-of-range deal amounts.
  
  We attach system DMFs + expectations to create automated pass/fail
  quality checks, plus a custom DMF for business-rule validation.
=============================================================================*/

USE ROLE HRZN_DATA_ENGINEER;

ALTER TABLE HRZN_DB.HRZN_SCH.SALES_LEADS
    SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';

/*-- System DMFs with Expectations ------------------------------------------
  Each DMF measures a quality dimension. The EXPECTATION clause defines
  the pass/fail threshold. When the DMF value violates the expectation,
  Snowflake records it as an expectation violation.
---------------------------------------------------------------------------*/

ALTER TABLE HRZN_DB.HRZN_SCH.SALES_LEADS
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (EMAIL)
    EXPECTATION no_null_emails (VALUE = 0);

ALTER TABLE HRZN_DB.HRZN_SCH.SALES_LEADS
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.BLANK_COUNT ON (PHONE)
    EXPECTATION no_blank_phones (VALUE = 0);

ALTER TABLE HRZN_DB.HRZN_SCH.SALES_LEADS
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT ON (EMAIL)
    EXPECTATION no_duplicate_emails (VALUE = 0);

ALTER TABLE HRZN_DB.HRZN_SCH.SALES_LEADS
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ()
    EXPECTATION minimum_lead_volume (VALUE >= 2500);

ALTER TABLE HRZN_DB.HRZN_SCH.SALES_LEADS
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES ON (
        STATUS,
        STATUS -> STATUS IN ('New', 'Contacted', 'Qualified', 'Proposal', 'Closed Won')
    )
    EXPECTATION no_invalid_statuses (VALUE = 0);

/*-- Custom DMF — Deal Amount Out of Range ----------------------------------
  Business rule: deal amounts must be between $0 and $1,000,000.
  Anything outside that range is a data quality issue.
---------------------------------------------------------------------------*/

CREATE OR REPLACE DATA METRIC FUNCTION HRZN_DB.HRZN_SCH.DEAL_AMOUNT_OUT_OF_RANGE(
    IN_TABLE TABLE(IN_COL FLOAT)
)
RETURNS NUMBER
AS
$$
    SELECT COUNT_IF(IN_COL < 0 OR IN_COL > 1000000) FROM IN_TABLE
$$;

GRANT USAGE ON FUNCTION HRZN_DB.HRZN_SCH.DEAL_AMOUNT_OUT_OF_RANGE(TABLE(FLOAT)) TO ROLE PUBLIC;

ALTER TABLE HRZN_DB.HRZN_SCH.SALES_LEADS
    ADD DATA METRIC FUNCTION HRZN_DB.HRZN_SCH.DEAL_AMOUNT_OUT_OF_RANGE ON (DEAL_AMOUNT)
    EXPECTATION no_out_of_range_deals (VALUE = 0);

/*-- Verify DMF schedule + associations ------------------------------------*/

SELECT metric_name, ref_entity_name, schedule, schedule_status
FROM TABLE(information_schema.data_metric_function_references(
    ref_entity_name => 'HRZN_DB.HRZN_SCH.SALES_LEADS',
    ref_entity_domain => 'TABLE'));

/*-- Inline DMF check — see current quality stats --------------------------*/

SELECT
    (SELECT COUNT(*) FROM HRZN_DB.HRZN_SCH.SALES_LEADS)                              AS total_rows,
    SNOWFLAKE.CORE.NULL_COUNT(SELECT EMAIL FROM HRZN_DB.HRZN_SCH.SALES_LEADS)        AS null_emails,
    SNOWFLAKE.CORE.BLANK_COUNT(SELECT PHONE FROM HRZN_DB.HRZN_SCH.SALES_LEADS)       AS blank_phones,
    SNOWFLAKE.CORE.DUPLICATE_COUNT(SELECT EMAIL FROM HRZN_DB.HRZN_SCH.SALES_LEADS)   AS duplicate_emails,
    HRZN_DB.HRZN_SCH.DEAL_AMOUNT_OUT_OF_RANGE(
        SELECT DEAL_AMOUNT FROM HRZN_DB.HRZN_SCH.SALES_LEADS
    )                                                                                 AS bad_deal_amounts;

/*-- Evaluate expectations — pass/fail report card -------------------------*/

SELECT *
FROM TABLE(SYSTEM$EVALUATE_DATA_QUALITY_EXPECTATIONS(
    REF_ENTITY_NAME => 'HRZN_DB.HRZN_SCH.SALES_LEADS'));

/*-- Historical results (populated after first scheduled run) ---------------*/

SELECT
    measurement_time,
    table_name,
    metric_name,
    value
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
WHERE table_database = 'HRZN_DB'
    AND table_name = 'SALES_LEADS'
ORDER BY measurement_time DESC;
