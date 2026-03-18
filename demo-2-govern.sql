/***************************************************************************************************
| H | O | R | I | Z | O | N |   | D | E | M | O |

  Demo 2: Access Control
  "Control who sees what — rows, columns, and values."

  What you'll show:
    - Row access policy: DATA_USER only sees CA, TX, MA customers
    - Tag-based dynamic masking: same query, different results by role
    - Multi-level masking: PII→redacted, RESTRICTED→partial, SENSITIVE→partial mask
    - Tag propagation: CTAS-derived tables inherit masking automatically
    - Projection policy: ZIP can't be projected, but CAN be used in WHERE

  Setup references:
    - RBAC roles + grants:               0-setup.sql lines 31-47
    - Row policy mapping table:           0-setup.sql lines 100-107
    - State-based row access policy:      2-data-governor.sql lines 333-345
    - Tag-based masking policies:         2-data-governor.sql lines 186-243
    - Tag propagation (CUSTOMER_COPY):    2-data-governor.sql lines 288-309
    - Projection policy:                  2-data-governor.sql lines 390-399
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
  TAG-BASED DYNAMIC MASKING — Same Query, Different Results
  
  The DATA_CLASSIFICATION tag drives 4 masking policies (STRING, NUMBER,
  DATE, TIMESTAMP). One tag, automatic enforcement on every tagged column.
  
    PII        → fully redacted (***PII-REDACTED***)
    RESTRICTED → partial mask (last 4 chars visible)
    SENSITIVE  → partial mask (first letter visible, rest asterisks)
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
  PROJECTION POLICY — Layered with Masking (Both Active on ZIP)
  
  ZIP already has a SENSITIVE masking tag (partial mask for DATA_USER).
  We now ADD a projection policy on top — both coexist on the same column.
  DATA_USER cannot project ZIP at all. If they EXCLUDE ZIP, masking
  still applies to every other SENSITIVE column (names, addresses).
  
  This demonstrates layered governance: masking + projection on one column.
  
  Setup ref: 2-data-governor.sql lines 392-401
  ⚠ If script stops before cleanup, re-run from line 109 or run 0-setup.sql.
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;

ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER MODIFY COLUMN ZIP
    SET PROJECTION POLICY HRZN_DB.TAG_SCHEMA.projection_policy;

USE ROLE HRZN_DATA_USER;

-- FAILS: ZIP is projection constrained (even though masking is also active)
SELECT TOP 10 * FROM HRZN_DB.HRZN_SCH.CUSTOMER;

-- WORKS: exclude ZIP — masking still active on names, addresses, etc.
SELECT TOP 10 * EXCLUDE ZIP FROM HRZN_DB.HRZN_SCH.CUSTOMER;

-- WORKS: ZIP can be used in WHERE (filter without seeing the value)
SELECT * EXCLUDE ZIP FROM HRZN_DB.HRZN_SCH.CUSTOMER WHERE ZIP IN ('53596','38106','62568') LIMIT 5;

USE ROLE HRZN_DATA_GOVERNOR;

ALTER TABLE HRZN_DB.HRZN_SCH.CUSTOMER MODIFY COLUMN ZIP UNSET PROJECTION POLICY;
