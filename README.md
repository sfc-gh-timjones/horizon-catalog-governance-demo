# Snowflake Horizon Catalog — Governance Demo

End-to-end Snowflake Horizon Catalog demo covering discovery, classification, masking, row access, aggregation, projection, data quality, AI governance, audit, and lineage — with idempotent setup and customer-facing demo scripts.

See [`demo-overview.md`](demo-overview.md) for the full demo guide and Horizon pillar descriptions.

---

## Quick Start

| Script | What it does |
|--------|-------------|
| `TEARDOWN_AND_REBUILD.sql` | **Run this first.** One-click deploy: creates git integration, tears down any existing objects, runs all setup scripts. After this, the demo environment is ready. |

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
