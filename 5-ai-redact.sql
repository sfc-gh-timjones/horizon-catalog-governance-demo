/***************************************************************************************************
| H | O | R | I | Z | O | N |   | L | A | B | S |

Demo:         Horizon Catalog - Lab 5: AI_REDACT for Unstructured PII
Version:      HLab v2.1 (Idempotent)
***************************************************************************************************/

USE ROLE HRZN_DATA_GOVERNOR;
USE WAREHOUSE HRZN_WH;
USE DATABASE HRZN_DB;
USE SCHEMA HRZN_SCH;

/*=============================================================================
  PREPARE CUSTOMER FEEDBACK DATA WITH EMBEDDED PII
  
  Unstructured text where classification can't help —
  AI_REDACT automatically detects 50+ PII types in free-form text.
=============================================================================*/

ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS
    ADD COLUMN IF NOT EXISTS CUSTOMER_FEEDBACK VARCHAR;

UPDATE HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS
SET CUSTOMER_FEEDBACK =
    CASE
        WHEN MOD(ORDER_ID::INT, 10) = 0 THEN
            'Customer John Smith called from 555-123-4567 about order. Email: john.smith@email.com. Very satisfied!'
        WHEN MOD(ORDER_ID::INT, 10) = 1 THEN
            'Jane Doe (jane.doe@company.com) requested refund. Phone: (555) 987-6543. Issue resolved.'
        WHEN MOD(ORDER_ID::INT, 10) = 2 THEN
            'Great product! Contact me at michael.johnson@gmail.com or 555-222-3333 for wholesale orders.'
        WHEN MOD(ORDER_ID::INT, 10) = 3 THEN
            'Customer Sarah Williams mentioned her SSN 123-45-6789 was visible on invoice. URGENT: Fix privacy issue!'
        WHEN MOD(ORDER_ID::INT, 10) = 4 THEN
            'Bob Martinez at 456 Oak Street, Boston MA 02101 wants expedited shipping. Call 555-444-5555.'
        WHEN MOD(ORDER_ID::INT, 10) = 5 THEN
            'Lisa Chen from Acme Corp called about bulk pricing. Reach her at 555-777-8888 or lisa.chen@acmecorp.com.'
        WHEN MOD(ORDER_ID::INT, 10) = 6 THEN
            'David Brown (david.b@email.net) reported shipping to wrong address: 789 Pine Ave, Seattle WA 98101.'
        WHEN MOD(ORDER_ID::INT, 10) = 7 THEN
            'Follow up with Maria Garcia at 555-333-2222. She wants to change credit card ending in 4567.'
        WHEN MOD(ORDER_ID::INT, 10) = 8 THEN
            'Customer feedback from james.wilson@company.org: Product exceeded expectations! My DOB is 03/15/1985 for loyalty program.'
        WHEN MOD(ORDER_ID::INT, 10) = 9 THEN
            'Emily Davis called from 555-666-9999. Lives at 321 Elm Street, Chicago IL 60601. Wants expedited shipping.'
        ELSE
            'Standard order processed. No issues reported.'
    END
WHERE CUSTOMER_FEEDBACK IS NULL;

SELECT ORDER_ID, CUSTOMER_FEEDBACK
FROM HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS
WHERE CUSTOMER_FEEDBACK NOT LIKE 'Standard order%'
LIMIT 10;

/*=============================================================================
  AI_REDACT — Automated PII Removal
  
  Automatically detects and replaces:
    Names → [NAME]
    Emails → [EMAIL]
    Phones → [PHONE_NUMBER]
    SSN → [US_SOCIAL_SECURITY_NUMBER]
    Addresses → [STREET_ADDRESS]
=============================================================================*/

WITH sample_feedback AS (
    SELECT ORDER_ID, CUSTOMER_FEEDBACK AS original_feedback
    FROM HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS
    WHERE CUSTOMER_FEEDBACK NOT LIKE 'Standard order%'
    LIMIT 5
)
SELECT
    ORDER_ID,
    original_feedback,
    SNOWFLAKE.CORTEX.AI_REDACT(original_feedback) AS redacted_feedback
FROM sample_feedback;

