/***************************************************************************************************
| H | O | R | I | Z | O | N |   | L | A | B | S |

Demo:         Horizon Catalog - Teardown (Clean Reset)
Version:      HLab v2.1 (Idempotent)
***************************************************************************************************/

/*=============================================================================
  TEARDOWN
  
  Removes ALL demo objects. Safe to run multiple times.
  Order matters: classification profile must be unset before DROP DATABASE.
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;
USE WAREHOUSE HRZN_WH;

ALTER DATABASE HRZN_DB UNSET CLASSIFICATION_PROFILE;

DROP SNOWFLAKE.DATA_PRIVACY.CLASSIFICATION_PROFILE IF EXISTS
    HRZN_DB.HRZN_SCH.HRZN_STANDARD_CLASSIFICATION_PROFILE;

USE ROLE HRZN_DATA_ENGINEER;
DROP DATABASE IF EXISTS HRZN_DB;

USE ROLE SECURITYADMIN;
DROP ROLE IF EXISTS HRZN_DATA_ANALYST;
DROP ROLE IF EXISTS HRZN_DATA_GOVERNOR;
DROP ROLE IF EXISTS HRZN_DATA_USER;
DROP ROLE IF EXISTS HRZN_IT_ADMIN;
DROP ROLE IF EXISTS HRZN_DATA_ENGINEER;

USE ROLE SYSADMIN;
DROP WAREHOUSE IF EXISTS HRZN_WH;

/*=============================================================================
  TEARDOWN COMPLETE
  
  All Horizon Lab objects removed:
    HRZN_DB database and ALL contents (schemas, tables, views, functions, stages)
    Classification profile
    Custom roles (HRZN_DATA_GOVERNOR, HRZN_DATA_USER, HRZN_IT_ADMIN, HRZN_DATA_ENGINEER, HRZN_DATA_ANALYST)
    HRZN_WH warehouse

  Dropping the database automatically removes:
    All schemas (HRZN_SCH, CLASSIFIERS, TAG_SCHEMA, SEC_POLICIES_SCHEMA)
    All tables (CUSTOMER, CUSTOMER_ORDERS, CUSTOMER_COPY, CUSTOMER_FEEDBACK_REDACTED, EMPLOYEES, SALES_LEADS, ROW_POLICY_MAP, CUSTOMER_CONSENT_MAP)
    All views (CUSTOMER_ORDER_SUMMARY, CUSTOMER_FEEDBACK_SECURE)
    All semantic views (CUSTOMER_ORDER_ANALYTICS)
    All functions (DEAL_AMOUNT_OUT_OF_RANGE data metric function)
    All masking policies (DATA_CLASSIFICATION_MASK_STRING, _NUMBER, _DATE, _TIMESTAMP)
    All row access policies (CUSTOMER_OPTIN_POLICY, CUSTOMER_STATE_RESTRICTIONS, CUSTOMER_ORDERS_STATE_RESTRICTIONS)
    All privacy policies (EMPLOYEE_PRIVACY_POLICY + privacy domains)
    All tags (DATA_CLASSIFICATION with propagation)
=============================================================================*/

SELECT 'Teardown complete. All Horizon Lab objects removed.' AS status;
