/***************************************************************************************************
| H | O | R | I | Z | O | N |   | L | A | B | S |

Demo:         Horizon Catalog - Lab 6: Natural Language Governance
Version:      HLab v2.1 (Idempotent)
***************************************************************************************************/

USE ROLE HRZN_DATA_GOVERNOR;
USE WAREHOUSE HRZN_WH;
USE DATABASE HRZN_DB;
USE SCHEMA HRZN_SCH;

/*=============================================================================
  VERIFY GOVERNANCE METADATA IS AVAILABLE
  
  Note: ACCOUNT_USAGE views have up to 120-minute latency.
  If results are empty, use INFORMATION_SCHEMA equivalents
  or try again later.
=============================================================================*/

SELECT
    TAG_NAME, TAG_VALUE, OBJECT_NAME, DOMAIN,
    COUNT(*) AS cnt
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE OBJECT_DATABASE = 'HRZN_DB'
GROUP BY TAG_NAME, TAG_VALUE, OBJECT_NAME, DOMAIN
LIMIT 10;

SELECT
    POLICY_KIND, POLICY_NAME, REF_ENTITY_NAME, REF_COLUMN_NAME, POLICY_STATUS
FROM SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES
WHERE POLICY_DB = 'HRZN_DB'
LIMIT 10;

SHOW MASKING POLICIES IN SCHEMA HRZN_DB.TAG_SCHEMA;

/*=============================================================================
  CORTEX CODE — ASK GOVERNANCE QUESTIONS IN NATURAL LANGUAGE
  
  Open Snowsight → click Cortex Code icon → try these questions:
  
  COMPLIANCE & AUDIT:
    "Which tables have PII but no masking policy?"
    "Who accessed PII data in the last 7 days?"
    "What policies are applied to the CUSTOMER table?"
  
  USAGE & ADOPTION:
    "Who are the top users accessing sensitive data?"
    "How many Cortex Analyst queries ran this week?"
  
  AI ASSET GOVERNANCE:
    "Which semantic views exist in HRZN_DB?"
    "Show all tables accessed by CUSTOMER_ORDER_ANALYTICS semantic view"
  
  TAG MANAGEMENT:
    "List all tags and what columns they are applied to in HRZN_DB"
    "List all columns tagged as PII"
=============================================================================*/

/*=============================================================================
  MANUAL SQL VERSIONS OF GOVERNANCE QUESTIONS
  (These are what Cortex Code would generate automatically)
=============================================================================*/

--> Which tables have PII but no masking policy?
WITH pii_tables AS (
    SELECT DISTINCT
        OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME,
        TAG_VALUE AS pii_type
    FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
    WHERE TAG_NAME = 'SEMANTIC_CATEGORY'
      AND TAG_VALUE IN ('EMAIL', 'SSN', 'PHONE_NUMBER', 'CREDIT_CARD', 'NAME')
      AND DOMAIN = 'COLUMN'
      AND OBJECT_DATABASE = 'HRZN_DB'
),
masked_tables AS (
    SELECT DISTINCT
        SPLIT_PART(REF_ENTITY_NAME, '.', 1) AS db,
        SPLIT_PART(REF_ENTITY_NAME, '.', 2) AS schema_name,
        SPLIT_PART(REF_ENTITY_NAME, '.', 3) AS table_name
    FROM SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES
    WHERE POLICY_KIND = 'MASKING_POLICY' AND POLICY_STATUS = 'ACTIVE'
)
SELECT
    p.OBJECT_DATABASE || '.' || p.OBJECT_SCHEMA || '.' || p.OBJECT_NAME AS full_table_name,
    LISTAGG(DISTINCT p.pii_type, ', ') AS pii_types,
    'HIGH RISK: No masking policy' AS governance_status
FROM pii_tables p
LEFT JOIN masked_tables m
    ON p.OBJECT_DATABASE = m.db AND p.OBJECT_SCHEMA = m.schema_name AND p.OBJECT_NAME = m.table_name
WHERE m.table_name IS NULL
GROUP BY p.OBJECT_DATABASE, p.OBJECT_SCHEMA, p.OBJECT_NAME;

--> Who accessed PII data in the last 7 days?
SELECT
    qh.USER_NAME,
    qh.ROLE_NAME,
    qh.START_TIME::DATE AS access_date,
    COUNT(DISTINCT qh.QUERY_ID) AS pii_query_count,
    LISTAGG(DISTINCT f.value:objectName::STRING, ', ') AS pii_tables_accessed
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
JOIN SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah ON qh.QUERY_ID = ah.QUERY_ID,
LATERAL FLATTEN(input => ah.DIRECT_OBJECTS_ACCESSED) f
WHERE f.value:objectName::STRING IN (
    SELECT DISTINCT OBJECT_DATABASE || '.' || OBJECT_SCHEMA || '.' || OBJECT_NAME
    FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
    WHERE TAG_NAME = 'SEMANTIC_CATEGORY'
      AND TAG_VALUE IN ('EMAIL', 'SSN', 'PHONE_NUMBER', 'CREDIT_CARD')
      AND OBJECT_DATABASE = 'HRZN_DB'
)
AND qh.START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY qh.USER_NAME, qh.ROLE_NAME, qh.START_TIME::DATE
ORDER BY access_date DESC, pii_query_count DESC;

