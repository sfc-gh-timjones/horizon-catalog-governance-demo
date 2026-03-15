/***************************************************************************************************
| H | O | R | I | Z | O | N |   | L | A | B | S |

Demo:         Horizon Catalog - Lab 3: IT Admin (Access History + Lineage)
Version:      HLab v2.1 (Idempotent)
Gaps:         + OBJECT_DEPENDENCIES lineage
              + Role effectiveness analysis
              + OBJECTS_MODIFIED write lineage
***************************************************************************************************/

USE ROLE HRZN_IT_ADMIN;
USE DATABASE HRZN_DB;
USE SCHEMA HRZN_SCH;
USE WAREHOUSE HRZN_WH;

/*=============================================================================
  ACCESS HISTORY — Read Queries
  
  Note: Access History has up to 3-hour latency.
  Some queries may return empty results on a fresh build.
=============================================================================*/

--> How many queries have accessed each table directly?
SELECT
    value:"objectName"::STRING AS object_name,
    COUNT(DISTINCT query_id) AS number_of_queries
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY,
LATERAL FLATTEN (input => direct_objects_accessed)
WHERE object_name ILIKE 'HRZN%'
GROUP BY object_name
ORDER BY number_of_queries DESC;

--> Read vs Write breakdown with last access time
SELECT
    value:"objectName"::STRING AS object_name,
    CASE
        WHEN object_modified_by_ddl IS NOT NULL THEN 'write'
        ELSE 'read'
    END AS query_type,
    COUNT(DISTINCT query_id) AS number_of_queries,
    MAX(query_start_time) AS last_query_start_time
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY,
LATERAL FLATTEN (input => direct_objects_accessed)
WHERE object_name ILIKE 'HRZN%'
GROUP BY object_name, query_type
ORDER BY object_name, number_of_queries DESC;

--> Last few "read" queries against CUSTOMER
SELECT
    qh.user_name,
    qh.query_text,
    value:objectName::string AS "TABLE"
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY AS qh
JOIN SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY AS ah ON qh.query_id = ah.query_id,
    LATERAL FLATTEN(input => ah.base_objects_accessed)
WHERE query_type = 'SELECT'
    AND value:objectName = 'HRZN_DB.HRZN_SCH.CUSTOMER'
    AND start_time > DATEADD(day, -90, CURRENT_DATE());

--> Last few "write" queries against CUSTOMER
SELECT
    qh.user_name,
    qh.query_text,
    value:objectName::string AS "TABLE"
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY AS qh
JOIN SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY AS ah ON qh.query_id = ah.query_id,
    LATERAL FLATTEN(input => ah.base_objects_accessed)
WHERE query_type != 'SELECT'
    AND value:objectName = 'HRZN_DB.HRZN_SCH.CUSTOMER'
    AND start_time > DATEADD(day, -90, CURRENT_DATE());

--> Longest running queries
SELECT
    query_text,
    user_name,
    role_name,
    database_name,
    warehouse_name,
    warehouse_size,
    execution_status,
    ROUND(total_elapsed_time/1000,3) elapsed_sec
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
ORDER BY total_elapsed_time DESC
LIMIT 10;

--> Queries against sensitive tables
SELECT
    q.USER_NAME,
    q.QUERY_TEXT,
    q.START_TIME,
    q.END_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY q
WHERE q.QUERY_TEXT ILIKE '%HRZN_DB.HRZN_SCH.CUSTOMER%'
ORDER BY q.START_TIME DESC;

/*=============================================================================
  [GAP] OBJECTS_MODIFIED — Write Lineage
  
  Shows column-level data flow: which source columns feed which targets.
  Covers both DIRECT sources and BASE (transitive) sources.
=============================================================================*/

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

