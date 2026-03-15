/***************************************************************************************************
| H | O | R | I | Z | O | N |   | L | A | B | S |

  Smoke test: runs ALL demo scripts in sequence.

  Prerequisites:
    - TEARDOWN_AND_REBUILD.sql must have been run first. It creates:
        1. The HRZN_DEPLOY database + HRZN_GIT_API_INTEGRATION (git repo)
        2. All demo objects (HRZN_DB, roles, warehouse, tables, policies)

  This is NOT for live demos — it just validates that every script
  executes without errors end-to-end.
***************************************************************************************************/

ALTER GIT REPOSITORY HRZN_DEPLOY.GIT.HORIZON_REPO FETCH;

USE WAREHOUSE HRZN_WH;

EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/demo-1-discover.sql;
EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/demo-2-govern.sql;
EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/demo-3-privacy.sql;
EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/demo-4-quality.sql;
EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/demo-5-ai-governance.sql;
EXECUTE IMMEDIATE FROM @HRZN_DEPLOY.GIT.HORIZON_REPO/branches/main/demo-6-audit.sql;

SELECT 'All 6 demo scripts completed successfully.' AS status;
