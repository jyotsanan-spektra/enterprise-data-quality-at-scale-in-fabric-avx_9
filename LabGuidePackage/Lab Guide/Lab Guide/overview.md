# Enterprise Data Quality at Scale: CDC Ingestion, SCD Type 2 History, and Automated Data Quality Checks in a Medallion Lakehouse

## Lab at a Glance

| | |
|---|---|
| **Use Case** | 4 |
| **Track** | L300 — Data Engineering & Analytics |
| **Level** | L300 — Advanced |
| **Duration** | Approximately 4 hours across 6 progressive challenges |
| **Audience** | Senior data engineers with a SQL and ETL background |
| **Primary Tools** | Fabric Data Factory Copy Job (CDC), Fabric Lakehouse, Fabric Warehouse, Apache Spark (PySpark), Delta Lake Time Travel, Fabric Pipelines |

## Problem Statement

Enterprise data teams face three persistent problems when building production-grade pipelines.

First, full-load pipelines are inefficient. They reprocess the entire source every night even though only a fraction of records actually changed. Second, slowly changing dimensions are difficult to implement correctly at scale — most teams fall back on ad-hoc scripts that silently produce duplicate versions, or overwrite history altogether, the moment the source shifts. Third, data quality is treated as an afterthought: pipelines report success even when the data arriving is incomplete, out of range, or schema-drifted, so the failure surfaces later as a broken dashboard and a loss of trust in the platform.

Contoso is living all three. Roughly 100,000 orders across 5,000 customers move through the `Contoso_Operations` system, every downstream report is rebuilt from a nightly full-table export, and nothing inspects that data before analysts consume it. Customer attributes are overwritten in place, so the business cannot answer what a customer looked like last quarter. In this lab you will replace that process with a medallion architecture on Microsoft Fabric that ingests only what changed, blocks bad data before it reaches the curated layer, preserves customer history, and can prove and reverse a data incident.

## The Scenario

You have joined the Contoso data engineering team as they rebuild the reporting estate. The Azure sandbox is already provisioned and the `Contoso_Operations` SQL database is live with change data capture enabled on its `Orders` table — but the Fabric side is empty. There is no workspace, no Lakehouse, no Warehouse, and no pipeline. You create every Fabric item yourself.

The business has four non-negotiable requirements: ingestion must be incremental, promotion to the curated layer must be gated by explicit quality rules, the customer dimension must retain both current and expired versions, and the team must be able to recover a corrupted table to a verified point in time without losing the audit trail.

## What Is Already Provisioned

The sandbox deploys the Azure-side prerequisites before you begin:

| Resource | Detail |
|---|---|
| **`Contoso_Operations` Azure SQL database** | Seeded with 100,000 `Orders`, 5,000 `Customers`, and 1,000 `Products`, with CDC enabled on `dbo.Orders` |
| **Lab virtual machine** | Preloaded with the sample files, the order-change simulation script, and the tooling used through the lab |
| **Validation storage account** | Holds the `validation` container that each challenge uploads its evidence to |
| **`C:\LabFiles\.env`** | Carries the SQL connection details, storage account name, and Fabric item naming used throughout |

Everything on the Fabric side is learner-created, because Fabric workspaces, Lakehouses, Warehouses, notebooks, Copy jobs, and pipelines are control-plane objects rather than Azure ARM resources.

## What You Will Build

| Component | What It Does |
|---|---|
| **`contoso_medallion_lh`** | Fabric Lakehouse holding the Bronze and Silver Delta tables |
| **`orders-to-bronze-cdc`** | Copy job landing `Contoso_Operations.Orders` into `bronze_orders_cdc`, capturing only changed rows after the initial load |
| **`nb_data_quality_gate`** | PySpark notebook enforcing five quality rules and writing `silver_orders` only when the blocking rules pass |
| **`quality_gate_log`** | Delta table recording each rule's outcome per run, so quality evidence survives outside the notebook |
| **`contoso_gold_wh`** | Fabric Warehouse holding `dim_customer`, the SCD Type 2 customer dimension |
| **`usp_process_customer_changes`** | Re-runnable stored procedure applying Type 2 changes, invoked directly by the orchestration pipeline |
| **`silver_orders_backup`** | Delta shallow clone created during recovery, backing a restore proven with time travel |
| **`contoso-medallion-orchestration`** | Pipeline chaining ingestion, the quality gate, and the Gold load, with retry and a failure branch |

