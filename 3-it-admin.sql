/***************************************************************************************************
| H | O | R | I | Z | O | N |   | L | A | B | S |

Demo:         Horizon Catalog - Lab 3: IT Admin (Pre-compute Audit Tables)
Version:      HLab v2.1 (Idempotent)

  This script pre-computes slow ACCOUNT_USAGE queries into materialized
  tables in HRZN_DB.AUDIT_RESULTS. The demo script (demo-6-audit.sql)
  reads from these tables for instant results during live walkthroughs.

  Run this script at least 3 hours after setup to allow access history
  to populate. Re-run any time to refresh the snapshots.

  Tables created:
    - DIRECT_ACCESS_COUNTS       — which objects were queried, how often
    - READ_WRITE_BREAKDOWN       — read vs write split with last access time
    - COLUMN_WRITE_LINEAGE       — OBJECTS_MODIFIED column-level data flow
    - INDIRECT_ACCESS_COUNTS     — base (transitive) object access
    - ALL_DEPENDENCIES           — full HRZN_DB object dependency graph
    - DOWNSTREAM_CUSTOMER        — what depends on the CUSTOMER table
    - UPSTREAM_SUMMARY_VIEW      — what feeds CUSTOMER_ORDER_SUMMARY
    - ROLE_GRANTS                — grants to each Horizon role
    - ACTIVE_ROLES               — which roles have been used recently
    - ROLE_EFFECTIVENESS         — granted vs used privilege comparison
    - LOGIN_ACTIVITY             — user login history over 90 days
    - WAREHOUSE_CREDITS          — credit consumption by warehouse
    - COST_ATTRIBUTION           — credit spend attributed to users
***************************************************************************************************/

USE ROLE HRZN_IT_ADMIN;
USE DATABASE HRZN_DB;
USE WAREHOUSE HRZN_WH;

ALTER WAREHOUSE HRZN_WH SET WAREHOUSE_SIZE = 'LARGE';

CREATE SCHEMA IF NOT EXISTS HRZN_DB.AUDIT_RESULTS;
GRANT USAGE ON SCHEMA HRZN_DB.AUDIT_RESULTS TO ROLE HRZN_DATA_GOVERNOR;
GRANT USAGE ON SCHEMA HRZN_DB.AUDIT_RESULTS TO ROLE HRZN_DATA_USER;
GRANT SELECT ON ALL TABLES IN SCHEMA HRZN_DB.AUDIT_RESULTS TO ROLE HRZN_DATA_GOVERNOR;
GRANT SELECT ON ALL TABLES IN SCHEMA HRZN_DB.AUDIT_RESULTS TO ROLE HRZN_DATA_USER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA HRZN_DB.AUDIT_RESULTS TO ROLE HRZN_DATA_GOVERNOR;
GRANT SELECT ON FUTURE TABLES IN SCHEMA HRZN_DB.AUDIT_RESULTS TO ROLE HRZN_DATA_USER;

USE SCHEMA HRZN_DB.AUDIT_RESULTS;

/*=============================================================================
  ACCESS HISTORY — Read Queries
  
  Note: Access History has up to 3-hour latency.
  Some queries may return empty results on a fresh build.
=============================================================================*/

CREATE OR REPLACE TABLE DIRECT_ACCESS_COUNTS AS
SELECT
    value:"objectName"::STRING AS object_name,
    COUNT(DISTINCT query_id) AS number_of_queries
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY,
LATERAL FLATTEN (input => direct_objects_accessed)
WHERE query_start_time >= DATEADD(day, -60, CURRENT_TIMESTAMP())
GROUP BY object_name
ORDER BY number_of_queries DESC;

CREATE OR REPLACE TABLE READ_WRITE_BREAKDOWN AS
SELECT
    value:"objectName"::STRING AS object_name,
    CASE
        WHEN object_modified_by_ddl IS NOT NULL THEN 'write'
        ELSE 'read'
    END AS query_type,
    COUNT(DISTINCT query_id) AS number_of_queries,
    MAX(query_start_time) AS last_access
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY,
LATERAL FLATTEN (input => direct_objects_accessed)
WHERE query_start_time >= DATEADD(day, -60, CURRENT_TIMESTAMP())
GROUP BY object_name, query_type
ORDER BY object_name, number_of_queries DESC;

/*=============================================================================
  OBJECTS_MODIFIED — Write Lineage
  
  Shows column-level data flow: which source columns feed which targets.
  Covers both DIRECT sources and BASE (transitive) sources.
=============================================================================*/

