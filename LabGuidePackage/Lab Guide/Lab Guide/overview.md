# Enterprise Data Quality at Scale in Fabric

Contoso processes around 100,000 orders across 5,000 customers through its `Contoso_Operations` system, and every downstream report is built on a nightly full-table export of that database. The exports are slow, they overwrite yesterday's picture of every customer, and nothing inspects the data before it reaches the analysts. Twice this quarter, a batch of orders with missing customer references reached the executive dashboard unnoticed, and the finance team spent a week reconciling revenue figures that were wrong from the moment they landed.

The Director of Data Engineering has mandated a rebuild on Microsoft Fabric before the October 2026 quarterly business review. Ingestion must capture only what changed rather than recopying the entire table. Bad data must be stopped before it reaches the curated layer, not discovered afterwards. Customer history must be preserved instead of overwritten. And when something does go wrong, the team must be able to prove what happened and roll the data back to a known good state.

In this challenge lab you will build that medallion architecture end to end - from CDC-based ingestion into Bronze, through a Spark quality gate that blocks bad data from Silver, to an SCD Type 2 customer dimension in Gold, with Delta Lake recovery controls and a pipeline that orchestrates the whole flow and proves both its success and failure paths.

## The Scenario

You have joined the Contoso data engineering team as they modernise the reporting estate. The Azure sandbox is provisioned and the `Contoso_Operations` SQL database is live with change data capture enabled on its `Orders` table, but the Fabric side is empty - no workspace, no Lakehouse, no Warehouse, no pipeline. You will create every Fabric item yourself.

The business has four non-negotiable requirements. Ingestion has to be incremental, so a second run captures roughly 500 changed rows rather than reloading all 100,000. Promotion to the curated layer has to be gated by explicit quality rules covering nulls, ranges, referential integrity, freshness, and schema drift. The customer dimension has to keep both the current and the expired version of every changed customer. And the team must be able to recover a corrupted table to a verified point in time without losing the audit trail of the incident.

## What You Will Build

| Component | What It Does |
|---|---|
| **contoso_medallion_lh** | A Fabric Lakehouse holding the Bronze and Silver Delta tables that carry raw and validated order data |
| **orders-to-bronze-cdc** | A Copy job that lands `Contoso_Operations.Orders` into `bronze_orders_cdc`, capturing only changed rows after the initial load |
| **nb_data_quality_gate** | A PySpark notebook enforcing five quality rules, writing `silver_orders` only when the blocking rules pass |
| **contoso_gold_wh** | A Fabric Warehouse holding `dim_customer`, an SCD Type 2 dimension preserving customer history |
| **silver_orders_backup** | A Delta shallow clone created during recovery, backing a restore proven with time travel |
| **contoso-medallion-orchestration** | A Data Factory pipeline chaining ingestion, validation, and Gold loading, with retries and a failure branch |

## Solution Architecture

Operational changes originate in the `Contoso_Operations` SQL database, where CDC records every insert and update to the `Orders` table. A Fabric Copy job reads those changes and lands them in the Bronze Delta table `bronze_orders_cdc` - a full snapshot on the first run, then only the delta on every run after.

Bronze is treated as untrusted. A PySpark notebook evaluates it against five explicit rules and promotes it to the Silver table `silver_orders` only when the blocking rules pass; when they fail, the notebook raises and Silver is left exactly as it was. In the Gold layer, a Fabric Warehouse holds `dim_customer`, where changed customers are expired rather than overwritten so that both the historical and the current version remain queryable.

Because Silver is a Delta table, every write is a version. When a faulty job corrupts revenue values, Delta history identifies the last good version, time travel verifies it before anything is changed, and a restore returns the table to that state while preserving the incident in the log. Finally, a Data Factory pipeline runs ingestion, the quality gate, and the Gold load in sequence, so that a clean run completes end to end and a failing quality gate blocks downstream Gold processing.

## Key Tools and Services

- **Microsoft Fabric** - the unified SaaS platform hosting the workspace, Lakehouse, Warehouse, notebook, Copy job, and pipeline
- **OneLake** - the single tenant-wide data lake underlying every Fabric item in the solution
- **Fabric Data Factory** - provides the Copy job used for CDC ingestion and the pipeline used for orchestration
- **Change data capture (CDC)** - the Azure SQL feature that lets Bronze ingestion capture only inserts and updates since the last run
- **Fabric Lakehouse and Delta Lake** - stores Bronze and Silver as versioned Delta tables, enabling history, time travel, restore, and shallow clone
- **Fabric notebooks (PySpark)** - implement the quality gate that decides whether Bronze may be promoted to Silver
- **Fabric Warehouse (T-SQL)** - hosts the Gold dimensional model and the stored procedure that applies SCD Type 2 changes

## Learning Objectives

By the end of this challenge lab, you will know how to:

- Create a Fabric workspace and the Lakehouse, Warehouse, notebook, Copy job, and pipeline items that a medallion solution requires
- Configure a Copy job for CDC-based incremental ingestion and prove from run metrics that only changed rows were processed
- Build an SCD Type 2 customer dimension that expires prior versions instead of overwriting them
- Write a re-runnable stored procedure so change processing can be safely invoked from an orchestration pipeline
- Implement PySpark quality checks for nulls, ranges, referential integrity, freshness, and schema drift
- Gate promotion to the curated layer so a failing check blocks the write and fails the notebook
- Use Delta Lake history and time travel to identify a last known good version and restore a corrupted table
- Create a shallow clone backup and explain when it is and is not appropriate
- Orchestrate the end-to-end flow with retries and a failure branch, and prove both the success and failure paths from run history

## Challenge Lab Format

6 challenges, each building on the last. Level L300 - Advanced. Estimated total time: 4 hours. Unlike a step-by-step walkthrough, each challenge states the outcome you must achieve and the criteria it is measured against, and leaves the implementation to you. Working knowledge of SQL and PySpark is assumed.
