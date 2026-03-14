/***************************************************************************************************
| H | O | R | I | Z | O | N |   | L | A | B | S |

Demo:         Horizon Catalog - Lab 4: Semantic View Governance
Version:      HLab v2.1 (Idempotent)
***************************************************************************************************/

USE ROLE HRZN_DATA_GOVERNOR;
USE WAREHOUSE HRZN_WH;
USE DATABASE HRZN_DB;
USE SCHEMA HRZN_SCH;

/*=============================================================================
  SEMANTIC VIEW FOR CORTEX ANALYST
  
  Semantic Views are first-class database objects that define:
  - Logical tables (mapped to physical tables)
  - Relationships between tables
  - Facts (raw values), Dimensions (attributes), Metrics (aggregates)
  
  Existing masking/row access policies on underlying tables
  AUTOMATICALLY apply to semantic view queries.
=============================================================================*/

CREATE OR REPLACE SEMANTIC VIEW CUSTOMER_ORDER_ANALYTICS

  TABLES (
    customers AS HRZN_DB.HRZN_SCH.CUSTOMER
      PRIMARY KEY (ID)
      WITH SYNONYMS ('customer', 'clients', 'buyers')
      COMMENT = 'Customer master data with PII protection',

    orders AS HRZN_DB.HRZN_SCH.CUSTOMER_ORDERS
      PRIMARY KEY (ORDER_ID)
      WITH SYNONYMS ('sales orders', 'transactions', 'purchases')
      COMMENT = 'Customer order transactions'
  )

  RELATIONSHIPS (
    orders_to_customers AS
      orders (CUSTOMER_ID) REFERENCES customers (ID)
  )

  FACTS (
    orders.order_amount_fact AS ORDER_AMOUNT
      COMMENT = 'Order amount before tax',
    orders.order_tax_fact AS ORDER_TAX
      COMMENT = 'Tax amount on order',
    orders.order_total_fact AS ORDER_TOTAL
      COMMENT = 'Total order amount including tax'
  )

  DIMENSIONS (
    customers.customer_name AS CONCAT(FIRST_NAME, ' ', LAST_NAME)
      WITH SYNONYMS = ('full name', 'name')
      COMMENT = 'Customer full name',
    customers.first_name AS FIRST_NAME
      COMMENT = 'Customer first name',
    customers.last_name AS LAST_NAME
      COMMENT = 'Customer last name',
    customers.email_address AS EMAIL
      WITH SYNONYMS = ('email', 'contact email')
      COMMENT = 'Customer email (masked for non-admin roles)',
    customers.phone AS PHONE_NUMBER
      WITH SYNONYMS = ('phone number', 'contact number')
      COMMENT = 'Customer phone (conditionally masked)',
    customers.location_state AS STATE
      WITH SYNONYMS = ('state', 'region')
      COMMENT = 'Customer state (subject to row-level security)',
    customers.location_city AS CITY
      WITH SYNONYMS = ('city', 'town')
      COMMENT = 'Customer city',
    customers.company_name AS COMPANY
      WITH SYNONYMS = ('company', 'employer', 'organization')
      COMMENT = 'Customer company',
    customers.job_title AS JOB
      WITH SYNONYMS = ('job', 'position', 'role')
      COMMENT = 'Customer job title',
    customers.customer_id AS ID
      COMMENT = 'Unique customer identifier',

    orders.order_id AS ORDER_ID
      WITH SYNONYMS = ('order number')
      COMMENT = 'Unique order identifier',
    orders.order_date AS ORDER_TS
      WITH SYNONYMS = ('date', 'order timestamp')
      COMMENT = 'Order date',
    orders.order_year AS YEAR(ORDER_TS)
      COMMENT = 'Year when the order was placed',
    orders.order_month AS MONTH(ORDER_TS)
      COMMENT = 'Month when the order was placed',
    orders.currency AS ORDER_CURRENCY
      WITH SYNONYMS = ('order currency')
      COMMENT = 'Order currency code'
  )

  METRICS (
    customers.customer_count AS COUNT(ID)
      COMMENT = 'Count of customers',
    orders.total_revenue AS SUM(orders.order_total_fact)
      WITH SYNONYMS = ('total sales', 'revenue')
      COMMENT = 'Total revenue from orders',
    orders.total_orders AS COUNT(ORDER_ID)
      WITH SYNONYMS = ('order count', 'number of orders')
      COMMENT = 'Total number of orders',
    orders.average_order_value AS AVG(orders.order_total_fact)
      WITH SYNONYMS = ('AOV', 'avg order')
      COMMENT = 'Average order value',
    orders.total_tax AS SUM(orders.order_tax_fact)
      COMMENT = 'Total tax collected',
    orders.max_order AS MAX(orders.order_total_fact)
      COMMENT = 'Largest single order',
    orders.min_order AS MIN(orders.order_total_fact)
      COMMENT = 'Smallest single order'
  )

  COMMENT = 'Semantic view for customer order analysis with built-in governance';

/*=============================================================================
  VERIFY THE SEMANTIC VIEW
=============================================================================*/

SHOW SEMANTIC VIEWS LIKE 'CUSTOMER_ORDER_ANALYTICS';
SHOW SEMANTIC DIMENSIONS IN CUSTOMER_ORDER_ANALYTICS;
SHOW SEMANTIC METRICS IN CUSTOMER_ORDER_ANALYTICS;
SHOW SEMANTIC FACTS IN CUSTOMER_ORDER_ANALYTICS;
DESCRIBE SEMANTIC VIEW CUSTOMER_ORDER_ANALYTICS;

/*=============================================================================
  QUERY THE SEMANTIC VIEW
=============================================================================*/

SELECT * FROM SEMANTIC_VIEW(
    CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS customers.location_state
    METRICS orders.total_revenue, orders.total_orders
)
ORDER BY TOTAL_REVENUE DESC;

SELECT * FROM SEMANTIC_VIEW(
    CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS customers.customer_name, customers.company_name
    METRICS orders.total_revenue, orders.total_orders
)
ORDER BY TOTAL_REVENUE DESC
LIMIT 10;

SELECT * FROM SEMANTIC_VIEW(
    CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS orders.order_year, orders.order_month
    METRICS orders.total_revenue, orders.average_order_value
)
ORDER BY ORDER_YEAR, ORDER_MONTH;

SELECT * FROM SEMANTIC_VIEW(
    CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS orders.currency
    METRICS orders.total_revenue, orders.total_orders, orders.average_order_value
);

/*=============================================================================
  POLICY INHERITANCE DEMO
  
  Existing masking and row access policies on underlying tables
  automatically apply to semantic view queries — no extra config needed!
=============================================================================*/

USE ROLE HRZN_DATA_GOVERNOR;
SELECT * FROM SEMANTIC_VIEW(
    CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS customers.customer_name, customers.email_address, customers.location_state
    METRICS orders.total_revenue
)
LIMIT 5;

USE ROLE HRZN_DATA_USER;

SELECT * FROM SEMANTIC_VIEW(
    CUSTOMER_ORDER_ANALYTICS
    DIMENSIONS customers.customer_name, customers.email_address, customers.location_state
    METRICS orders.total_revenue
)
LIMIT 5;

USE ROLE HRZN_DATA_GOVERNOR;
