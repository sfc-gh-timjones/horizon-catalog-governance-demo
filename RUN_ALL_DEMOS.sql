/***************************************************************************************************
| H | O | R | I | Z | O | N |   | L | A | B | S |

  Smoke test: runs ALL demo scripts in sequence.
  Assumes TEARDOWN_AND_REBUILD.sql has already been run (environment
  is built and git repo integration exists).

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
