/***************************************************************************************************
| H | O | R | I | Z | O | N |   | D | E | M | O |

  Demo 1: Discovery & Classification
  "Snowflake automatically finds and labels sensitive data."

  What you'll show:
    - AI classification tagged every column with a sensitivity level
    - Tag propagation: labels follow data through CTAS automatically
    - Live AI classification with custom classifiers (credit cards)

  Setup references:
    - AI classification + tag creation:   2-data-governor.sql lines 38-119
    - Custom credit card classifier:      2-data-governor.sql lines 148-165
    - Tag propagation (CTAS):             2-data-governor.sql lines 288-306
    - Classification profile config:      2-data-governor.sql lines 55-105
    - Tag definition (PROPAGATE = ON):    2-data-governor.sql lines 38-41
***************************************************************************************************/

USE ROLE HRZN_DATA_GOVERNOR;
USE WAREHOUSE HRZN_WH;
USE DATABASE HRZN_DB;
USE SCHEMA HRZN_SCH;

/*=============================================================================
  AI CLASSIFICATION RESULTS
  
  Snowflake AI scanned the CUSTOMER table and automatically assigned
  a DATA_CLASSIFICATION tag to every column based on its content:
    PII        — EMAIL, SSN (must be encrypted/erased under GDPR, HIPAA)
    RESTRICTED — BIRTHDATE, PHONE_NUMBER (special categories)
    SENSITIVE  — CITY, FIRST_NAME, LAST_NAME, STREET_ADDRESS, ZIP
    INTERNAL   — JOB (business data, low risk)
=============================================================================*/

SELECT TOP 50 * FROM HRZN_DB.HRZN_SCH.CUSTOMER;

SELECT COLUMN_NAME, TAG_VALUE AS CLASSIFICATION_LEVEL
FROM TABLE(
    INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'HRZN_DB.HRZN_SCH.CUSTOMER', 'table'
    )
)
WHERE TAG_NAME = 'DATA_CLASSIFICATION'
ORDER BY
    CASE TAG_VALUE
        WHEN 'PII' THEN 1 WHEN 'RESTRICTED' THEN 2
        WHEN 'SENSITIVE' THEN 3 WHEN 'INTERNAL' THEN 4
        WHEN 'PUBLIC' THEN 5
    END, COLUMN_NAME;

/*=============================================================================
  TAG PROPAGATION — Labels Follow the Data
  
  CUSTOMER_COPY was created with CREATE TABLE ... AS SELECT * FROM CUSTOMER.
  All 9 DATA_CLASSIFICATION tags propagated automatically.
  No manual tagging. No governance gaps.
  
  Setup ref: 2-data-governor.sql lines 288-306
=============================================================================*/

CREATE OR REPLACE TABLE HRZN_DB.HRZN_SCH.CUSTOMER_COPY AS
SELECT * FROM HRZN_DB.HRZN_SCH.CUSTOMER;

SELECT TOP 50 * FROM HRZN_DB.HRZN_SCH.CUSTOMER_COPY;

SELECT COLUMN_NAME, TAG_VALUE AS CLASSIFICATION_LEVEL
FROM TABLE(
    INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'HRZN_DB.HRZN_SCH.CUSTOMER_COPY', 'table'
    )
)
WHERE TAG_NAME = 'DATA_CLASSIFICATION'
ORDER BY
    CASE TAG_VALUE
        WHEN 'PII' THEN 1 WHEN 'RESTRICTED' THEN 2
        WHEN 'SENSITIVE' THEN 3 WHEN 'INTERNAL' THEN 4
    END, COLUMN_NAME;

/*=============================================================================
  LIVE AI CLASSIFICATION
  
  Two ways to classify data in Snowflake:
  
  1. AUTOMATIC — A Classification Profile runs on a schedule and
     automatically tags new/changed columns. That's how the CUSTOMER
     table was originally tagged during setup.
     (Setup ref: 2-data-governor.sql lines 55-105)
  
  2. MANUAL — SYSTEM$CLASSIFY runs classification on-demand.
     Without 'auto_tag', it returns recommendations only (read-only).
     With 'auto_tag': true, it permanently applies the tags.
  
  Below we run it manually WITHOUT auto_tag — a safe, live preview.
  A custom regex classifier for credit card formats (Mastercard, Amex)
  is included to enhance detection accuracy.
  
  Setup ref: 2-data-governor.sql lines 148-165
=============================================================================*/

-- Read-only: returns recommendations without tagging anything
CALL SYSTEM$CLASSIFY(
    'HRZN_DB.HRZN_SCH.CUSTOMER',
    {'custom_classifiers': ['HRZN_DB.CLASSIFIERS.CREDITCARD']}
);

-- Uncomment below to permanently apply tags:
-- CALL SYSTEM$CLASSIFY(
--     'HRZN_DB.HRZN_SCH.CUSTOMER',
--     {'custom_classifiers': ['HRZN_DB.CLASSIFIERS.CREDITCARD'], 'auto_tag': true}
-- );

SELECT
    col.key AS COLUMN_NAME,
    col.value:recommendation:semantic_category::STRING AS SEMANTIC_CATEGORY,
    col.value:recommendation:privacy_category::STRING AS PRIVACY_CATEGORY,
    col.value:recommendation:confidence::STRING AS CONFIDENCE
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) r,
    LATERAL FLATTEN(input => r."SYSTEM$CLASSIFY":classification_result) col
ORDER BY col.key;
