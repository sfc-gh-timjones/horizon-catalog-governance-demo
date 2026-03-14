/***************************************************************************************************
| H | O | R | I | Z | O | N |   | D | E | M | O |

  Customer-Facing Demo: Snowflake Horizon Catalog — Governance In Action
  
  Prerequisites: Run 0-setup.sql through 5-ai-redact.sql first (already done).
  This script contains ONLY the queries that show features working.
  No CREATE, ALTER, or setup statements — just the payoff.

  SETUP REFERENCE (if customer asks "how did you build that?"):
    0-setup.sql           — Environment, roles, warehouse, data load
    1-data-engineer.sql   — DMF creation (lines 53-96)
    2-data-governor.sql   — Classification (lines 33-165), masking policies (lines 186-243),
                            row access (lines 252-345), aggregation (lines 360-369),
                            projection (lines 390-401)
    3-it-admin.sql        — Access history & lineage setup
    4-semantic-views.sql  — Semantic view DDL (lines 25-117)
    5-ai-redact.sql       — Feedback data + redacted table (lines 20-97)
***************************************************************************************************/

USE WAREHOUSE HRZN_WH;
USE DATABASE HRZN_DB;
USE SCHEMA HRZN_SCH;

/*=============================================================================
  1. AI-POWERED DATA CLASSIFICATION
  
  Snowflake AI automatically detected and classified every column.
  Each column is tagged with a sensitivity level that maps to
  GDPR, HIPAA, PCI DSS, and CCPA requirements.
  
  Setup ref: 2-data-governor.sql lines 38-143
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;

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
  2. TAG-BASED DYNAMIC MASKING — Same Query, Different Results
  
  The DATA_GOVERNOR sees everything. The DATA_USER sees multi-level masking:
    PII       → fully redacted
    RESTRICTED→ partial mask (last 4 chars)
    SENSITIVE → SHA2 hash (pseudonymized)
    INTERNAL  → visible (low risk)
  
  One tag, one policy — automatically applied to every tagged column.
  
  Setup ref: 2-data-governor.sql lines 186-243
=============================================================================*/

-- GOVERNOR: Full visibility
USE ROLE HRZN_DATA_GOVERNOR;
SELECT ID, FIRST_NAME, EMAIL, SSN, PHONE_NUMBER, BIRTHDATE, COMPANY, OPTIN
FROM HRZN_DB.HRZN_SCH.CUSTOMER LIMIT 10;

-- DATA USER: Multi-level masking in action
USE ROLE HRZN_DATA_USER;
SELECT ID, FIRST_NAME, EMAIL, SSN, PHONE_NUMBER, BIRTHDATE, COMPANY, OPTIN
FROM HRZN_DB.HRZN_SCH.CUSTOMER LIMIT 10;

/*=============================================================================
  3. ROW ACCESS POLICIES — Geographic Filtering
  
  HRZN_DATA_USER can only see Massachusetts (MA) customers.
  The governor sees all 1,000 customers across all states.
  Controlled by a simple role→state mapping table.
  
  Setup ref: 2-data-governor.sql lines 333-345
=============================================================================*/

-- GOVERNOR: All states, all rows
USE ROLE HRZN_DATA_GOVERNOR;
SELECT STATE, COUNT(*) AS customer_count
FROM HRZN_DB.HRZN_SCH.CUSTOMER
GROUP BY STATE ORDER BY customer_count DESC;

-- DATA USER: Only Massachusetts
USE ROLE HRZN_DATA_USER;
SELECT STATE, COUNT(*) AS customer_count
FROM HRZN_DB.HRZN_SCH.CUSTOMER
GROUP BY STATE ORDER BY customer_count DESC;

