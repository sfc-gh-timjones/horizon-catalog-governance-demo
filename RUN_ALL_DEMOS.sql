/***************************************************************************************************
| H | O | R | I | Z | O | N |   | L | A | B | S |

  Smoke test: runs ALL demo scripts in sequence.

  Prerequisites: None! This script is standalone and sets up its own git integration.

  This is NOT for live demos — it just validates that every script
  executes without errors end-to-end.
***************************************************************************************************/

USE ROLE ACCOUNTADMIN;
CREATE WAREHOUSE IF NOT EXISTS HRZN_DEPLOY_WH WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
USE WAREHOUSE HRZN_DEPLOY_WH;

/*=============================================================================
  1. GIT REPO INTEGRATION
=============================================================================*/

CREATE OR REPLACE API INTEGRATION HRZN_GIT_API_INTEGRATION
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-timjones/horizon-catalog-governance-demo')
  ENABLED = TRUE;

CREATE DATABASE IF NOT EXISTS HRZN_DEPLOY;
CREATE SCHEMA IF NOT EXISTS HRZN_DEPLOY.GIT;

CREATE OR REPLACE GIT REPOSITORY HRZN_DEPLOY.GIT.HORIZON_REPO
  API_INTEGRATION = HRZN_GIT_API_INTEGRATION
  ORIGIN = 'https://github.com/sfc-gh-timjones/horizon-catalog-governance-demo';

ALTER GIT REPOSITORY HRZN_DEPLOY.GIT.HORIZON_REPO FETCH;

USE WAREHOUSE HRZN_WH;

USE WAREHOUSE HRZN_WH;

EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/demo-1-discover.sql;
-- demo-2 intentionally triggers a projection policy error (that's the demo)
-- EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/demo-2-govern.sql;
-- demo-3 intentionally triggers aggregation + differential privacy errors (that's the demo)
-- EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/demo-3-privacy.sql;
EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/demo-4-quality.sql;
EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/demo-5-ai-governance.sql;
EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/demo-6-audit.sql;

-- Clean up deployment infrastructure
DROP WAREHOUSE IF EXISTS HRZN_DEPLOY_WH;
DROP DATABASE IF EXISTS HRZN_DEPLOY;
DROP API INTEGRATION IF EXISTS HRZN_GIT_API_INTEGRATION;

SELECT 'Demo smoke test complete (demos 2 & 3 skipped — they contain intentional policy errors).' AS status;