## Solution Architecture

Operational changes originate in `Contoso_Operations`, where CDC records every insert and update to `Orders`. A Fabric Copy job reads those changes into the Bronze Delta table `bronze_orders_cdc` — a full snapshot on the first run, then only the delta on every run afterwards.

Bronze is treated as untrusted. A PySpark notebook evaluates it against five explicit rules and promotes it to `silver_orders` only when the blocking rules pass; when they fail, the notebook raises an exception and Silver is left exactly as it was. In Gold, a Fabric Warehouse holds `dim_customer`, where changed customers are expired rather than overwritten so both the historical and current version stay queryable.

Because Silver is a Delta table, every write is a version. When a faulty job zeroes revenue on 1,000 rows, Delta history identifies the last good version, time travel verifies it before anything changes, and a restore returns the table to that state while preserving the incident in the log. Finally, a Data Factory pipeline runs ingestion, the quality gate, and the Gold load in sequence, so a clean run completes end to end and a failing gate blocks downstream Gold processing.

## Challenges

| # | Challenge | Focus | Duration |
|---|---|---|---|
| 1 | Confirm the medallion foundation and target state | Create the workspace and the six Fabric items the lab depends on | 40 min |
| 2 | Implement CDC ingestion into the Bronze layer | Configure incremental CDC ingestion and prove only changed rows are processed | 40 min |
| 3 | Implement SCD Type 2 history in the Gold Warehouse | Build the customer dimension and apply Type 2 change processing | 40 min |
| 4 | Enforce Spark-based data quality gates before Silver promotion | Implement five quality rules and gate promotion on the blocking ones | 40 min |
| 5 | Audit, recover, and protect data with Delta Lake time travel | Reproduce an incident, identify the last good version, restore, and clone | 40 min |
| 6 | Orchestrate the end-to-end medallion pipeline | Chain the flow with retries and a failure branch, and prove both paths | 45 min |

## Outcomes Expected

By the end of this lab you will be able to:

- Configure CDC-based ingestion from a SQL source using a Fabric Data Factory Copy job, and prove from run metrics that a second run processed only the change set
- Implement SCD Type 2 dimension history in the Fabric Warehouse, expiring prior versions instead of overwriting them
- Write change-processing logic that is safe to re-run, so it can be invoked from an orchestration pipeline without creating duplicate versions
- Build automated data quality checks in a Spark notebook that gate promotion into the Silver layer
- Use Delta Lake time travel to audit a data quality incident and restore a table to a verified last known good version
- Create a shallow clone backup and explain where it is and is not appropriate
- Wire the full flow into a Fabric pipeline with retry logic and a failure branch, and evidence both the success and failure paths from run history

## Technology Used

- **Microsoft Fabric** — the SaaS platform hosting the workspace, Lakehouse, Warehouse, notebook, Copy job, and pipeline
- **OneLake** — the tenant-wide data lake underlying every Fabric item in the solution
- **Fabric Data Factory** — the Copy job used for CDC ingestion and the pipeline used for orchestration
- **Change data capture (CDC)** — the Azure SQL feature letting Bronze ingestion capture only inserts and updates since the previous run
- **Fabric Lakehouse and Delta Lake** — stores Bronze and Silver as versioned Delta tables, enabling history, time travel, restore, and shallow clone
- **Apache Spark (PySpark)** — implements the quality gate deciding whether Bronze may be promoted to Silver
- **Fabric Warehouse (T-SQL)** — hosts the Gold dimensional model and the SCD Type 2 stored procedure
- **SQL analytics endpoint** — T-SQL access over the Lakehouse tables for verification queries

## Lab Format

Six challenges, each building on the last. Rather than a click-by-click walkthrough, each challenge states the outcome you must achieve and the success criteria it is measured against, then leaves the implementation to you. Every challenge ends by uploading an evidence file that the lab's automated validation checks, so record the row counts, run metrics, and version numbers as you go. Working knowledge of SQL and PySpark is assumed.