CREATE OR REPLACE TABLE COLUMN_WRITE_LINEAGE AS
SELECT * FROM (
    SELECT
        directSources.value:"objectId"::varchar AS source_object_id,
        directSources.value:"objectName"::varchar AS source_object_name,
        directSources.value:"columnName"::varchar AS source_column_name,
        'DIRECT' AS source_column_type,
        om.value:"objectName"::varchar AS target_object_name,
        columns_modified.value:"columnName"::varchar AS target_column_name
    FROM (SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY) t,
        LATERAL FLATTEN(input => t.OBJECTS_MODIFIED) om,
        LATERAL FLATTEN(input => om.value:"columns", outer => true) columns_modified,
        LATERAL FLATTEN(input => columns_modified.value:"directSources", outer => true) directSources
    UNION
    SELECT
        baseSources.value:"objectId" AS source_object_id,
        baseSources.value:"objectName"::varchar AS source_object_name,
        baseSources.value:"columnName"::varchar AS source_column_name,
        'BASE' AS source_column_type,
        om.value:"objectName"::varchar AS target_object_name,
        columns_modified.value:"columnName"::varchar AS target_column_name
    FROM (SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY) t,
        LATERAL FLATTEN(input => t.OBJECTS_MODIFIED) om,
        LATERAL FLATTEN(input => om.value:"columns", outer => true) columns_modified,
        LATERAL FLATTEN(input => columns_modified.value:"baseSources", outer => true) baseSources
) col_lin
WHERE (SOURCE_OBJECT_NAME = 'HRZN_DB.HRZN_SCH.CUSTOMER' OR TARGET_OBJECT_NAME = 'HRZN_DB.HRZN_SCH.CUSTOMER')
    AND (SOURCE_COLUMN_NAME IN (
            SELECT COLUMN_NAME FROM (
                SELECT * FROM TABLE(
                    HRZN_DB.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
                        'HRZN_DB.HRZN_SCH.CUSTOMER', 'table'
                    )
                )
            )
            WHERE TAG_NAME IN ('SEMANTIC_CATEGORY','PRIVACY_CATEGORY','DATA_CLASSIFICATION')
        )
        OR TARGET_COLUMN_NAME IN (
            SELECT COLUMN_NAME FROM (
                SELECT * FROM TABLE(
                    HRZN_DB.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
                        'HRZN_DB.HRZN_SCH.CUSTOMER', 'table'
                    )
                )
            )
            WHERE TAG_NAME IN ('SEMANTIC_CATEGORY','PRIVACY_CATEGORY','DATA_CLASSIFICATION')
        )
    );

CREATE OR REPLACE TABLE INDIRECT_ACCESS_COUNTS AS
SELECT
    base.value:"objectName"::STRING AS object_name,
    COUNT(DISTINCT query_id) AS number_of_queries
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY,
LATERAL FLATTEN (input => base_objects_accessed) base,
LATERAL FLATTEN (input => direct_objects_accessed) direct
WHERE query_start_time >= DATEADD(day, -60, CURRENT_TIMESTAMP())
    AND object_name <> direct.value:"objectName"::STRING
GROUP BY object_name
ORDER BY number_of_queries DESC;

/*=============================================================================
  OBJECT_DEPENDENCIES — Static Lineage
  
  Shows object-level dependencies (views → tables, etc.)
  without waiting for access history latency.
=============================================================================*/

CREATE OR REPLACE TABLE ALL_DEPENDENCIES AS
SELECT
    REFERENCING_DATABASE || '.' || REFERENCING_SCHEMA || '.' || REFERENCING_OBJECT_NAME AS referencing_object,
    REFERENCING_OBJECT_DOMAIN AS referencing_type,
    REFERENCED_DATABASE || '.' || REFERENCED_SCHEMA || '.' || REFERENCED_OBJECT_NAME AS referenced_object,
    REFERENCED_OBJECT_DOMAIN AS referenced_type
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE REFERENCING_DATABASE = 'HRZN_DB'
ORDER BY referencing_object;

CREATE OR REPLACE TABLE DOWNSTREAM_CUSTOMER AS
SELECT
    REFERENCING_DATABASE || '.' || REFERENCING_SCHEMA || '.' || REFERENCING_OBJECT_NAME AS dependent_object,
    REFERENCING_OBJECT_DOMAIN AS object_type
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE REFERENCED_DATABASE = 'HRZN_DB'
    AND REFERENCED_SCHEMA = 'HRZN_SCH'
    AND REFERENCED_OBJECT_NAME = 'CUSTOMER';

CREATE OR REPLACE TABLE UPSTREAM_SUMMARY_VIEW AS
SELECT
    REFERENCED_DATABASE || '.' || REFERENCED_SCHEMA || '.' || REFERENCED_OBJECT_NAME AS source_object,
    REFERENCED_OBJECT_DOMAIN AS source_type
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE REFERENCING_DATABASE = 'HRZN_DB'
    AND REFERENCING_SCHEMA = 'HRZN_SCH'
    AND REFERENCING_OBJECT_NAME = 'CUSTOMER_ORDER_SUMMARY';

