/***************************************************************************************************
| H | O | R | I | Z | O | N |   | D | E | M | O |

  Demo 5: AI & Semantic Governance
  "AI queries inherit governance automatically."

  What you'll show:
    - Semantic views define business-friendly dimensions, metrics, relationships
    - SEMANTIC_VIEW() queries return analytics results
    - All masking + row access policies apply automatically — zero extra config
    - Same semantic query, different results by role

  Setup references:
    - Semantic view DDL (15 dims, 7 metrics, 3 facts): 4-semantic-views.sql lines 25-117
    - SEMANTIC_VIEW() query examples:                   4-semantic-views.sql lines 133-159
    - Policy inheritance demo:                          4-semantic-views.sql lines 168-183
***************************************************************************************************/

USE WAREHOUSE HRZN_WH;
USE DATABASE HRZN_DB;
USE SCHEMA HRZN_SCH;

/*=============================================================================
  SEMANTIC VIEW QUERIES — Business Analytics
  
  Semantic views let Cortex Analyst translate natural language
  into SQL. Here we query the view directly with SEMANTIC_VIEW().
  
  Setup ref: 4-semantic-views.sql lines 25-117
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;

-- Revenue by state
SELECT * FROM SEMANTIC_VIEW(
    CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS customers.location_state
    METRICS orders.total_revenue, orders.total_orders
)
ORDER BY TOTAL_REVENUE DESC;

-- Top 10 customers by revenue
SELECT * FROM SEMANTIC_VIEW(
    CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS customers.customer_name, customers.email_address, customers.location_state
    METRICS orders.total_revenue
)
ORDER BY TOTAL_REVENUE DESC
LIMIT 10;

-- Revenue by year and month
SELECT * FROM SEMANTIC_VIEW(
    CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS orders.order_year, orders.order_month
    METRICS orders.total_revenue, orders.average_order_value
)
ORDER BY ORDER_YEAR, ORDER_MONTH;

/*=============================================================================
  POLICY INHERITANCE — Same Query, Different Results
  
  The semantic view sits on top of CUSTOMER and CUSTOMER_ORDERS.
  All masking and row access policies on those tables apply
  automatically to semantic view queries. No extra configuration.
  
  Setup ref: 4-semantic-views.sql lines 168-183
=============================================================================*/

-- GOVERNOR: sees real names, real emails, all states
USE ROLE HRZN_DATA_GOVERNOR;
SELECT * FROM SEMANTIC_VIEW(
    CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS customers.customer_name, customers.email_address, customers.location_state
    METRICS orders.total_revenue
)
ORDER BY TOTAL_REVENUE DESC
LIMIT 10;

-- DATA USER: emails MASKED, only MA rows visible
USE ROLE HRZN_DATA_USER;
SELECT * FROM SEMANTIC_VIEW(
    CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS customers.customer_name, customers.email_address, customers.location_state
    METRICS orders.total_revenue
)
ORDER BY TOTAL_REVENUE DESC
LIMIT 10;
