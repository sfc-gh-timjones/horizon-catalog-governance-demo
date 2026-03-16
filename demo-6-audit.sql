/***************************************************************************************************
| H | O | R | I | Z | O | N |   | D | E | M | O |

  Demo 6: Audit, Lineage & Compliance
  "Prove governance works."

  What you'll show:
    - Access history: who accessed what data, when, read vs write
    - Column-level write lineage: source→target data flow
    - Object dependency lineage: downstream impact + upstream sources
    - Login history: user login activity over last 90 days
    - Warehouse metering: credit consumption by warehouse
    - Cost attribution: which users drove the most credit spend
    - Role effectiveness: granted privileges vs actual usage

  How it works:
    Each section has a CREATE TABLE IF NOT EXISTS (the full SQL for reference)
    followed by a SELECT * from the pre-computed result in AUDIT_RESULTS.
    Show the audience the SQL, then run the SELECT for instant results.

  Pre-requisite: Run 3-it-admin.sql first to materialize the audit tables
  into HRZN_DB.AUDIT_RESULTS. Re-run 3-it-admin.sql to refresh snapshots.

  Note: Access history has up to 3-hour latency.
  Results improve the longer the demo environment has been running.
***************************************************************************************************/

USE WAREHOUSE HRZN_WH;
USE ROLE HRZN_IT_ADMIN;

/*=============================================================================
  ACCESS HISTORY — Who Touched What, When
  
  Every query against every object is tracked automatically.
  No configuration needed — it's built into the platform.
=============================================================================*/

-- Direct object access counts
CREATE TABLE IF NOT EXISTS HRZN_DB.AUDIT_RESULTS.DIRECT_ACCESS_COUNTS AS
SELECT
    value:"objectName"::STRING AS object_name,
    COUNT(DISTINCT query_id) AS number_of_queries
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY,
LATERAL FLATTEN (input => direct_objects_accessed)
WHERE object_name ILIKE 'HRZN%'
GROUP BY object_name
ORDER BY number_of_queries DESC;

SELECT * FROM HRZN_DB.AUDIT_RESULTS.DIRECT_ACCESS_COUNTS ORDER BY number_of_queries DESC;

-- Read vs write breakdown with last access time
CREATE TABLE IF NOT EXISTS HRZN_DB.AUDIT_RESULTS.READ_WRITE_BREAKDOWN AS
SELECT
    value:"objectName"::STRING AS object_name,
    CASE WHEN object_modified_by_ddl IS NOT NULL THEN 'write' ELSE 'read' END AS query_type,
    COUNT(DISTINCT query_id) AS number_of_queries,
    MAX(query_start_time) AS last_access
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY,
LATERAL FLATTEN (input => direct_objects_accessed)
WHERE object_name ILIKE 'HRZN%'
GROUP BY object_name, query_type
ORDER BY object_name, number_of_queries DESC;

SELECT * FROM HRZN_DB.AUDIT_RESULTS.READ_WRITE_BREAKDOWN ORDER BY query_type, number_of_queries DESC;

/*=============================================================================
  COLUMN-LEVEL WRITE LINEAGE — Source→Target Data Flow
  
  Shows which source columns feed which target columns.
  Covers both DIRECT sources and BASE (transitive) sources.
  Filtered to tagged (sensitive) columns on CUSTOMER.
=============================================================================*/

CREATE TABLE IF NOT EXISTS HRZN_DB.AUDIT_RESULTS.COLUMN_WRITE_LINEAGE AS
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

SELECT * FROM HRZN_DB.AUDIT_RESULTS.COLUMN_WRITE_LINEAGE;

/*=============================================================================
  OBJECT DEPENDENCY LINEAGE — Impact Analysis
  
  Static lineage — no access history latency.
  Shows which views, tables, and semantic views depend on each other.
=============================================================================*/

-- Downstream: what depends on the CUSTOMER table?
CREATE TABLE IF NOT EXISTS HRZN_DB.AUDIT_RESULTS.DOWNSTREAM_CUSTOMER AS
SELECT
    REFERENCING_DATABASE || '.' || REFERENCING_SCHEMA || '.' || REFERENCING_OBJECT_NAME AS dependent_object,
    REFERENCING_OBJECT_DOMAIN AS object_type
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE REFERENCED_DATABASE = 'HRZN_DB'
    AND REFERENCED_SCHEMA = 'HRZN_SCH'
    AND REFERENCED_OBJECT_NAME = 'CUSTOMER';

SELECT * FROM HRZN_DB.AUDIT_RESULTS.DOWNSTREAM_CUSTOMER;

-- Upstream: what feeds the CUSTOMER_ORDER_SUMMARY view?
CREATE TABLE IF NOT EXISTS HRZN_DB.AUDIT_RESULTS.UPSTREAM_SUMMARY_VIEW AS
SELECT
    REFERENCED_DATABASE || '.' || REFERENCED_SCHEMA || '.' || REFERENCED_OBJECT_NAME AS source_object,
    REFERENCED_OBJECT_DOMAIN AS source_type
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE REFERENCING_DATABASE = 'HRZN_DB'
    AND REFERENCING_SCHEMA = 'HRZN_SCH'
    AND REFERENCING_OBJECT_NAME = 'CUSTOMER_ORDER_SUMMARY';