/*=============================================================================
  ROLE EFFECTIVENESS ANALYSIS
  
  Compares granted privileges vs actually-used privileges
  to identify over-provisioned or dormant roles.
=============================================================================*/

CREATE OR REPLACE TABLE ROLE_GRANTS AS
SELECT
    GRANTEE_NAME,
    PRIVILEGE,
    TABLE_CATALOG || '.' || TABLE_SCHEMA || '.' || NAME AS object_name,
    GRANTED_ON
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE GRANTEE_NAME LIKE 'HRZN_%'
    AND DELETED_ON IS NULL
ORDER BY GRANTEE_NAME, GRANTED_ON;

CREATE OR REPLACE TABLE ACTIVE_ROLES AS
SELECT
    ROLE_NAME,
    COUNT(DISTINCT QUERY_ID) AS query_count,
    COUNT(DISTINCT USER_NAME) AS user_count,
    MIN(START_TIME) AS first_used,
    MAX(START_TIME) AS last_used
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY ROLE_NAME
ORDER BY query_count DESC;

CREATE OR REPLACE TABLE ROLE_EFFECTIVENESS AS
WITH granted AS (
    SELECT
        GRANTEE_NAME AS role_name,
        COUNT(*) AS total_grants
    FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
    WHERE DELETED_ON IS NULL
    GROUP BY GRANTEE_NAME
),
used AS (
    SELECT
        ROLE_NAME AS role_name,
        COUNT(DISTINCT QUERY_ID) AS queries_last_30d
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE START_TIME >= DATEADD(day, -30, CURRENT_TIMESTAMP())
    GROUP BY ROLE_NAME
)
SELECT
    g.role_name,
    g.total_grants,
    COALESCE(u.queries_last_30d, 0) AS queries_last_30d,
    CASE
        WHEN COALESCE(u.queries_last_30d, 0) = 0 THEN 'DORMANT'
        WHEN g.total_grants > 20 AND COALESCE(u.queries_last_30d, 0) < 5 THEN 'OVER-PROVISIONED'
        ELSE 'ACTIVE'
    END AS effectiveness_status
FROM granted g
LEFT JOIN used u ON g.role_name = u.role_name
ORDER BY g.role_name;

/*=============================================================================
  LOGIN, METERING & COST ATTRIBUTION
=============================================================================*/

CREATE OR REPLACE TABLE LOGIN_ACTIVITY AS
SELECT
    USER_NAME,
    COUNT(*) AS login_count,
    MAX(EVENT_TIMESTAMP) AS last_login,
    MIN(EVENT_TIMESTAMP) AS first_login_in_window,
    CASE
        WHEN MAX(EVENT_TIMESTAMP) >= DATEADD(day, -7, CURRENT_TIMESTAMP()) THEN 'ACTIVE'
        WHEN MAX(EVENT_TIMESTAMP) >= DATEADD(day, -30, CURRENT_TIMESTAMP()) THEN 'RECENT'
        ELSE 'STALE'
    END AS activity_status
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE EVENT_TIMESTAMP >= DATEADD(day, -60, CURRENT_TIMESTAMP())
    AND IS_SUCCESS = 'YES'
GROUP BY USER_NAME
ORDER BY login_count DESC;

CREATE OR REPLACE TABLE WAREHOUSE_CREDITS AS
SELECT
    WAREHOUSE_NAME,
    ROUND(SUM(CREDITS_USED), 2) AS total_credits,
    ROUND(SUM(CREDITS_USED_COMPUTE), 2) AS compute_credits,
    ROUND(SUM(CREDITS_USED_CLOUD_SERVICES), 2) AS cloud_services_credits,
    COUNT(DISTINCT TO_DATE(START_TIME)) AS active_days
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME >= DATEADD(day, -60, CURRENT_TIMESTAMP())
GROUP BY WAREHOUSE_NAME
ORDER BY total_credits DESC;

CREATE OR REPLACE TABLE COST_ATTRIBUTION AS
SELECT
    USER_NAME,
    ROUND(SUM(CREDITS_ATTRIBUTED_COMPUTE), 2) AS compute_credits,
    COUNT(DISTINCT QUERY_ID) AS query_count,
    ROUND(SUM(CREDITS_ATTRIBUTED_COMPUTE) / NULLIF(COUNT(DISTINCT QUERY_ID), 0), 4) AS credits_per_query
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
WHERE START_TIME >= DATEADD(day, -60, CURRENT_TIMESTAMP())
GROUP BY USER_NAME
ORDER BY compute_credits DESC
LIMIT 20;

ALTER WAREHOUSE HRZN_WH SET WAREHOUSE_SIZE = 'SMALL';

SELECT 'Audit tables materialized in HRZN_DB.AUDIT_RESULTS. Run demo-6-audit.sql for instant results.' AS status;
