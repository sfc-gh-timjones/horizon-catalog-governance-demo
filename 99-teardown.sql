/***************************************************************************************************
| H | O | R | I | Z | O | N |   | L | A | B | S |

Demo:         Horizon Catalog - Teardown (Clean Reset)
Version:      HLab v2.1 (Idempotent)
***************************************************************************************************/

/*=============================================================================
  TEARDOWN
  
  Removes ALL demo objects. Safe to run multiple times — every statement
  is guarded with IF EXISTS and runs as ACCOUNTADMIN (always available).
=============================================================================*/

USE ROLE ACCOUNTADMIN;

DROP DATABASE IF EXISTS HRZN_DB;

DROP ROLE IF EXISTS HRZN_DATA_ANALYST;
DROP ROLE IF EXISTS HRZN_DATA_GOVERNOR;
DROP ROLE IF EXISTS HRZN_DATA_USER;
DROP ROLE IF EXISTS HRZN_IT_ADMIN;
DROP ROLE IF EXISTS HRZN_DATA_ENGINEER;

DROP WAREHOUSE IF EXISTS HRZN_WH;

/*=============================================================================
  TEARDOWN COMPLETE
  
  All Horizon Lab objects removed:
    HRZN_DB database and ALL contents (schemas, tables, views, functions)
    Custom roles (HRZN_DATA_GOVERNOR, HRZN_DATA_USER, HRZN_IT_ADMIN, HRZN_DATA_ENGINEER, HRZN_DATA_ANALYST)
    HRZN_WH warehouse

  Dropping the database automatically removes:
    All schemas (HRZN_SCH, CLASSIFIERS, TAG_SCHEMA, AUDIT_RESULTS)
    All tables (CUSTOMER, CUSTOMER_ORDERS, CUSTOMER_COPY, CUSTOMER_FEEDBACK_REDACTED, EMPLOYEES, SALES_LEADS, ROW_POLICY_MAP, CUSTOMER_CONSENT_MAP)
    All views (CUSTOMER_ORDER_SUMMARY, CUSTOMER_FEEDBACK_SECURE)
    All semantic views (CUSTOMER_ORDER_ANALYTICS)
    All functions (DEAL_AMOUNT_OUT_OF_RANGE data metric function)
    All masking policies (DATA_CLASSIFICATION_MASK_STRING, _NUMBER, _DATE, _TIMESTAMP)
    All row access policies (CUSTOMER_OPTIN_POLICY, CUSTOMER_STATE_RESTRICTIONS, CUSTOMER_ORDERS_STATE_RESTRICTIONS)
    All privacy policies (EMPLOYEE_PRIVACY_POLICY + privacy domains)
    All classification profiles (HRZN_STANDARD_CLASSIFICATION_PROFILE)
    All tags (DATA_CLASSIFICATION with propagation)
=============================================================================*/

SELECT 'Teardown complete. All Horizon Lab objects removed.' AS status;