SELECT * FROM HRZN_DB.AUDIT_RESULTS.UPSTREAM_SUMMARY_VIEW;

-- Prove it: show the actual DDL — you can see CUSTOMER and CUSTOMER_ORDERS referenced
SELECT GET_DDL('VIEW', 'HRZN_DB.HRZN_SCH.CUSTOMER_ORDER_SUMMARY');

/*=============================================================================
  LOGIN HISTORY — User Activity Over 90 Days
  
  Who's logging in, how often, and when was their last session?
  Spot inactive accounts and verify active user engagement.
=============================================================================*/

CREATE TABLE IF NOT EXISTS HRZN_DB.AUDIT_RESULTS.LOGIN_ACTIVITY AS
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
WHERE EVENT_TIMESTAMP >= DATEADD(day, -90, CURRENT_TIMESTAMP())
    AND IS_SUCCESS = 'YES'
GROUP BY USER_NAME
ORDER BY login_count DESC;

SELECT * FROM HRZN_DB.AUDIT_RESULTS.LOGIN_ACTIVITY ORDER BY login_count DESC;

/*=============================================================================
  WAREHOUSE METERING — Credit Consumption (Last 90 Days)
  
  Which warehouses burned the most credits?
  Helps identify cost hotspots and right-sizing opportunities.
=============================================================================*/

CREATE TABLE IF NOT EXISTS HRZN_DB.AUDIT_RESULTS.WAREHOUSE_CREDITS AS
SELECT
    WAREHOUSE_NAME,
    ROUND(SUM(CREDITS_USED), 2) AS total_credits,
    ROUND(SUM(CREDITS_USED_COMPUTE), 2) AS compute_credits,
    ROUND(SUM(CREDITS_USED_CLOUD_SERVICES), 2) AS cloud_services_credits,
    COUNT(DISTINCT TO_DATE(START_TIME)) AS active_days
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME >= DATEADD(day, -90, CURRENT_TIMESTAMP())
GROUP BY WAREHOUSE_NAME
ORDER BY total_credits DESC;

SELECT * FROM HRZN_DB.AUDIT_RESULTS.WAREHOUSE_CREDITS ORDER BY total_credits DESC;

/*=============================================================================
  QUERY ATTRIBUTION — Who's Driving Credit Spend?
  
  Attributes warehouse credits back to the users who ran the queries.
  Identifies top spenders for chargeback and optimization.
=============================================================================*/

CREATE TABLE IF NOT EXISTS HRZN_DB.AUDIT_RESULTS.COST_ATTRIBUTION AS
SELECT
    USER_NAME,
    ROUND(SUM(CREDITS_ATTRIBUTED_COMPUTE), 2) AS compute_credits,
    COUNT(DISTINCT QUERY_ID) AS query_count,
    ROUND(SUM(CREDITS_ATTRIBUTED_COMPUTE) / NULLIF(COUNT(DISTINCT QUERY_ID), 0), 4) AS credits_per_query
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
WHERE START_TIME >= DATEADD(day, -90, CURRENT_TIMESTAMP())
GROUP BY USER_NAME
ORDER BY compute_credits DESC
LIMIT 20;

SELECT * FROM HRZN_DB.AUDIT_RESULTS.COST_ATTRIBUTION ORDER BY query_count DESC;

/*=============================================================================
  ROLE EFFECTIVENESS — Granted vs Used
  
  Identifies dormant roles (granted but never used)
  and over-provisioned roles (many grants, few queries).
=============================================================================*/

CREATE TABLE IF NOT EXISTS HRZN_DB.AUDIT_RESULTS.ROLE_EFFECTIVENESS AS
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

SELECT * FROM HRZN_DB.AUDIT_RESULTS.ROLE_EFFECTIVENESS;

/*=============================================================================
  OTHER IDEAS — What Else Can You Build With ACCOUNT_USAGE?
  
  These aren't scripted, but show the art of the possible:
  
  1. Failed login anomaly detection — flag users with sudden spikes in
     failed logins using LOGIN_HISTORY, potential credential stuffing signal.

  2. After-hours access alerts — join ACCESS_HISTORY with QUERY_HISTORY
     to find queries run outside business hours on sensitive tables.

  3. Schema drift tracking — compare COLUMNS view snapshots over time
     to detect unexpected column additions, drops, or type changes.

  4. Cross-account data sharing audit — use DATA_TRANSFER_HISTORY to
     track which shares are sending data where and how much.

  5. Query complexity trending — analyze QUERY_HISTORY compilation_time
     and bytes_scanned week-over-week to spot performance regressions
     before users complain.

  6. Privilege escalation detection — monitor GRANTS_TO_ROLES for new
     ACCOUNTADMIN or SECURITYADMIN grants and alert on unexpected changes.
=============================================================================*/
