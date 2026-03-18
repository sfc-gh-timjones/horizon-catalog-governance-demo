/***************************************************************************************************
| H | O | R | I | Z | O | N |   | D | E | M | O |

  Demo 3: Privacy & Aggregation
  "Protect individuals even when data is accessible."

  What you'll show:
    - Aggregation policy: must aggregate with 100+ group size, no individual records
    - Differential privacy: noisy aggregates, row-level access blocked, privacy budget
    - AI_REDACT for unstructured text (50+ PII types, no regex)
    - Partial redaction (choose which PII types to redact)
    - Role-based redaction view: governor sees PII, analyst sees pre-redacted version
    - Sentiment analysis on redacted data (safe analytics without PII exposure)

  Setup references:
    - Aggregation policy:                 2-data-governor.sql lines 360-369
    - EMPLOYEES table (synthetic data):   0-setup.sql lines 313-341
    - Privacy policy + entity key:        0-setup.sql lines 405-427
    - Customer feedback data + AI_REDACT: 5-ai-redact.sql lines 20-97
    - Role-based redaction view:          5-ai-redact.sql lines 143-155
    - Sentiment analysis:                 5-ai-redact.sql lines 108-120
***************************************************************************************************/

USE WAREHOUSE HRZN_WH;
USE DATABASE HRZN_DB;
USE SCHEMA HRZN_SCH;

/*=============================================================================
  AGGREGATION POLICY — k-Anonymity Enforcement
  
  DATA_USER cannot SELECT individual records from CUSTOMER_ORDERS.
  They CAN run aggregates — but only when groups contain 100+ rows.
  This prevents re-identification attacks on small groups.
  
  Setup ref: 2-data-governor.sql lines 360-369
  Note: Re-applying policy for this demo section.
  ⚠ If script stops before cleanup, re-run from line 55 or run 0-setup.sql.
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;

-- GOVERNOR: unrestricted access
SELECT TOP 100 * FROM HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS;

ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS
    SET AGGREGATION POLICY HRZN_DB.TAG_SCHEMA.aggregation_policy;

USE ROLE HRZN_DATA_USER;

-- FAILS: can't select individual records
SELECT TOP 100 * FROM HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS;

-- WORKS: aggregate with large enough groups
SELECT ORDER_CURRENCY, SUM(ORDER_AMOUNT) AS total_amount
FROM HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS GROUP BY ORDER_CURRENCY;

USE ROLE HRZN_DATA_GOVERNOR;

ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS UNSET AGGREGATION POLICY;

/*=============================================================================
  DIFFERENTIAL PRIVACY — Noisy Aggregates + Privacy Budget
  
  The EMPLOYEES table is protected by a privacy policy.
  Individual rows are blocked — only aggregates are allowed.
  Noise is injected automatically to prevent re-identification.
  A weekly privacy budget limits how many queries analysts can run.
  
  Setup ref: 0-setup.sql lines 204-237 (EMPLOYEES table), lines 286-320 (privacy policy + domains)
=============================================================================*/

-- GOVERNOR: exact results, no noise
USE ROLE HRZN_DATA_GOVERNOR;

SELECT
    DEPARTMENT,
    COUNT(DISTINCT EMPLOYEE_ID) AS headcount,
    ROUND(AVG(SALARY), 2) AS avg_salary,
    ROUND(AVG(BONUS), 2) AS avg_bonus
FROM HRZN_DB.HRZN_SCH.EMPLOYEES
GROUP BY DEPARTMENT
ORDER BY avg_salary DESC;

-- DATA USER: individual records blocked
USE ROLE HRZN_DATA_USER;

SELECT * FROM HRZN_DB.HRZN_SCH.EMPLOYEES LIMIT 5;
-- ^ Fails: "Query not supported" — row-level access is blocked

-- DATA USER: noisy aggregates with confidence intervals
SELECT
    department,
    COUNT(salary) AS headcount,
    DP_INTERVAL_LOW(headcount) AS headcount_low,
    DP_INTERVAL_HIGH(headcount) AS headcount_high
FROM (
    SELECT EMPLOYEE_ID, ANY_VALUE(DEPARTMENT) AS department, ANY_VALUE(SALARY) AS salary
    FROM HRZN_DB.HRZN_SCH.EMPLOYEES
    GROUP BY EMPLOYEE_ID
)
GROUP BY department;

-- DATA USER: how many employees earn $100K–$150K per department?
SELECT
    department,
    COUNT(salary) AS emp_count,
    DP_INTERVAL_LOW(emp_count) AS count_low,
    DP_INTERVAL_HIGH(emp_count) AS count_high
