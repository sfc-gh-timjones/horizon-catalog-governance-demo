/***************************************************************************************************
| H | O | R | I | Z | O | N |   | D | E | M | O |

  Demo 4: Data Quality & Trust
  "Continuously validate data quality with DMFs + Expectations."

  What you'll show:
    - The SALES_LEADS table: 3000 rows of intentionally messy CRM data
    - System DMFs: NULL_COUNT, BLANK_COUNT, DUPLICATE_COUNT, ROW_COUNT, ACCEPTED_VALUES
    - Custom DMF: DEAL_AMOUNT_OUT_OF_RANGE (business-rule validation)
    - EXPECTATION clauses: pass/fail quality checks on each DMF
    - SYSTEM$EVALUATE_DATA_QUALITY_EXPECTATIONS: one-shot report card
    - Historical monitoring results for trend analysis

  Setup references:
    - SALES_LEADS table creation:             0-setup.sql lines 216-296
    - DMFs + Expectations on SALES_LEADS:     1-data-engineer.sql lines 59-109
    - Custom DEAL_AMOUNT_OUT_OF_RANGE DMF:    1-data-engineer.sql lines 96-109
***************************************************************************************************/

USE ROLE HRZN_DATA_ENGINEER;
USE WAREHOUSE HRZN_WH;
USE DATABASE HRZN_DB;
USE SCHEMA HRZN_SCH;

/*=============================================================================
  ACT 1: EXPLORE THE DIRTY DATA
  
  SALES_LEADS has 3000 synthetic CRM records with quality issues baked in
  that increase linearly (later rows are dirtier). Let's look at the mess.
  
  Setup ref: 0-setup.sql lines 216-296 (SALES_LEADS table)
=============================================================================*/

SELECT * FROM HRZN_DB.HRZN_SCH.SALES_LEADS;

-- Spot-check: rows with NULL emails
SELECT LEAD_ID, LEAD_NAME, EMAIL, STATUS
FROM HRZN_DB.HRZN_SCH.SALES_LEADS
WHERE EMAIL IS NULL
ORDER BY LEAD_ID
LIMIT 10;

-- Spot-check: rows with blank phone numbers
SELECT LEAD_ID, LEAD_NAME, PHONE, COMPANY
FROM HRZN_DB.HRZN_SCH.SALES_LEADS
WHERE PHONE = ''
ORDER BY LEAD_ID
LIMIT 10;

-- Spot-check: duplicate emails (all pointing to same address)
SELECT LEAD_ID, EMAIL, COMPANY, STATUS
FROM HRZN_DB.HRZN_SCH.SALES_LEADS
WHERE EMAIL = 'duplicate_lead@example.com'
ORDER BY LEAD_ID;

-- Spot-check: invalid statuses (not in our allowed list)
SELECT LEAD_ID, STATUS, DEAL_AMOUNT
FROM HRZN_DB.HRZN_SCH.SALES_LEADS
WHERE STATUS NOT IN ('New', 'Contacted', 'Qualified', 'Proposal', 'Closed Won')
ORDER BY LEAD_ID;

-- Spot-check: out-of-range deal amounts (negative or > $1M)
SELECT LEAD_ID, DEAL_AMOUNT, STATUS, COMPANY
FROM HRZN_DB.HRZN_SCH.SALES_LEADS
WHERE DEAL_AMOUNT < 0 OR DEAL_AMOUNT > 1000000
ORDER BY LEAD_ID;

/*=============================================================================
  ACT 2: RUN INLINE DMFs — SEE THE NUMBERS
  
  System and custom DMFs run against live data and return counts of
  quality violations. These are the same functions that run on schedule.
  
  Setup ref: 1-data-engineer.sql lines 68-109 (DMFs + expectations)
=============================================================================*/

SELECT
    (SELECT COUNT(*) FROM HRZN_DB.HRZN_SCH.SALES_LEADS)                              AS total_rows,
    SNOWFLAKE.CORE.NULL_COUNT(SELECT EMAIL FROM HRZN_DB.HRZN_SCH.SALES_LEADS)        AS null_emails,
    SNOWFLAKE.CORE.BLANK_COUNT(SELECT PHONE FROM HRZN_DB.HRZN_SCH.SALES_LEADS)       AS blank_phones,
    SNOWFLAKE.CORE.DUPLICATE_COUNT(SELECT EMAIL FROM HRZN_DB.HRZN_SCH.SALES_LEADS)   AS duplicate_emails,
    HRZN_DB.HRZN_SCH.DEAL_AMOUNT_OUT_OF_RANGE(
        SELECT DEAL_AMOUNT FROM HRZN_DB.HRZN_SCH.SALES_LEADS
    )                                                                                 AS bad_deal_amounts;

/*=============================================================================
  ACT 3: DMF REGISTRY — WHAT'S ATTACHED?
  
  Show all DMFs registered on SALES_LEADS, their schedule, and status.
  
  Setup ref: 1-data-engineer.sql lines 59-109 (schedule + DMF attachment)
=============================================================================*/

