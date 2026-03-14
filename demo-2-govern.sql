/***************************************************************************************************
| H | O | R | I | Z | O | N |   | D | E | M | O |

  Demo 2: Governance & Policy Enforcement
  "Define who can see which data."

  What you'll show:
    - Row access policy: DATA_USER only sees CA, TX, MA customers
    - Aggregation policy: must aggregate with 100+ group size, no individual records
    - Projection policy: ZIP can't be projected, but CAN be used in WHERE

  Setup references:
    - RBAC roles + grants:               0-setup.sql lines 31-47
    - Row policy mapping table:           0-setup.sql lines 100-107
    - State-based row access policy:      2-data-governor.sql lines 333-345
    - Aggregation policy:                 2-data-governor.sql lines 360-369
    - Projection policy:                  2-data-governor.sql lines 392-401
***************************************************************************************************/

USE WAREHOUSE HRZN_WH;
USE DATABASE HRZN_DB;
USE SCHEMA HRZN_SCH;

/*=============================================================================
  ROW ACCESS POLICY — Geographic Filtering
  
  The ROW_POLICY_MAP table maps HRZN_DATA_USER → CA, TX, MA.
  The governor sees all 1,000 customers. The data user sees only those 3 states.
  
  Setup ref: 2-data-governor.sql lines 333-345
=============================================================================*/

-- What the mapping table looks like
USE ROLE HRZN_DATA_GOVERNOR;
SELECT * FROM HRZN_DB.TAG_SCHEMA.ROW_POLICY_MAP;

-- GOVERNOR: All states, all rows
SELECT STATE, COUNT(*) AS customer_count
FROM HRZN_DB.HRZN_SCH.CUSTOMER
GROUP BY STATE ORDER BY customer_count DESC;

-- DATA USER: Only CA, TX, MA
USE ROLE HRZN_DATA_USER;
SELECT STATE, COUNT(*) AS customer_count
FROM HRZN_DB.HRZN_SCH.CUSTOMER
GROUP BY STATE ORDER BY customer_count DESC;

/*=============================================================================
  AGGREGATION POLICY — k-Anonymity Enforcement
  
  DATA_USER cannot SELECT individual records from CUSTOMER_ORDERS.
  They CAN run aggregates — but only when groups contain 100+ rows.
  This prevents re-identification attacks on small groups.
  
  Setup ref: 2-data-governor.sql lines 360-369
  Note: Re-applying policy for this demo section.
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;
ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS
    SET AGGREGATION POLICY HRZN_DB.TAG_SCHEMA.aggregation_policy;

USE ROLE HRZN_DATA_USER;
--USE ROLE HRZN_DATA_GOVERNOR;

-- FAILS: can't select individual records
SELECT TOP 10 * FROM HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS;

-- WORKS: aggregate with large enough groups
SELECT ORDER_CURRENCY, SUM(ORDER_AMOUNT) AS total_amount
FROM HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS GROUP BY ORDER_CURRENCY;

USE ROLE HRZN_DATA_GOVERNOR;
ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS UNSET AGGREGATION POLICY;

/*=============================================================================
  PROJECTION POLICY — Column-Level Access Control
  
  ZIP column is projection-constrained for DATA_USER.
  They CANNOT include it in query output.
  They CAN use it in WHERE clauses (filter without seeing the value).
  
  Setup ref: 2-data-governor.sql lines 392-401
  Note: Re-applying policy for this demo section.
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;
ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER MODIFY COLUMN ZIP UNSET TAG HRZN_DB.TAG_SCHEMA.DATA_CLASSIFICATION;
ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER MODIFY COLUMN ZIP
    SET PROJECTION POLICY HRZN_DB.TAG_SCHEMA.projection_policy;

USE ROLE HRZN_DATA_USER;

-- FAILS: ZIP is projection constrained
SELECT TOP 10 * FROM HRZN_DB.HRZN_SCH.CUSTOMER;

-- WORKS: exclude ZIP from output
SELECT TOP 10 * EXCLUDE ZIP FROM HRZN_DB.HRZN_SCH.CUSTOMER;

-- WORKS: ZIP can be used in WHERE (filter without seeing)
SELECT * EXCLUDE ZIP FROM HRZN_DB.HRZN_SCH.CUSTOMER WHERE ZIP IN ('53596','38106','62568') LIMIT 5;

USE ROLE HRZN_DATA_GOVERNOR;
ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER MODIFY COLUMN ZIP UNSET PROJECTION POLICY;
ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER MODIFY COLUMN ZIP SET TAG HRZN_DB.TAG_SCHEMA.DATA_CLASSIFICATION = 'SENSITIVE';