FROM (
    SELECT EMPLOYEE_ID, ANY_VALUE(DEPARTMENT) AS department, ANY_VALUE(SALARY) AS salary
    FROM HRZN_DB.HRZN_SCH.EMPLOYEES
    GROUP BY EMPLOYEE_ID
)
WHERE salary > 100000 AND salary < 150000
GROUP BY department;

-- Privacy budget: how many queries remain before the weekly reset?
-- (Must run as DATA_USER — the entity-key role that consumes DP budget)
USE ROLE HRZN_DATA_USER;

SELECT * FROM TABLE(SNOWFLAKE.DATA_PRIVACY.ESTIMATE_REMAINING_DP_AGGREGATES('HRZN_DB.HRZN_SCH.EMPLOYEES'));

/*=============================================================================
  AI_REDACT — Unstructured PII Protection
  
  Structured columns are handled by classification + masking.
  Unstructured text (feedback, emails, tickets) needs AI_REDACT.
  Detects 50+ PII types automatically — names, emails, phones,
  SSNs, addresses, credit cards, dates of birth.
  
  Setup ref: 5-ai-redact.sql lines 20-97
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;

-- Live AI_REDACT: watch PII get stripped in real time
SELECT ORDER_ID,
       CUSTOMER_FEEDBACK AS original_feedback,
       SNOWFLAKE.CORTEX.AI_REDACT(CUSTOMER_FEEDBACK) AS redacted_feedback
FROM HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS
WHERE CUSTOMER_FEEDBACK NOT LIKE 'Standard order%'
  AND CUSTOMER_FEEDBACK IS NOT NULL
LIMIT 10;

-- Pre-computed version (same result, instant — built during setup)
-- Run below code if you don't want to wait 20+ seconds for above code to run.
/*
SELECT ORDER_ID, original_feedback, redacted_feedback
FROM HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_REDACTED
WHERE original_feedback NOT LIKE 'Standard order%'
LIMIT 10;
*/

/*=============================================================================
  PARTIAL REDACTION — Choose Which PII Types to Redact
  
  Full redaction replaces ALL PII. Partial redaction lets you keep
  specific types (e.g., redact names and emails, but keep phone numbers).
  
  Setup ref: 5-ai-redact.sql lines 126-133
=============================================================================*/

WITH feedback_sample AS (
    SELECT 'Contact John Smith at john.smith@email.com or call 555-123-4567 for updates.' AS text
)
SELECT
    text AS original,
    SNOWFLAKE.CORTEX.AI_REDACT(text)::VARCHAR AS full_redaction,
    SNOWFLAKE.CORTEX.AI_REDACT(text, ['NAME', 'EMAIL'])::VARCHAR AS partial_redaction
FROM feedback_sample;

/*=============================================================================
  SAFE SENTIMENT ANALYSIS ON REDACTED DATA
  
  Run analytics on customer feedback without exposing any PII.
  Sentiment scores are identical whether you use original or redacted text.
  
  Setup ref: 5-ai-redact.sql lines 108-120
=============================================================================*/

SELECT
    redacted_feedback,
    SNOWFLAKE.CORTEX.SENTIMENT(redacted_feedback) AS sentiment_score,
    CASE
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(redacted_feedback) > 0.5 THEN 'Positive'
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(redacted_feedback) < -0.5 THEN 'Negative'
        ELSE 'Neutral'
    END AS sentiment_category
FROM HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_REDACTED
WHERE redacted_feedback NOT LIKE 'Standard order%'
QUALIFY ROW_NUMBER() OVER (PARTITION BY MOD(ORDER_ID::INT, 10) ORDER BY ORDER_ID) = 1
ORDER BY sentiment_score DESC;

/*=============================================================================
  ROLE-BASED REDACTION VIEW
  
  CUSTOMER_FEEDBACK_SECURE shows original text to governors
  and pre-redacted text to everyone else. One view, automatic switching.
  
  Setup ref: 5-ai-redact.sql lines 143-155
=============================================================================*/

/*logic in setup (see reference lines above).

    CASE
        WHEN CURRENT_ROLE() IN ('HRZN_DATA_GOVERNOR', 'ACCOUNTADMIN')
        THEN original_feedback
        ELSE redacted_feedback
    END AS CUSTOMER_FEEDBACK,
*/

-- Governor sees original PII
USE ROLE HRZN_DATA_GOVERNOR;

SELECT ORDER_ID, CUSTOMER_FEEDBACK
FROM HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_SECURE
WHERE CUSTOMER_FEEDBACK NOT LIKE 'Standard order%' LIMIT 3;

-- Data user sees redacted version
USE ROLE HRZN_DATA_USER;

SELECT ORDER_ID, CUSTOMER_FEEDBACK
FROM HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_SECURE
WHERE CUSTOMER_FEEDBACK NOT LIKE 'Standard order%' LIMIT 3;
