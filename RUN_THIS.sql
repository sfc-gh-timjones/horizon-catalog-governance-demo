/***************************************************************************************************
| H | O | R | I | Z | O | N |   | L | A | B | S |

  One-click deployment! This script:
    1. Tears down any existing demo objects (safe to run fresh)
    2. Creates a git repo integration to pull scripts
    3. Runs all setup scripts (0 → 6) via EXECUTE IMMEDIATE

  After this completes, run any demo-*.sql script in any order.
***************************************************************************************************/

USE ROLE ACCOUNTADMIN;
CREATE WAREHOUSE IF NOT EXISTS HRZN_WH WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
USE WAREHOUSE HRZN_WH;

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

/*=============================================================================
  2. TEARDOWN (safe even on first run)
=============================================================================*/

EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/99-teardown.sql;

/*=============================================================================
  3. SETUP (runs in order: 0 → 6)
     Teardown drops HRZN_WH, so recreate a temporary warehouse for EXECUTE IMMEDIATE.
     0-setup.sql will CREATE OR REPLACE it with the correct config.
=============================================================================*/

CREATE WAREHOUSE IF NOT EXISTS HRZN_WH WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
USE WAREHOUSE HRZN_WH;

EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/0-setup.sql;
EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/1-data-engineer.sql;
EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/2-data-governor.sql;
EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/3-it-admin.sql;
EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/4-semantic-views.sql;
EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/5-ai-redact.sql;
EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/6-nl-governance.sql;

/*=============================================================================
  DONE!

  The demo environment is ready. Run any demo script:
    demo-1-discover.sql    Pillar 1: Discovery
    demo-2-govern.sql      Pillar 2: Governance
    demo-3-privacy.sql     Pillar 3: Privacy
    demo-4-quality.sql     Pillar 4: Data Quality
    demo-5-ai-governance.sql  Pillar 5: AI Governance
    demo-6-audit.sql       Pillar 6: Audit & Compliance
=============================================================================*/

SELECT 'Horizon Catalog demo deployed. Run any demo-*.sql script.' AS status;

/*=============================================================================
  FULL CLEANUP (uncomment to remove everything including the git integration)
=============================================================================*/

-- EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/99-teardown.sql;
-- DROP DATABASE IF EXISTS HRZN_DEPLOY;
-- DROP API INTEGRATION IF EXISTS HRZN_GIT_API_INTEGRATION;
