/***************************************************************************************************
| H | O | R | I | Z | O | N |   | D | E | M | O |

  Demo 6: Audit, Lineage & Compliance
  "Prove governance works."

  What you'll show:
    - Access history: who accessed what data, when, read vs write
    - Object dependency lineage: what depends on the CUSTOMER table
    - Upstream lineage: what feeds the summary view
    - Role effectiveness: granted privileges vs actual usage
    - Governance scorecard: policy coverage overview

  Setup references:
    - Access history queries:              3-it-admin.sql lines 24-31
    - Read vs write breakdown:             3-it-admin.sql lines 34-46
    - OBJECT_DEPENDENCIES lineage:         3-it-admin.sql lines 172-197
    - Role effectiveness analysis:         3-it-admin.sql lines 230-260
    - Governance coverage scoring:         6-nl-governance.sql lines 115-154
    - Policy types summary:                6-nl-governance.sql lines 167-175

  Note: Access history has up to 3-hour latency.
  Results improve the longer the demo environment has been running.
***************************************************************************************************/

USE WAREHOUSE HRZN_WH;
USE DATABASE HRZN_DB;
USE SCHEMA HRZN_SCH;

/*=============================================================================
  ACCESS HISTORY — Who Touched What, When
  
  Every query against every object is tracked automatically.
  No configuration needed — it's built into the platform.
  
  Setup ref: 3-it-admin.sql lines 24-46
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

-- Read vs write breakdown with last access time
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

/*=============================================================================
  OBJECT DEPENDENCY LINEAGE — Impact Analysis
  
  Static lineage — no access history latency.
  Shows which views, tables, and semantic views depend on each other.
  
  Setup ref: 3-it-admin.sql lines 172-197
=============================================================================*/

-- Downstream: what depends on the CUSTOMER table?
SELECT
    REFERENCING_DATABASE || '.' || REFERENCING_SCHEMA || '.' || REFERENCING_OBJECT_NAME AS dependent_object,
    REFERENCING_OBJECT_DOMAIN AS object_type
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE REFERENCED_DATABASE = 'HRZN_DB'
    AND REFERENCED_SCHEMA = 'HRZN_SCH'
    AND REFERENCED_OBJECT_NAME = 'CUSTOMER';

-- Upstream: what feeds the CUSTOMER_ORDER_SUMMARY view?
SELECT
    REFERENCED_DATABASE || '.' || REFERENCED_SCHEMA || '.' || REFERENCED_OBJECT_NAME AS source_object,
    REFERENCED_OBJECT_DOMAIN AS source_type
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE REFERENCING_DATABASE = 'HRZN_DB'
    AND REFERENCING_SCHEMA = 'HRZN_SCH'
    AND REFERENCING_OBJECT_NAME = 'CUSTOMER_ORDER_SUMMARY';

/*=============================================================================
  ROLE EFFECTIVENESS — Granted vs Used
  
  Identifies dormant roles (granted but never used)
  and over-provisioned roles (many grants, few queries).
  
  Setup ref: 3-it-admin.sql lines 230-260
=============================================================================*/

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

/*=============================================================================
  GOVERNANCE SCORECARD — Policy Coverage
  
  Quick overview: what policies are applied to CUSTOMER?
  What masking policies exist? What objects are in the environment?
  
  Setup ref: 6-nl-governance.sql lines 115-175
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;

-- All policies applied to CUSTOMER
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
