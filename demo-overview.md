# Snowflake Horizon Catalog — Demo Overview

**Snowflake Horizon** is the built-in governance layer of the Snowflake AI Data Cloud.
It provides unified discovery, security, privacy, quality, and compliance capabilities
that apply to tables, views, AI models, and apps — all from a single control plane.

> **Demo flow:** Discover → Govern → Protect → Trust → AI → Audit

| # | Category | Description |
|---|----------|-----------------|
| 1 | **Discovery & Classification** | Find sensitive data automatically and label it so everyone knows what it is |
| 2 | **Access Control** | Control who can see which rows, columns, and values — and block everything else |
| 3 | **Privacy & Aggregation** | Protect individuals with aggregation policies, differential privacy, and AI-powered PII redaction |
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

## 2. Access Control
**"Control who sees what — rows, columns, and values."**

- Row access policies restrict which rows a role can see (e.g., DATA_USER only sees CA, TX, and MA customers)
- Tag-based dynamic masking applies multi-level protection based on classification:
  - **PII** → fully redacted (`***PII-REDACTED***`)
  - **RESTRICTED** → partial mask (last 4 characters visible)
  - **SENSITIVE** → partial mask (first letter visible, rest asterisks)
  - **INTERNAL** → visible (low risk)
- Same query, same table — different results depending on the role executing it
- Tag propagation: CTAS-derived tables inherit masking automatically — no extra config
- Projection policies control column visibility — a column can be used in WHERE but excluded from output

**Demo script:** [`demo-2-govern.sql`](demo-2-govern.sql)
**Setup reference:** `2-data-governor.sql` (row access, masking, projection policies), `0-setup.sql` (RBAC roles)

---

## 3. Privacy & Aggregation
**"Protect individuals even when data is accessible."**

- Aggregation policies enforce k-anonymity — users must aggregate with minimum group sizes (100+), no individual record access
- Differential privacy on the EMPLOYEES table: individual rows blocked, only noisy aggregates allowed, with confidence intervals (DP_INTERVAL_LOW/HIGH) and a weekly privacy budget
- AI_REDACT detects and removes 50+ PII types from unstructured text (feedback, tickets, emails) — no regex needed
- Partial redaction lets you choose exactly which PII types to redact (e.g., names and emails, but keep phone numbers)
- A role-based redaction view controls who sees PII: governors see original text, analysts see the pre-redacted version
- Safe sentiment analysis on redacted data — analytics without PII exposure

**Demo script:** [`demo-3-privacy.sql`](demo-3-privacy.sql)
**Setup reference:** `2-data-governor.sql` (aggregation policy), `0-setup.sql` (EMPLOYEES + privacy policy), `5-ai-redact.sql` (AI_REDACT + role-based redaction view)

---

## 4. Data Quality & Trust
**"Continuously validate data quality with DMFs + Expectations."**

- Dedicated `SALES_LEADS` table: 3000 synthetic CRM records with intentional quality issues that increase linearly (NULLs, blanks, duplicates, invalid statuses, out-of-range amounts)
- System DMFs (NULL_COUNT, BLANK_COUNT, DUPLICATE_COUNT, ROW_COUNT, ACCEPTED_VALUES) measure quality dimensions automatically
- Custom DMF (`DEAL_AMOUNT_OUT_OF_RANGE`) enforces business rules: deal amounts must be $0–$1M
- EXPECTATION clauses on each DMF define pass/fail thresholds (e.g., `VALUE = 0` for null emails)
- `SYSTEM$EVALUATE_DATA_QUALITY_EXPECTATIONS` produces a one-shot report card showing which expectations pass and which fail
- Inject 200 rows of garbage data mid-demo, then re-evaluate to show how expectations catch regressions in real time
- Historical results stored in `DATA_QUALITY_MONITORING_RESULTS` for trend analysis

**Demo script:** [`demo-4-quality.sql`](demo-4-quality.sql)
**Setup reference:** `0-setup.sql` (SALES_LEADS table), `1-data-engineer.sql` (DMFs + Expectations + custom DMF)

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

**Demo script:** [`demo-6-audit.sql`](demo-6-audit.sql)
**Setup reference:** `3-it-admin.sql` (access history + lineage)

---

## Quick Start

See the [README](README.md) for Quick Start, Setup & Teardown tables, and script inventory.
