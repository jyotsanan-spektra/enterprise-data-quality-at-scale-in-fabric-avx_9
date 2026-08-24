# Enterprise Data Quality at Scale with CDC, SCD Type 2, and Automated Quality Gates in Fabric

Contoso moves roughly 100,000 orders across 5,000 customers through its `Contoso_Operations` system, and every downstream report is rebuilt each night from a full export of that database. The export is slow, it overwrites yesterday's picture of every customer, and nothing inspects the data before analysts consume it. Twice this quarter a batch of orders with missing customer references reached the executive dashboard unnoticed, and the finance team spent a week reconciling revenue that was wrong from the moment it landed.

Three problems sit underneath that. Full-load pipelines reprocess everything nightly even though only a fraction of records changed. Customer attributes are overwritten in place, so the business cannot answer what a customer looked like last quarter. And data quality is an afterthought, so pipelines report success even when the data arriving is incomplete, out of range, or schema-drifted.

In this challenge lab you will replace that process with a medallion architecture on Microsoft Fabric — ingesting only what changed, blocking bad data before it reaches the curated layer, preserving customer history, and proving you can reverse a data incident.

## The Scenario

You have joined the Contoso data engineering team as they rebuild the reporting estate. The Azure sandbox is already provisioned: the `Contoso_Operations` SQL database is live with change data capture enabled on its `Orders` table, the lab virtual machine carries the sample files and simulation scripts, and a storage account is waiting to receive your validation evidence. The Fabric side is empty — no workspace, no Lakehouse, no Warehouse, no pipeline. You create every Fabric item yourself.

The business has four non-negotiable requirements. Ingestion must be incremental, so a second run captures only the change set rather than reloading all 100,000 orders. Promotion to the curated layer must be gated by explicit quality rules. The customer dimension must retain both the current and the expired version of every changed customer. And when something goes wrong, the team must be able to prove what happened and restore the data to a verified point in time.

## What You Will Build

| Component | What It Does |
|---|---|
| **contoso_medallion_lh** | A Fabric Lakehouse holding the Bronze and Silver Delta tables for raw and validated order data |
| **orders-to-bronze-cdc** | A Copy job landing `Contoso_Operations.Orders` into `bronze_orders_cdc`, capturing only changed rows after the initial load |
| **nb_data_quality_gate** | A PySpark notebook enforcing five quality rules and writing `silver_orders` only when the blocking rules pass |
| **contoso_gold_wh** | A Fabric Warehouse holding `dim_customer`, an SCD Type 2 dimension that preserves customer history |
| **silver_orders_backup** | A Delta shallow clone created during recovery, backing a restore proven with time travel |
| **contoso-medallion-orchestration** | A Data Factory pipeline chaining ingestion, validation, and the Gold load, with retries and a failure branch |

## Solution Architecture

Operational changes originate in the `Contoso_Operations` SQL database, where CDC records every insert and update to the `Orders` table. A Fabric Copy job reads those changes into the Bronze Delta table `bronze_orders_cdc` — a full snapshot on the first run, then only the delta on every run afterwards.

Bronze is treated as untrusted. A PySpark notebook evaluates it against five explicit rules covering nulls, ranges, referential integrity, freshness, and schema drift, and promotes it to the Silver table `silver_orders` only when the blocking rules pass. When they fail, the notebook raises an exception and Silver is left exactly as it was. In the Gold layer, a Fabric Warehouse holds `dim_customer`, where changed customers are expired rather than overwritten so both the historical and the current version stay queryable.

Because Silver is a Delta table, every write is a version. When a faulty job zeroes revenue across a thousand rows, Delta history identifies the last good version, time travel verifies it before anything is changed, and a restore returns the table to that state while preserving the incident in the log. Finally, a Data Factory pipeline runs ingestion, the quality gate, and the Gold load in sequence, so a clean run completes end to end and a failing quality gate blocks downstream Gold processing.

## Key Tools and Services

- **Microsoft Fabric** - the unified SaaS platform hosting the workspace, Lakehouse, Warehouse, notebook, Copy job, and pipeline
- **OneLake** - the single tenant-wide data lake underlying every Fabric item in the solution
- **Fabric Data Factory** - provides the Copy job used for CDC ingestion and the pipeline used for orchestration
- **Change data capture** - the Azure SQL feature that lets Bronze ingestion capture only inserts and updates since the previous run
- **Fabric Lakehouse and Delta Lake** - stores Bronze and Silver as versioned Delta tables, enabling history, time travel, restore, and shallow clone
- **Apache Spark and PySpark notebooks** - implement the quality gate that decides whether Bronze may be promoted to Silver
- **Fabric Warehouse and T-SQL** - hosts the Gold dimensional model and the stored procedure that applies SCD Type 2 changes
- **SQL analytics endpoint** - T-SQL access over the Lakehouse tables for verification queries

## Learning Objectives

By the end of this challenge lab, you will know how to:

- Create a Fabric workspace and the Lakehouse, Warehouse, notebook, Copy job, and pipeline items a medallion solution requires
- Configure a Copy job for CDC-based incremental ingestion and prove from run metrics that only changed rows were processed
- Build an SCD Type 2 customer dimension that expires prior versions instead of overwriting them
- Write change-processing logic that is safe to re-run, so it can be invoked from an orchestration pipeline without creating duplicate versions
- Implement PySpark quality checks for nulls, ranges, referential integrity, freshness, and schema drift
- Gate promotion to the curated layer so a failing check blocks the write and fails the notebook
- Use Delta Lake history and time travel to identify a last known good version and restore a corrupted table
- Create a shallow clone backup and explain when it is and is not appropriate
- Orchestrate the end-to-end flow with retries and a failure branch, and prove both the success and failure paths from run history

## Challenge Lab Format

6 challenges, each building progressively on the previous. Estimated total time: 4 hours. Rather than a click-by-click walkthrough, each challenge states the outcome you must achieve and the success criteria it is measured against, and leaves the implementation to you. Every challenge ends by uploading an evidence file that the lab's automated validation checks, so record row counts, run metrics, and version numbers as you go. Working knowledge of SQL and PySpark is assumed.
