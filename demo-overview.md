# Snowflake Horizon Catalog — Demo Overview

**Snowflake Horizon** is the built-in governance layer of the Snowflake AI Data Cloud.
It provides unified discovery, security, privacy, quality, and compliance capabilities
that apply to tables, views, AI models, and apps — all from a single control plane.

> **Demo flow:** Discover → Govern → Protect → Trust → AI → Audit

| # | Category | Description |
|---|----------|-----------------|
| 1 | **Discovery & Classification** | Find sensitive data automatically and label it so everyone knows what it is |
| 2 | **Governance & Policy Enforcement** | Control who can see which rows, columns, and records — and block everything else |
| 3 | **Privacy Protection** | Scramble, mask, or hide sensitive values so the wrong people never see the real data |
| 4 | **Data Quality & Trust** | Continuously check that data is accurate, complete, and not broken |
| 5 | **AI & Semantic Governance** | Make sure AI-powered analytics follow the same security rules as everything else |
| 6 | **Audit, Lineage & Compliance** | Track who accessed what, when, and prove to auditors that your controls actually work |

---

## 1. Discovery & Classification
**"Snowflake automatically finds and labels sensitive data."**

- AI-powered classification scans every column and detects PII, financial data, and personal identifiers
- Detected data is mapped to enterprise classification levels: **PII, RESTRICTED, SENSITIVE, INTERNAL, PUBLIC**
- Custom classifiers extend detection with business-specific patterns (e.g., credit card regex)
- Tag propagation ensures labels follow the data — CTAS, INSERT...SELECT, or any transformation automatically inherits tags

**Demo script:** [`demo-1-discover.sql`](demo-1-discover.sql)
**Setup reference:** `2-data-governor.sql` (classification + tag propagation), `0-setup.sql` (environment)

---

## 2. Governance & Policy Enforcement
**"Define who can see which data."**

- Row access policies restrict which rows a role can see (e.g., DATA_USER only sees CA, TX, and MA customers)
- Aggregation policies enforce k-anonymity — users must aggregate with minimum group sizes (100+), no individual record access
- Projection policies control column visibility — a column can be used in WHERE but excluded from output
- All policies are role-aware: governors and engineers see everything, restricted roles see filtered results

**Demo script:** [`demo-2-govern.sql`](demo-2-govern.sql)
**Setup reference:** `2-data-governor.sql` (row access, aggregation, projection policies), `0-setup.sql` (RBAC roles)

---

## 3. Privacy Protection
**"Protect sensitive data automatically."**

- Tag-based dynamic masking applies multi-level protection based on classification:
  - **PII** → fully redacted (`***PII-REDACTED***`)
  - **RESTRICTED** → partial mask (last 4 characters visible)
  - **SENSITIVE** → SHA2 hash (pseudonymized)
  - **INTERNAL** → visible (low risk)
- Same query, same table — different results depending on the role executing it
- AI_REDACT detects and removes 50+ PII types from unstructured text (feedback, tickets, emails) — no regex needed
- Partial redaction lets you choose exactly which PII types to redact (e.g., names and emails, but keep phone numbers)
- Secure views provide role-based access: governors see original PII, analysts see the pre-redacted version
- Differential privacy on the EMPLOYEES table: individual rows blocked, only noisy aggregates allowed, with confidence intervals (DP_INTERVAL_LOW/HIGH) and a weekly privacy budget

**Demo script:** [`demo-3-privacy.sql`](demo-3-privacy.sql)
**Setup reference:** `2-data-governor.sql` (masking policies), `5-ai-redact.sql` (AI_REDACT + secure view), `0-setup.sql` (EMPLOYEES + privacy policy)

---

## 4. Data Quality & Trust
**"Continuously validate data quality."**

- System Data Metric Functions (DMFs) measure null counts, uniqueness, duplicates, and row counts out of the box
- Custom DMFs extend quality checks with business rules (e.g., regex-based invalid email detection)
- DMFs run on automated schedules (TRIGGER_ON_CHANGES in this demo) — no external orchestrator needed
- Historical results are stored in `DATA_QUALITY_MONITORING_RESULTS` for trend analysis and alerting

**Demo script:** [`demo-4-quality.sql`](demo-4-quality.sql)
**Setup reference:** `1-data-engineer.sql` (DMF creation + scheduling)

---

## 5. AI & Semantic Governance
**"AI queries inherit governance automatically."**

- Semantic views are first-class database objects that define business-friendly dimensions, metrics, and relationships
- Cortex Analyst uses semantic views to answer natural language questions with SQL
- All masking policies, row access policies, and other controls on the underlying tables automatically apply to semantic view queries — zero extra configuration
- Same semantic query returns full data for a governor and filtered/masked data for a restricted user

**Demo script:** [`demo-5-ai-governance.sql`](demo-5-ai-governance.sql)
**Setup reference:** `4-semantic-views.sql` (semantic view DDL)

---

## 6. Audit, Lineage & Compliance
**"Prove governance works."**

- Access history tracks every query: who accessed what data, when, and how (read vs. write)
- Login history shows user activity over 90 days with active/recent/stale status
- Warehouse metering reveals credit consumption by warehouse
- Query attribution ties credit spend back to individual users
- Object dependency lineage shows which views, tables, and semantic views depend on each other — useful for impact analysis
- Role effectiveness analysis compares granted privileges vs. actual usage to identify dormant or over-provisioned roles
- Governance scorecard summarizes policy coverage across the environment

**Demo script:** [`demo-6-audit.sql`](demo-6-audit.sql)
**Setup reference:** `3-it-admin.sql` (access history + lineage), `6-nl-governance.sql` (governance queries)

---

## Setup & Teardown

| Script | Purpose |
|--------|---------|
| `0-setup.sql` | Idempotent environment build: roles, warehouse, database, schemas, data load from S3, EMPLOYEES table + differential privacy |
| `1-data-engineer.sql` | DMF creation, custom DMF, scheduling |
| `2-data-governor.sql` | Classification, masking, row access, aggregation, projection, tag propagation |
| `3-it-admin.sql` | Access history queries, lineage, role effectiveness |
| `4-semantic-views.sql` | Semantic view DDL and verification |
| `5-ai-redact.sql` | Customer feedback data, AI_REDACT, secure view |
| `6-nl-governance.sql` | Natural language governance queries |
| `99-teardown.sql` | Clean teardown: drop everything |

> **Note:** Access history queries (scripts 3 and 6) have up to 3-hour latency.
> Results improve the longer the demo environment has been running.