--> How many queries accessed tables indirectly?
SELECT
    base.value:"objectName"::STRING AS object_name,
    COUNT(DISTINCT query_id) AS number_of_queries
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY,
LATERAL FLATTEN (input => base_objects_accessed) base,
LATERAL FLATTEN (input => direct_objects_accessed) direct
WHERE 1=1
    AND object_name ILIKE 'HRZN%'
    AND object_name <> direct.value:"objectName"::STRING
GROUP BY object_name
ORDER BY number_of_queries DESC;

/*=============================================================================
  [GAP] OBJECT_DEPENDENCIES — Static Lineage
  
  Shows object-level dependencies (views → tables, etc.)
  without waiting for access history latency.
=============================================================================*/

--> All dependencies for objects in HRZN_DB
SELECT
    REFERENCING_DATABASE || '.' || REFERENCING_SCHEMA || '.' || REFERENCING_OBJECT_NAME AS referencing_object,
    REFERENCING_OBJECT_DOMAIN AS referencing_type,
    REFERENCED_DATABASE || '.' || REFERENCED_SCHEMA || '.' || REFERENCED_OBJECT_NAME AS referenced_object,
    REFERENCED_OBJECT_DOMAIN AS referenced_type
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE REFERENCING_DATABASE = 'HRZN_DB'
ORDER BY referencing_object;

--> Downstream impact: what depends on CUSTOMER table?
SELECT
    REFERENCING_DATABASE || '.' || REFERENCING_SCHEMA || '.' || REFERENCING_OBJECT_NAME AS dependent_object,
    REFERENCING_OBJECT_DOMAIN AS object_type
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE REFERENCED_DATABASE = 'HRZN_DB'
    AND REFERENCED_SCHEMA = 'HRZN_SCH'
    AND REFERENCED_OBJECT_NAME = 'CUSTOMER';

--> Upstream lineage: what does the summary view depend on?
SELECT
    REFERENCED_DATABASE || '.' || REFERENCED_SCHEMA || '.' || REFERENCED_OBJECT_NAME AS source_object,
    REFERENCED_OBJECT_DOMAIN AS source_type
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE REFERENCING_DATABASE = 'HRZN_DB'
    AND REFERENCING_SCHEMA = 'HRZN_SCH'
    AND REFERENCING_OBJECT_NAME = 'CUSTOMER_ORDER_SUMMARY';

/*=============================================================================
  [GAP] ROLE EFFECTIVENESS ANALYSIS
  
  Compares granted privileges vs actually-used privileges
  to identify over-provisioned or dormant roles.
=============================================================================*/

--> Grants to each Horizon role
SELECT
    GRANTEE_NAME,
    PRIVILEGE,
    TABLE_CATALOG || '.' || TABLE_SCHEMA || '.' || NAME AS object_name,
    GRANTED_ON
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE GRANTEE_NAME LIKE 'HRZN_%'
    AND DELETED_ON IS NULL
ORDER BY GRANTEE_NAME, GRANTED_ON;

--> Active roles: which Horizon roles have been used recently?
SELECT
    ROLE_NAME,
    COUNT(DISTINCT QUERY_ID) AS query_count,
    COUNT(DISTINCT USER_NAME) AS user_count,
    MIN(START_TIME) AS first_used,
    MAX(START_TIME) AS last_used
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE ROLE_NAME LIKE 'HRZN_%'
    AND START_TIME >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY ROLE_NAME
ORDER BY query_count DESC;

--> Role privilege coverage: granted vs used
WITH granted AS (
    SELECT
        GRANTEE_NAME AS role_name,
        COUNT(*) AS total_grants
    FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
    WHERE GRANTEE_NAME LIKE 'HRZN_%'
        AND DELETED_ON IS NULL
    GROUP BY GRANTEE_NAME
),
used AS (
    SELECT
        ROLE_NAME AS role_name,
        COUNT(DISTINCT QUERY_ID) AS queries_last_30d
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE ROLE_NAME LIKE 'HRZN_%'
        AND START_TIME >= DATEADD(day, -30, CURRENT_TIMESTAMP())
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
