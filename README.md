# Snowflake Horizon Catalog — Governance Demo

End-to-end Snowflake Horizon Catalog demo covering discovery, classification, masking, row access, aggregation, projection, data quality, AI governance, audit, and lineage — with idempotent setup and customer-facing demo scripts.

See [`demo-overview.md`](demo-overview.md) for the full demo guide and Horizon pillar descriptions.

---

## Quick Start

| Script | What it does |
|--------|-------------|
| `TEARDOWN_AND_REBUILD.sql` | **Run this first.** One-click deploy: creates git integration, tears down any existing objects, runs all setup scripts. After this, the demo environment is ready. |

---

## Running the Demos

Once `TEARDOWN_AND_REBUILD.sql` has completed, the environment is fully ready. Simply open and run any demo script — no additional setup needed:

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
