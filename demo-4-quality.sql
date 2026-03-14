/***************************************************************************************************
| H | O | R | I | Z | O | N |   | D | E | M | O |

  Demo 4: Data Quality & Trust
  "Continuously validate data quality."

  What you'll show:
    - System DMFs: null count, unique count, duplicate count, row count
    - Custom DMF: regex-based invalid email detection
    - Automated 5-minute scheduling
    - Historical quality monitoring results

  Setup references:
    - System DMFs attached to CUSTOMER:     1-data-engineer.sql lines 55-61
    - Custom INVALID_EMAIL_COUNT DMF:       1-data-engineer.sql lines 73-80
    - DMF scheduling (5 minute):            1-data-engineer.sql lines 86-89
    - DMF schedule verification:            1-data-engineer.sql lines 93-96
***************************************************************************************************/

USE ROLE HRZN_DATA_ENGINEER;
USE WAREHOUSE HRZN_WH;
USE DATABASE HRZN_DB;
USE SCHEMA HRZN_SCH;

/*=============================================================================
  LIVE DATA QUALITY STATS
  
  Call system and custom DMFs inline to see current data quality.
  These same functions run automatically every 5 minutes on schedule.
  
  Setup ref: 1-data-engineer.sql lines 55-80
=============================================================================*/

SELECT
    SNOWFLAKE.CORE.NULL_COUNT(SELECT EMAIL FROM HRZN_DB.HRZN_SCH.CUSTOMER) AS null_emails,
    SNOWFLAKE.CORE.UNIQUE_COUNT(SELECT EMAIL FROM HRZN_DB.HRZN_SCH.CUSTOMER) AS unique_emails,
    SNOWFLAKE.CORE.DUPLICATE_COUNT(SELECT EMAIL FROM HRZN_DB.HRZN_SCH.CUSTOMER) AS duplicate_emails,
    HRZN_DB.HRZN_SCH.INVALID_EMAIL_COUNT(SELECT EMAIL FROM HRZN_DB.HRZN_SCH.CUSTOMER) AS invalid_emails;

/*=============================================================================
  AUTOMATED SCHEDULING
  
  All 5 DMFs run every 5 minutes. No external orchestrator needed.
  
  Setup ref: 1-data-engineer.sql lines 86-96
=============================================================================*/

SELECT metric_name, ref_entity_name, schedule, schedule_status
FROM TABLE(information_schema.data_metric_function_references(
    ref_entity_name => 'HRZN_DB.HRZN_SCH.CUSTOMER',
    ref_entity_domain => 'TABLE'));

/*=============================================================================
  HISTORICAL DMF RESULTS
  
  Every scheduled run stores results for trend analysis and alerting.
  Note: May need a few minutes after setup to populate.
  
  Setup ref: 1-data-engineer.sql lines 98-107
=============================================================================*/

SELECT change_commit_time, measurement_time, table_name, metric_name, value
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
WHERE table_database = 'HRZN_DB'
ORDER BY change_commit_time DESC;
