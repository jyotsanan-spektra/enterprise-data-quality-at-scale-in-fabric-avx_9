# Challenge 1: Confirm the medallion foundation and target state

### Estimated Duration: 40 Minutes

## Scenario

You have joined the Contoso data engineering team to build the Microsoft Fabric foundation for an enterprise medallion solution. The Azure-side sandbox is already provisioned, but the Fabric control-plane items required for this lab are not pre-created. Before any ingestion, validation, or modelling work can begin, you must stand up the workspace and the core items that every later challenge depends on.

## Overview

In this challenge you will sign in to Microsoft Fabric, create your own workspace, and create the Lakehouse, Warehouse, notebook, Copy job, and pipeline that support the Bronze, Silver, and Gold layers used throughout the lab. You will then confirm that each item maps to its role in the medallion design.

## Objectives

- Task 1: Sign in and create the Fabric workspace
- Task 2: Create the core Lakehouse and Warehouse items
- Task 3: Create the supporting notebook, Copy job, and pipeline items
- Task 4: Confirm target-state readiness

## Task 1: Sign in and create the Fabric workspace

Sign in to the Azure portal and the Microsoft Fabric portal at <https://app.fabric.microsoft.com> using the lab credentials:

- Username: <inject key="AzureAdUserEmail"></inject>
- Password: <inject key="AzureAdUserPassword"></inject>

Create a Fabric-capable workspace named **contoso-fabric-<inject key="DeploymentID"></inject>**. This workspace is the container for every item you build in this lab.

> [!Note]
> Microsoft Fabric workspaces, Lakehouses, Warehouses, notebooks, Copy jobs, and pipelines are Fabric control-plane objects, not Azure ARM resources. They are learner-created and are not pre-seeded for you.

## Task 2: Create the core Lakehouse and Warehouse items

Inside your new workspace, create the two storage and analytics items that hold the medallion data:

- A **Lakehouse** named **contoso_medallion_lh**, which will hold the Bronze and Silver Delta tables.
- A blank **Warehouse** named **contoso_gold_wh**, which will hold the Gold-layer dimensional model.

Record the Warehouse's **SQL connection string** and **JDBC connection string** from its settings. Later challenges use these to reach `contoso_gold_wh` from a notebook or a pipeline activity.

> [!Important]
> Create a blank Warehouse, not a sample warehouse. Use the exact item names above — later challenges and the lab validations both depend on them.

## Task 3: Create the supporting notebook, Copy job, and pipeline items

Create the three remaining items that support validation, ingestion, and orchestration. Leave them unconfigured; later challenges configure each one:

- A **Notebook** named **nb_data_quality_gate** (the Silver quality gate, Challenge 4)
- A **Copy job** named **orders-to-bronze-cdc** (Bronze ingestion, Challenge 2)
- A **Data pipeline** named **contoso-medallion-orchestration** (end-to-end orchestration, Challenge 6)

## Task 4: Confirm target-state readiness

Confirm that every requirement in the scenario now has a matching item in your workspace, and that each item opens without error. Record the item names in `C:\LabFiles\fabric-item-names.txt` on the lab VM, along with the connection strings from Task 2 — you will reuse them throughout the lab.

Map the objects you have not yet created to their future layer, so the target state is clear before you build it:

| Layer | Object | Created in |
| --- | --- | --- |
| Bronze | `bronze_orders_cdc` table in `contoso_medallion_lh` | Challenge 2 |
| Silver | `silver_orders` table in `contoso_medallion_lh` | Challenge 4 |
| Gold | `dim_customer` table in `contoso_gold_wh` | Challenge 3 |

## Success criteria

| Check | Expected result |
| --- | --- |
| Workspace | **contoso-fabric-<inject key="DeploymentID"></inject>** exists and is Fabric-capable |
| Lakehouse | **contoso_medallion_lh** exists with **Tables** and **Files** areas |
| Warehouse | **contoso_gold_wh** exists and is empty |
| Notebook | **nb_data_quality_gate** exists |
| Copy job | **orders-to-bronze-cdc** exists |
| Pipeline | **contoso-medallion-orchestration** exists |
| Connection strings | SQL and JDBC strings recorded for `contoso_gold_wh` |

<validation step="Validate prerequisite environment readiness and required Fabric object baseline for the medallion scenario."/>

## Summary

In this challenge you created your own Fabric workspace and the six learner-owned items that form the medallion solution, and you confirmed how each item supports the target architecture. Your environment is now ready for CDC ingestion into Bronze, quality-controlled promotion into Silver, SCD Type 2 modelling in the Gold Warehouse, recovery testing, and orchestration.
