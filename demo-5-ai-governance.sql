/***************************************************************************************************
| H | O | R | I | Z | O | N |   | D | E | M | O |

  Demo 5: AI & Semantic Governance
  "AI queries inherit governance automatically."

  What you'll show:
    - Semantic views define business-friendly dimensions, metrics, relationships
    - Same semantic query, different results by role — zero extra config
    - Row access policies filter states, masking policies hash PII
    - Governance follows data into the semantic layer automatically

  Setup references:
    - Semantic view DDL (15 dims, 7 metrics, 3 facts): 4-semantic-views.sql lines 25-117
    - SEMANTIC_VIEW() query examples:                   4-semantic-views.sql lines 133-159
    - Policy inheritance demo:                          4-semantic-views.sql lines 168-183
***************************************************************************************************/

USE WAREHOUSE HRZN_WH;
USE DATABASE HRZN_DB;
USE SCHEMA HRZN_SCH;

/*=============================================================================
  TOP CUSTOMERS BY REVENUE — Governor vs Data User

  Same semantic query, two roles. Governor sees all states and real PII.
  Data User sees only CA, TX, MA — names and emails are masked.

  Setup ref: 4-semantic-views.sql lines 25-117
=============================================================================*/

-- GOVERNOR: all states, real names, real emails
USE ROLE HRZN_DATA_GOVERNOR;

SELECT * FROM SEMANTIC_VIEW(
    HRZN_DB.HRZN_SCH.CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS customers.customer_name, customers.email_address, customers.location_state
    METRICS orders.total_revenue
)
ORDER BY TOTAL_REVENUE DESC
LIMIT 10;

-- DATA USER: only CA/TX/MA, names and emails masked
USE ROLE HRZN_DATA_USER;

SELECT * FROM SEMANTIC_VIEW(
    HRZN_DB.HRZN_SCH.CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS customers.customer_name, customers.email_address, customers.location_state
    METRICS orders.total_revenue
)
ORDER BY TOTAL_REVENUE DESC
LIMIT 10;

/*=============================================================================
  REVENUE BY STATE — Row Access Policy in Action

  Governor sees revenue across all 50 states.
  Data User sees only 3 states — the rest are filtered out silently.

  Setup ref: 4-semantic-views.sql lines 168-183
=============================================================================*/

-- GOVERNOR: all states
USE ROLE HRZN_DATA_GOVERNOR;

SELECT * FROM SEMANTIC_VIEW(
    HRZN_DB.HRZN_SCH.CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS customers.location_state
    METRICS orders.total_revenue, orders.total_orders
)
ORDER BY TOTAL_REVENUE DESC;

-- DATA USER: only CA, TX, MA
USE ROLE HRZN_DATA_USER;

SELECT * FROM SEMANTIC_VIEW(
    HRZN_DB.HRZN_SCH.CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS customers.location_state
    METRICS orders.total_revenue, orders.total_orders
)
ORDER BY TOTAL_REVENUE DESC;