/*=============================================================================
  4. TAG PROPAGATION — Governance Follows the Data
  
  CUSTOMER_COPY was created with CTAS from CUSTOMER.
  Tags propagated AUTOMATICALLY — no manual tagging needed.
  Masking policies apply instantly to the derived table.
  
  Setup ref: 2-data-governor.sql lines 291-309
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;

-- Tags propagated automatically to derived table
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

-- Masking automatically applies to the derived table too
USE ROLE HRZN_DATA_USER;
SELECT ID, FIRST_NAME, EMAIL, SSN, PHONE_NUMBER FROM HRZN_DB.HRZN_SCH.CUSTOMER_COPY LIMIT 5;

/*=============================================================================
  5. AGGREGATION POLICIES — Prevent Individual Record Access
  
  DATA_USER cannot SELECT * (individual records).
  They CAN run aggregates — but only if groups have 100+ rows.
  This enforces k-anonymity for statistical de-identification.
  
  Setup ref: 2-data-governor.sql lines 360-369
  Note: Policy was unset for later labs. Re-apply to demo:
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;
ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS
    SET AGGREGATION POLICY HRZN_DB.TAG_SCHEMA.aggregation_policy;

USE ROLE HRZN_DATA_USER;

-- This FAILS — can't select individual records
SELECT TOP 10 * FROM HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS;

-- This WORKS — aggregate with enough rows per group
SELECT ORDER_CURRENCY, SUM(ORDER_AMOUNT) AS total_amount
FROM HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS GROUP BY ORDER_CURRENCY;

-- Clean up for next demo
USE ROLE HRZN_DATA_GOVERNOR;
ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS UNSET AGGREGATION POLICY;

/*=============================================================================
  6. PROJECTION POLICIES — Column-Level Access Control
  
  ZIP column is projection-constrained for DATA_USER.
  They CANNOT project it in output, but CAN filter on it in WHERE.
  
  Setup ref: 2-data-governor.sql lines 392-401
  Note: Policy was unset for later labs. Re-apply to demo:
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;
ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER MODIFY COLUMN ZIP UNSET TAG HRZN_DB.TAG_SCHEMA.DATA_CLASSIFICATION;
ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER MODIFY COLUMN ZIP
    SET PROJECTION POLICY HRZN_DB.TAG_SCHEMA.projection_policy;

USE ROLE HRZN_DATA_USER;

-- This FAILS — ZIP is projection constrained
SELECT TOP 10 * FROM HRZN_DB.HRZN_SCH.CUSTOMER;

-- This WORKS — exclude ZIP from output
SELECT TOP 10 * EXCLUDE ZIP FROM HRZN_DB.HRZN_SCH.CUSTOMER;

-- ZIP can still be used in WHERE clause (filter without seeing)
SELECT * EXCLUDE ZIP FROM HRZN_DB.HRZN_SCH.CUSTOMER WHERE ZIP IN ('53596','38106','62568') LIMIT 5;

-- Clean up
USE ROLE HRZN_DATA_GOVERNOR;
ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER MODIFY COLUMN ZIP UNSET PROJECTION POLICY;
ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER MODIFY COLUMN ZIP SET TAG HRZN_DB.TAG_SCHEMA.DATA_CLASSIFICATION = 'SENSITIVE';

/*=============================================================================
  7. DATA QUALITY MONITORING — DMFs in Action
  
  5 Data Metric Functions run every 5 minutes automatically.
  Includes a custom regex DMF that counts invalid emails.
  
  Setup ref: 1-data-engineer.sql lines 53-96
=============================================================================*/

USE ROLE HRZN_DATA_ENGINEER;

-- Live data quality stats
SELECT
    SNOWFLAKE.CORE.NULL_COUNT(SELECT EMAIL FROM HRZN_DB.HRZN_SCH.CUSTOMER) AS null_emails,
    SNOWFLAKE.CORE.UNIQUE_COUNT(SELECT EMAIL FROM HRZN_DB.HRZN_SCH.CUSTOMER) AS unique_emails,
    SNOWFLAKE.CORE.DUPLICATE_COUNT(SELECT EMAIL FROM HRZN_DB.HRZN_SCH.CUSTOMER) AS duplicate_emails,
    HRZN_DB.HRZN_SCH.INVALID_EMAIL_COUNT(SELECT EMAIL FROM HRZN_DB.HRZN_SCH.CUSTOMER) AS invalid_emails;

-- All 5 DMFs running on schedule
SELECT metric_name, ref_entity_name, schedule, schedule_status
FROM TABLE(information_schema.data_metric_function_references(
    ref_entity_name => 'HRZN_DB.HRZN_SCH.CUSTOMER',
    ref_entity_domain => 'TABLE'));

-- Historical DMF results (may need a few minutes to populate)
SELECT change_commit_time, measurement_time, table_name, metric_name, value
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
WHERE table_database = 'HRZN_DB'
ORDER BY change_commit_time DESC;