--> Governance coverage by schema
WITH table_inventory AS (
    SELECT TABLE_SCHEMA,
        COUNT(*) AS total_tables,
        SUM(CASE WHEN TABLE_TYPE = 'BASE TABLE' THEN 1 ELSE 0 END) AS base_tables,
        SUM(CASE WHEN TABLE_TYPE = 'VIEW' THEN 1 ELSE 0 END) AS views
    FROM HRZN_DB.INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'HRZN_SCH'
    GROUP BY TABLE_SCHEMA
),
governance_stats AS (
    SELECT OBJECT_SCHEMA,
        COUNT(DISTINCT CASE WHEN tr.DOMAIN = 'TABLE' THEN tr.OBJECT_NAME END) AS tagged_tables,
        COUNT(DISTINCT CASE WHEN tr.DOMAIN = 'COLUMN' THEN tr.OBJECT_NAME END) AS tables_with_tagged_columns,
        COUNT(DISTINCT CASE WHEN pr.REF_ENTITY_DOMAIN = 'TABLE'
                            THEN SPLIT_PART(pr.REF_ENTITY_NAME, '.', 3) END) AS protected_tables
    FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES tr
    FULL OUTER JOIN SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES pr
        ON tr.OBJECT_NAME = SPLIT_PART(pr.REF_ENTITY_NAME, '.', 3)
        AND tr.OBJECT_SCHEMA = SPLIT_PART(pr.REF_ENTITY_NAME, '.', 2)
    WHERE tr.OBJECT_DATABASE = 'HRZN_DB' OR SPLIT_PART(pr.REF_ENTITY_NAME, '.', 1) = 'HRZN_DB'
    GROUP BY OBJECT_SCHEMA
)
SELECT
    ti.TABLE_SCHEMA,
    ti.total_tables,
    ti.base_tables,
    ti.views,
    COALESCE(gs.tagged_tables, 0) AS tagged_tables,
    COALESCE(gs.protected_tables, 0) AS protected_tables,
    ROUND(COALESCE(gs.tagged_tables, 0) * 100.0 / NULLIF(ti.total_tables, 0), 1) AS pct_tagged,
    ROUND(COALESCE(gs.protected_tables, 0) * 100.0 / NULLIF(ti.total_tables, 0), 1) AS pct_protected,
    CASE
        WHEN COALESCE(gs.protected_tables, 0) * 100.0 / NULLIF(ti.total_tables, 0) >= 80 THEN 'Excellent'
        WHEN COALESCE(gs.protected_tables, 0) * 100.0 / NULLIF(ti.total_tables, 0) >= 60 THEN 'Good'
        WHEN COALESCE(gs.protected_tables, 0) * 100.0 / NULLIF(ti.total_tables, 0) >= 40 THEN 'Fair'
        ELSE 'Needs Improvement'
    END AS governance_grade
FROM table_inventory ti
LEFT JOIN governance_stats gs ON ti.TABLE_SCHEMA = gs.OBJECT_SCHEMA;

--> Tag distribution across objects
SELECT
    TAG_NAME, TAG_VALUE, DOMAIN AS object_type,
    COUNT(*) AS tagged_objects,
    COUNT(DISTINCT OBJECT_NAME) AS unique_objects
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE OBJECT_DATABASE = 'HRZN_DB'
GROUP BY TAG_NAME, TAG_VALUE, DOMAIN
ORDER BY tagged_objects DESC;

--> Policy types applied
SELECT
    POLICY_KIND, POLICY_STATUS,
    COUNT(DISTINCT POLICY_NAME) AS policy_count,
    COUNT(DISTINCT REF_ENTITY_NAME) AS protected_objects,
    COUNT(DISTINCT REF_COLUMN_NAME) AS protected_columns
FROM SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES
WHERE SPLIT_PART(REF_ENTITY_NAME, '.', 1) = 'HRZN_DB'
GROUP BY POLICY_KIND, POLICY_STATUS
ORDER BY policy_count DESC;

--> Top users accessing sensitive data (last 30 days)
SELECT
    qh.USER_NAME, qh.ROLE_NAME,
    COUNT(DISTINCT qh.QUERY_ID) AS total_queries,
    COUNT(DISTINCT qh.START_TIME::DATE) AS active_days,
    AVG(qh.TOTAL_ELAPSED_TIME)/1000 AS avg_query_seconds,
    SUM(qh.BYTES_SCANNED)/(1024*1024*1024) AS total_gb_scanned,
    MIN(qh.START_TIME) AS first_access,
    MAX(qh.START_TIME) AS last_access
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
WHERE (qh.QUERY_TEXT ILIKE '%HRZN_DB.HRZN_SCH.CUSTOMER%'
    OR qh.QUERY_TEXT ILIKE '%HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS%')
  AND qh.START_TIME >= DATEADD(day, -30, CURRENT_TIMESTAMP())
  AND qh.EXECUTION_STATUS = 'SUCCESS'
GROUP BY qh.USER_NAME, qh.ROLE_NAME
ORDER BY total_queries DESC
LIMIT 10;
