/***************************************************************************************************
| H | O | R | I | Z | O | N |   | D | E | M | O |

  Demo 1: Discovery & Classification
  "Snowflake automatically finds and labels sensitive data."

  What you'll show:
    - AI classification tagged every column with a sensitivity level
    - Custom classifiers detect business-specific patterns (credit cards)
    - Tag propagation: labels follow data through CTAS automatically

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
  CUSTOM CLASSIFIER — Credit Card Detection
  
  Beyond built-in AI, you can add regex-based classifiers
  for business-specific patterns (Mastercard, Amex, etc.)
  
  Setup ref: 2-data-governor.sql lines 148-165
=============================================================================*/

SELECT SYSTEM$GET_TAG('snowflake.core.semantic_category','HRZN_DB.HRZN_SCH.CUSTOMER.CREDITCARD','column')
    AS creditcard_classification;

/*=============================================================================
  TAG PROPAGATION — Labels Follow the Data
  
  CUSTOMER_COPY was created with CREATE TABLE ... AS SELECT * FROM CUSTOMER.
  All 9 DATA_CLASSIFICATION tags propagated automatically.
  No manual tagging. No governance gaps.
  
  Setup ref: 2-data-governor.sql lines 288-306
=============================================================================*/

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