/*=============================================================================
  8. SEMANTIC VIEW — AI Queries with Built-In Governance
  
  Cortex Analyst queries through the semantic view automatically
  inherit ALL masking and row access policies. Zero extra config.
  
  Setup ref: 4-semantic-views.sql lines 25-117
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;

-- Revenue by state (governor sees all states)
SELECT * FROM SEMANTIC_VIEW(
    CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS customers.location_state
    METRICS orders.total_revenue, orders.total_orders
)
ORDER BY TOTAL_REVENUE DESC;

-- Top 10 customers (governor sees real names and emails)
SELECT * FROM SEMANTIC_VIEW(
    CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS customers.customer_name, customers.email_address, customers.location_state
    METRICS orders.total_revenue
)
ORDER BY TOTAL_REVENUE DESC
LIMIT 10;

-- Same query, restricted role — emails MASKED, only MA rows
USE ROLE HRZN_DATA_USER;
SELECT * FROM SEMANTIC_VIEW(
    CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS customers.customer_name, customers.email_address, customers.location_state
    METRICS orders.total_revenue
)
ORDER BY TOTAL_REVENUE DESC
LIMIT 10;

/*=============================================================================
  9. AI_REDACT — Unstructured PII Protection
  
  Structured columns are protected by classification + masking.
  Unstructured text (feedback, emails, tickets) needs AI_REDACT.
  Automatically detects 50+ PII types — no regex needed.
  
  Setup ref: 5-ai-redact.sql lines 20-97
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;

-- Side-by-side: original PII vs AI-redacted
SELECT ORDER_ID, original_feedback, redacted_feedback
FROM HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_REDACTED
WHERE original_feedback NOT LIKE 'Standard order%'
LIMIT 5;

-- Partial redaction: choose exactly which PII types to redact
WITH feedback_sample AS (
    SELECT 'Contact John Smith at john.smith@email.com or call 555-123-4567 for updates.' AS text
)
SELECT
    text AS original,
    SNOWFLAKE.CORTEX.AI_REDACT(text) AS full_redaction,
    SNOWFLAKE.CORTEX.AI_REDACT(text, ['NAME', 'EMAIL']) AS partial_redaction
FROM feedback_sample;

-- Safe sentiment analysis on redacted data (no PII exposure)
WITH distinct_feedback AS (
    SELECT redacted_feedback,
           SNOWFLAKE.CORTEX.SENTIMENT(redacted_feedback) AS sentiment_score,
           ROW_NUMBER() OVER (PARTITION BY MOD(ORDER_ID::INT, 10) ORDER BY ORDER_ID) AS rn
    FROM HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_REDACTED
    WHERE redacted_feedback NOT LIKE 'Standard order%'
)
SELECT
    redacted_feedback, sentiment_score,
    CASE
        WHEN sentiment_score > 0.5 THEN 'Positive'
        WHEN sentiment_score < -0.5 THEN 'Negative'
        ELSE 'Neutral'
    END AS sentiment_category
FROM distinct_feedback
WHERE rn = 1
ORDER BY sentiment_score DESC;

-- Role-based: governor sees original, data user sees redacted
USE ROLE HRZN_DATA_GOVERNOR;
SELECT ORDER_ID, CUSTOMER_FEEDBACK
FROM HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_SECURE
WHERE CUSTOMER_FEEDBACK NOT LIKE 'Standard order%' LIMIT 3;

USE ROLE HRZN_DATA_USER;
SELECT ORDER_ID, CUSTOMER_FEEDBACK
FROM HRZN_DB.HRZN_SCH.CUSTOMER_FEEDBACK_SECURE
WHERE CUSTOMER_FEEDBACK NOT LIKE 'Standard order%' LIMIT 3;

/*=============================================================================
  10. ACCESS HISTORY & LINEAGE — Who Touched What, When
  
  Note: Access history has up to 3-hour latency.
  Results improve the longer the demo environment has been running.
  
  Setup ref: 3-it-admin.sql (entire file)
=============================================================================*/

USE ROLE HRZN_IT_ADMIN;

-- Direct object access counts
SELECT
    value:"objectName"::STRING AS object_name,
    COUNT(DISTINCT query_id) AS number_of_queries
FROM snowflake.account_usage.access_history,
LATERAL FLATTEN (input => direct_objects_accessed)
WHERE object_name ILIKE 'HRZN%'
GROUP BY object_name
ORDER BY number_of_queries DESC;

-- Read vs write breakdown
SELECT
    value:"objectName"::STRING AS object_name,
    CASE WHEN object_modified_by_ddl IS NOT NULL THEN 'write' ELSE 'read' END AS query_type,
    COUNT(DISTINCT query_id) AS number_of_queries,
    MAX(query_start_time) AS last_access
FROM snowflake.account_usage.access_history,
LATERAL FLATTEN (input => direct_objects_accessed)
WHERE object_name ILIKE 'HRZN%'
GROUP BY object_name, query_type
ORDER BY object_name, number_of_queries DESC;

-- Object dependency lineage (what depends on CUSTOMER?)
SELECT
    REFERENCING_DATABASE || '.' || REFERENCING_SCHEMA || '.' || REFERENCING_OBJECT_NAME AS dependent_object,
    REFERENCING_OBJECT_DOMAIN AS object_type
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE REFERENCED_DATABASE = 'HRZN_DB'
    AND REFERENCED_SCHEMA = 'HRZN_SCH'
    AND REFERENCED_OBJECT_NAME = 'CUSTOMER';

/*=============================================================================
  11. GOVERNANCE SCORECARD
  
  Quick overview: what's tagged, what's protected, what's the grade?
  
  Setup ref: 6-nl-governance.sql lines 115-154
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;

-- Policy coverage summary
SELECT * FROM TABLE(HRZN_DB.INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_NAME => 'HRZN_DB.HRZN_SCH.CUSTOMER',
    REF_ENTITY_DOMAIN => 'TABLE'
));

-- Masking policies in the environment
SHOW MASKING POLICIES IN SCHEMA HRZN_DB.TAG_SCHEMA;

-- All governance objects at a glance
SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE
FROM HRZN_DB.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA IN ('HRZN_SCH','TAG_SCHEMA','CLASSIFIERS','SEC_POLICIES_SCHEMA')
ORDER BY TABLE_SCHEMA, TABLE_TYPE, TABLE_NAME;
