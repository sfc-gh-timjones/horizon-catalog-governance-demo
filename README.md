# Snowflake Horizon Catalog — Governance Demo

End-to-end Snowflake Horizon Catalog demo covering discovery, classification, masking, row access, aggregation, projection, data quality, AI governance, audit, and lineage — with idempotent setup and customer-facing demo scripts.

See [`demo-overview.md`](demo-overview.md) for the full demo guide and Horizon pillar descriptions.

---

## Quick Start

| Script | What it does |
|--------|-------------|
| `TEARDOWN_AND_REBUILD.sql` | **Run this first.** One-click deploy: creates git integration, tears down any existing objects, runs all setup scripts. After this, the demo environment is ready. |
| `RUN_ALL_DEMOS.sql` | Smoke test: runs all 6 demo scripts in sequence to validate everything works end-to-end. Requires `TEARDOWN_AND_REBUILD.sql` to have been run first (uses the git integration it creates). |

> **Note:** Access history queries (demo 6) have up to 3-hour latency.
> Results improve the longer the demo environment has been running.