/*=============================================================================
  CREATE REDACTED TABLE FOR SAFE ANALYTICS
  (Limited to 100 rows for demo performance — AI_REDACT takes ~50s)
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;

CREATE OR REPLACE TABLE HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_REDACTED AS
SELECT
    ORDER_ID,
    CUSTOMER_ID,
    ORDER_TS,
    CUSTOMER_FEEDBACK AS original_feedback,
    SNOWFLAKE.CORTEX.AI_REDACT(CUSTOMER_FEEDBACK) AS redacted_feedback,
    CURRENT_TIMESTAMP() AS redacted_at,
    CURRENT_USER() AS redacted_by
FROM HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS
WHERE CUSTOMER_FEEDBACK IS NOT NULL
LIMIT 100;

SELECT ORDER_ID, original_feedback, redacted_feedback
FROM HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_REDACTED
WHERE original_feedback NOT LIKE 'Standard order%'
LIMIT 10;

/*=============================================================================
  SAFE SENTIMENT ANALYSIS WITH REDACTED DATA
=============================================================================*/

SELECT
    ORDER_ID,
    redacted_feedback,
    SNOWFLAKE.CORTEX.SENTIMENT(redacted_feedback) AS sentiment_score,
    CASE
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(redacted_feedback) > 0.5 THEN 'Positive'
        WHEN SNOWFLAKE.CORTEX.SENTIMENT(redacted_feedback) < -0.5 THEN 'Negative'
        ELSE 'Neutral'
    END AS sentiment_category
FROM HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_REDACTED
WHERE redacted_feedback NOT LIKE 'Standard order%'
ORDER BY sentiment_score DESC
LIMIT 100;

/*=============================================================================
  PARTIAL REDACTION — Selective Entity Types
=============================================================================*/

WITH feedback_sample AS (
    SELECT 'Contact John Smith at john.smith@email.com or call 555-123-4567 for updates.' AS text
)
SELECT
    text AS original,
    SNOWFLAKE.CORTEX.AI_REDACT(text) AS full_redaction,
    SNOWFLAKE.CORTEX.AI_REDACT(text, ['NAME', 'EMAIL']) AS partial_redaction
FROM feedback_sample;

/*=============================================================================
  ROLE-BASED ACCESS TO FEEDBACK
  
  Governors see original PII; analysts see pre-redacted version.
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;

CREATE OR REPLACE SECURE VIEW HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_SECURE AS
SELECT
    ORDER_ID,
    CUSTOMER_ID,
    ORDER_TS,
    CASE
        WHEN CURRENT_ROLE() IN ('HRZN_DATA_GOVERNOR', 'ACCOUNTADMIN')
        THEN original_feedback
        ELSE redacted_feedback
    END AS CUSTOMER_FEEDBACK,
    redacted_at,
    redacted_by
FROM HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_REDACTED;

USE ROLE HRZN_DATA_GOVERNOR;
SELECT ORDER_ID, CUSTOMER_FEEDBACK
FROM HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_SECURE
WHERE CUSTOMER_FEEDBACK NOT LIKE 'Standard order%'
LIMIT 5;

USE ROLE HRZN_DATA_USER;
SELECT ORDER_ID, CUSTOMER_FEEDBACK
FROM HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_SECURE
WHERE CUSTOMER_FEEDBACK NOT LIKE 'Standard order%'
LIMIT 5;

/*=============================================================================
  BUSINESS INSIGHTS FROM REDACTED DATA
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;

WITH feedback_analysis AS (
    SELECT
        ORDER_ID,
        redacted_feedback,
        SNOWFLAKE.CORTEX.SENTIMENT(redacted_feedback) AS sentiment,
        CASE
            WHEN LOWER(redacted_feedback) LIKE '%refund%' THEN 'Refund Request'
            WHEN LOWER(redacted_feedback) LIKE '%shipping%' OR LOWER(redacted_feedback) LIKE '%expedited%' THEN 'Shipping Issue'
            WHEN LOWER(redacted_feedback) LIKE '%bulk%' OR LOWER(redacted_feedback) LIKE '%wholesale%' THEN 'Bulk Order'
            WHEN LOWER(redacted_feedback) LIKE '%credit card%' THEN 'Payment Issue'
            WHEN LOWER(redacted_feedback) LIKE '%urgent%' OR LOWER(redacted_feedback) LIKE '%privacy%' THEN 'Urgent Issue'
            ELSE 'General Feedback'
        END AS feedback_category
    FROM HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_REDACTED
    WHERE redacted_feedback NOT LIKE 'Standard order%'
)
SELECT
    feedback_category,
    COUNT(*) AS feedback_count,
    AVG(sentiment) AS avg_sentiment,
    CASE
        WHEN AVG(sentiment) > 0.3 THEN 'Positive'
        WHEN AVG(sentiment) < -0.3 THEN 'Negative'
        ELSE 'Neutral'
    END AS sentiment_label
FROM feedback_analysis
GROUP BY feedback_category
ORDER BY feedback_count DESC;
