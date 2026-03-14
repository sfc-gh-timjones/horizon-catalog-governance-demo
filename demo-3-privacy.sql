/***************************************************************************************************
| H | O | R | I | Z | O | N |   | D | E | M | O |

  Demo 3: Privacy Protection
  "Protect sensitive data automatically."

  What you'll show:
    - Tag-based dynamic masking: same query, different results by role
    - Multi-level masking: PII→redacted, RESTRICTED→partial, SENSITIVE→hashed
    - AI_REDACT for unstructured text (50+ PII types, no regex)
    - Partial redaction (choose which PII types to redact)
    - Secure view: governor sees PII, analyst sees pre-redacted version
    - Sentiment analysis on redacted data (safe analytics without PII exposure)

  Setup references:
    - Tag-based masking policies (4 types):  2-data-governor.sql lines 186-243
    - Consent consent map:                   2-data-governor.sql lines 180-184
    - Customer feedback data + AI_REDACT:    5-ai-redact.sql lines 20-97
    - Secure view creation:                  5-ai-redact.sql lines 143-155
    - Sentiment analysis:                    5-ai-redact.sql lines 108-120
***************************************************************************************************/

USE WAREHOUSE HRZN_WH;
USE DATABASE HRZN_DB;
USE SCHEMA HRZN_SCH;

/*=============================================================================
  TAG-BASED DYNAMIC MASKING — Same Query, Different Results
  
  The DATA_CLASSIFICATION tag drives 4 masking policies (STRING, NUMBER,
  DATE, TIMESTAMP). One tag, automatic enforcement on every tagged column.
  
    PII        → fully redacted (***PII-REDACTED***)
    RESTRICTED → partial mask (last 4 chars visible)
    SENSITIVE  → SHA2 hash (pseudonymized)
    INTERNAL   → visible (low risk)
  
  Setup ref: 2-data-governor.sql lines 186-243
=============================================================================*/

-- GOVERNOR: Full visibility — sees all PII in the clear
USE ROLE HRZN_DATA_GOVERNOR;
SELECT ID, FIRST_NAME, EMAIL, SSN, PHONE_NUMBER, BIRTHDATE, COMPANY, OPTIN
FROM HRZN_DB.HRZN_SCH.CUSTOMER LIMIT 10;

-- DATA USER: Multi-level masking in action
USE ROLE HRZN_DATA_USER;
SELECT ID, FIRST_NAME, EMAIL, SSN, PHONE_NUMBER, BIRTHDATE, COMPANY, OPTIN
FROM HRZN_DB.HRZN_SCH.CUSTOMER LIMIT 10;

/*=============================================================================
  TAG PROPAGATION + MASKING ON DERIVED TABLES
  
  CUSTOMER_COPY inherited all tags from CUSTOMER via CTAS.
  Masking policies apply automatically — no extra config.
  
  Setup ref: 2-data-governor.sql lines 288-309
=============================================================================*/

USE ROLE HRZN_DATA_USER;
SELECT ID, FIRST_NAME, EMAIL, SSN, PHONE_NUMBER FROM HRZN_DB.HRZN_SCH.CUSTOMER_COPY LIMIT 10;

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
SELECT ORDER_ID, original_feedback, redacted_feedback
FROM HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_REDACTED
WHERE original_feedback NOT LIKE 'Standard order%'
LIMIT 10;

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