SELECT metric_name, ref_entity_name, schedule, schedule_status
FROM TABLE(information_schema.data_metric_function_references(
    ref_entity_name => 'HRZN_DB.HRZN_SCH.SALES_LEADS',
    ref_entity_domain => 'TABLE'));

/*=============================================================================
  ACT 4: EXPECTATIONS REPORT CARD
  
  This is the headline: SYSTEM$EVALUATE_DATA_QUALITY_EXPECTATIONS runs
  every DMF with its EXPECTATION clause and returns a pass/fail verdict.
  
  Our SALES_LEADS data is intentionally dirty, so most expectations FAIL:
    - no_null_emails        → FAIL  (we have ~115 NULL emails)
    - no_blank_phones       → FAIL  (we have ~103 blank phones)
    - no_duplicate_emails   → FAIL  (we have ~71 duplicates)
    - minimum_lead_volume   → PASS  (3000 rows ≥ 2500 threshold)
    - no_invalid_statuses   → FAIL  (we have ~63 garbage statuses)
    - no_out_of_range_deals → FAIL  (we have ~37 bad amounts)
=============================================================================*/

SELECT *
FROM TABLE(SYSTEM$EVALUATE_DATA_QUALITY_EXPECTATIONS(
    REF_ENTITY_NAME => 'HRZN_DB.HRZN_SCH.SALES_LEADS'));

/*=============================================================================
  ACT 5: HISTORICAL MONITORING RESULTS
  
  Every scheduled DMF run stores its result. Over time this becomes a
  trend line showing whether data quality is improving or degrading.
  Results appear after the first TRIGGER_ON_CHANGES run completes.
  
  Setup ref: 1-data-engineer.sql line 60 (TRIGGER_ON_CHANGES schedule)
=============================================================================*/

SELECT
    measurement_time,
    table_name,
    metric_name,
    value
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
WHERE table_database = 'HRZN_DB'
    AND table_name = 'SALES_LEADS'
ORDER BY measurement_time DESC;

/*=============================================================================
  ACT 6: INJECT BAD DATA & RE-EVALUATE
  
  Simulate a bad data load. Insert 200 rows of garbage, then re-run the
  expectations to show how the report card catches regressions in real time.
  ⚠ Cleanup at end restores original 3000 rows for repeatability.
=============================================================================*/

INSERT INTO HRZN_DB.HRZN_SCH.SALES_LEADS
    (LEAD_ID, LEAD_NAME, EMAIL, PHONE, COMPANY, STATUS, DEAL_AMOUNT, LEAD_SOURCE, CREATED_AT)
SELECT
    3000 + ROW_NUMBER() OVER (ORDER BY SEQ4()) AS LEAD_ID,
    'BadLead_' || ROW_NUMBER() OVER (ORDER BY SEQ4()) AS LEAD_NAME,
    NULL                       AS EMAIL,
    ''                         AS PHONE,
    'Fake Corp'                AS COMPANY,
    'GARBAGE'                  AS STATUS,
    -99999.99                  AS DEAL_AMOUNT,
    'Unknown'                  AS LEAD_SOURCE,
    CURRENT_TIMESTAMP()        AS CREATED_AT
FROM TABLE(GENERATOR(ROWCOUNT => 200));

-- Re-run the expectations — violations should jump up
SELECT *
FROM TABLE(SYSTEM$EVALUATE_DATA_QUALITY_EXPECTATIONS(
    REF_ENTITY_NAME => 'HRZN_DB.HRZN_SCH.SALES_LEADS'));

-- Show the new inline counts
SELECT
    (SELECT COUNT(*) FROM HRZN_DB.HRZN_SCH.SALES_LEADS)                              AS total_rows,
    SNOWFLAKE.CORE.NULL_COUNT(SELECT EMAIL FROM HRZN_DB.HRZN_SCH.SALES_LEADS)        AS null_emails,
    SNOWFLAKE.CORE.BLANK_COUNT(SELECT PHONE FROM HRZN_DB.HRZN_SCH.SALES_LEADS)       AS blank_phones,
    SNOWFLAKE.CORE.DUPLICATE_COUNT(SELECT EMAIL FROM HRZN_DB.HRZN_SCH.SALES_LEADS)   AS duplicate_emails,
    HRZN_DB.HRZN_SCH.DEAL_AMOUNT_OUT_OF_RANGE(
        SELECT DEAL_AMOUNT FROM HRZN_DB.HRZN_SCH.SALES_LEADS
    )                                                                                 AS bad_deal_amounts;

/*=============================================================================
  CLEANUP: REMOVE INJECTED ROWS
  
  Restore the table to its original 3000 rows so the demo is repeatable.
=============================================================================*/

DELETE FROM HRZN_DB.HRZN_SCH.SALES_LEADS WHERE LEAD_ID > 3000;
