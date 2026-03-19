# Snowflake Horizon Catalog — Governance Demo

> **Based on Snowflake's official Horizon getting-started guide**, tailored and extended for specific demo purposes with additional pillars and synthetic datasets.
> - Quickstart Guide: [Getting Started with Horizon for Data Governance](https://www.snowflake.com/en/developers/guides/getting-started-with-horizon-for-data-governance-in-snowflake/)
> - Original GitHub Repo: [sfguide-getting-started-with-horizon-data-governance-in-snowflake](https://github.com/Snowflake-Labs/sfguide-getting-started-with-horizon-data-governance-in-snowflake)

End-to-end Snowflake Horizon Catalog demo covering discovery, classification, masking, row access, aggregation, projection, data quality, AI governance, audit, and lineage — with idempotent setup and customer-facing demo scripts.

See [`demo-overview.md`](demo-overview.md) for the full demo guide and Horizon pillar descriptions.

---

## Quick Start

### Step 1: Create a Git API Integration & Connect Your Workspace

Before running any scripts, you need a Git API integration so Snowflake can pull from this repo — and a Workspace linked to it so you can browse and run the files.

1. Navigate to **Projects → Workspaces** in Snowsight.
2. Open a blank SQL file and run the following as `ACCOUNTADMIN`:

```sql
USE ROLE ACCOUNTADMIN;

CREATE API INTEGRATION IF NOT EXISTS GIT_HUB_INTEGRATION
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/')
  ENABLED = TRUE;
```

3. At the top of the left-hand file pane, click the **dropdown arrow** next to your current workspace name (likely **My Workspace**).
4. Select **From Git repository**.
5. Fill in the form:
   - **Repository URL:** `https://github.com/sfc-gh-timjones/horizon-catalog-governance-demo`
   - **Workspace name:** e.g. `Horizon Demo`
   - **API integration:** select `GIT_HUB_INTEGRATION` (the one you just created)
     > If `GIT_HUB_INTEGRATION` doesn't appear in the dropdown, log out and log back in — since it was just created, Snowsight may not have picked it up yet.
   - **Repository access:** select **Public repository**
     > Note: public repositories are read-only — you will not be able to push changes from this Workspace.
6. Click **Create**.

Your Workspace is now connected to the repo and all scripts are accessible in the left pane.

### Step 2: Deploy the Demo Environment

| Script | What it does |
|--------|-------------|
| `TEARDOWN_AND_REBUILD.sql` | **Run this next.** Tears down any existing objects, runs all setup scripts in order. After this, the demo environment is ready. |

---

## Running the Demos

Once `TEARDOWN_AND_REBUILD.sql` has completed, the environment is fully ready. Simply open and run any demo script — no additional setup needed:

> **Note:** You could technically run each setup script (`0-setup.sql` through `6-nl-governance.sql`) manually one by one, but `TEARDOWN_AND_REBUILD.sql` handles the full sequence automatically via the Git integration — making it a seamless, one-click experience.

| Script | Pillar |
|--------|--------|
| `demo-1-discover.sql` | Pillar 1: Sensitive Data Discovery & Classification |
| `demo-2-govern.sql` | Pillar 2: Access Control & Dynamic Masking |
| `demo-3-privacy.sql` | Pillar 3: Privacy, Aggregation & AI Redaction |
| `demo-4-quality.sql` | Pillar 4: Data Quality & Trust |
| `demo-5-ai-governance.sql` | Pillar 5: AI & Semantic Governance |
| `demo-6-audit.sql` | Pillar 6: Audit, Lineage & Compliance |

### Why setup and demo scripts are separate

The setup scripts (`0-setup.sql` through `6-nl-governance.sql`) contain everything needed to build the environment: creating roles, tables, policies, tags, classification profiles, and pre-computing audit tables from `ACCOUNT_USAGE`. Some operations — like pre-computing audit snapshots from `ACCOUNT_USAGE` — are intentionally run ahead of time so the live walkthrough stays instant and focused.

The demo scripts assume all objects already exist and focus purely on showcasing the governance features.

> **Tip:** Each demo script includes exact line references back to the relevant setup file — so if a customer asks how something was configured, you can navigate directly to the source.

---

## Teardown

When you're done and want to remove all demo objects without rebuilding, run the following (or equivalently, run `99-teardown.sql`):

```sql
USE ROLE ACCOUNTADMIN;

DROP DATABASE IF EXISTS HRZN_DB;

DROP ROLE IF EXISTS HRZN_DATA_ANALYST;
DROP ROLE IF EXISTS HRZN_DATA_GOVERNOR;
DROP ROLE IF EXISTS HRZN_DATA_USER;
DROP ROLE IF EXISTS HRZN_IT_ADMIN;
DROP ROLE IF EXISTS HRZN_DATA_ENGINEER;

DROP WAREHOUSE IF EXISTS HRZN_WH;
```
