# Challenge 1: Confirm the medallion foundation and target state

### Estimated Duration: 40 Minutes

## Scenario

You are taking ownership of a Microsoft Fabric data engineering solution for the Contoso operations workload. Later challenges depend on a working Fabric foundation, but Fabric control-plane items such as Lakehouses, Warehouses, notebooks, pipelines, and Copy jobs are not Azure resources that can be deployed through ARM. In this challenge, you will establish the Fabric items you need for the rest of the lab and align them to the intended medallion architecture.

## Overview

In this challenge, you will sign in to the lab environment, create or confirm the core Fabric workspace items for Bronze, Silver, and Gold processing, and document a naming and responsibility model that supports CDC ingestion, data quality enforcement, historical dimensions, recovery validation, and orchestration.

## Objectives

- Task 1: Sign in and review the Fabric workspace context
- Task 2: Create the core Fabric items for the medallion implementation
- Task 3: Confirm naming, ownership, and downstream readiness

## Task 1: Sign in and review the Fabric workspace context

In this task, you will access the lab environment and confirm the workspace context you will use throughout the lab.

1. Sign in to the Azure portal at <https://portal.azure.com> using the following credentials:
   - Username: <inject key="AzureAdUserEmail"></inject>
   - Password: <inject key="AzureAdUserPassword"></inject>
2. Record your deployment identifier for reference during the lab: **<inject key="DeploymentID" enableCopy="false"/>**.
3. Open Microsoft Fabric at <https://app.fabric.microsoft.com> with the same lab account and go to the workspace assigned to this lab.
4. Confirm that the workspace is available on Fabric capacity and that you can create new Fabric items in it.
5. Review the Contoso operations scenario and identify the logical flow you will complete across the remaining challenges: CDC ingestion into Bronze, curated promotion into Silver, customer history management in Gold, Spark-based quality checks, Delta-based recovery validation, and pipeline orchestration.
6. Decide on a consistent naming standard you will use for all items created in this lab so later work remains easy to trace.

> [!Note]
> A Fabric workspace is the container for the items used in this lab. The workspace might already exist, but the implementation items you need later must be created or completed inside Fabric as part of the challenge flow.

## Task 2: Create the core Fabric items for the medallion implementation

In this task, you will create or establish the main Fabric control-plane items required for the rest of the lab.

1. In the workspace, create a Lakehouse that will host the engineering layers for the solution.
2. Use a name that clearly supports the medallion design, and plan to store Bronze and Silver Delta tables in this Lakehouse.
3. Create a Warehouse in the same workspace that will serve as the Gold analytical store for dimensional history and reporting-oriented SQL work.
4. Create a notebook item that you will later use for PySpark-based data quality checks and Delta Lake recovery operations.
5. Create a pipeline item that will later orchestrate ingestion, quality validation, dimension loading, and success or failure handling.
6. Create a Copy job item, or otherwise establish the ingestion item you will use later, for CDC-based movement of `Contoso_Operations.Orders` into the Bronze layer.
7. Open each item once and confirm it initializes successfully in the workspace so you know the environment is ready for later implementation.
8. Record the exact names of the Lakehouse, Warehouse, notebook, pipeline, and ingestion item you created.

> [!Important]
> Microsoft Learn documents Lakehouse, Warehouse, notebook, pipeline, and Copy job creation as Fabric workspace actions. These are Fabric control-plane items, so this lab treats them as learner-created assets rather than pre-seeded Azure resources.

## Task 3: Confirm naming, ownership, and downstream readiness

In this task, you will align the newly established Fabric items to the intended medallion architecture and verify they are ready for the remaining challenges.

1. Confirm that the Lakehouse is the destination for raw and curated Delta tables, including the future `bronze_orders_cdc` and `silver_orders` tables.
2. Confirm that the Warehouse will hold the Gold customer dimension and any related SQL-based history tracking structures needed for SCD Type 2 implementation.
3. Associate the notebook with the Lakehouse context you created so it is ready for Spark-based validation and Delta history work in later challenges.
4. Confirm that the pipeline can reference the notebook and the ingestion path you created so it can later coordinate the end-to-end workflow.
5. Verify that the source connectivity and prerequisite Contoso_Operations data are available for later CDC ingestion work, even if you do not build the full logic yet in this challenge.
6. Create a short design note for yourself that maps each item to its purpose: Bronze ingestion, Silver quality gate, Gold history tracking, recovery testing, and orchestration.
7. Review the overall target state and confirm there is no remaining ambiguity about which Fabric item will be used in each later challenge.

<validation step="Validate prerequisite environment readiness and required Fabric object baseline for the medallion scenario."/>

## Summary

In this challenge, you established the core Fabric workspace items required for the lab, aligned them to the Bronze, Silver, and Gold pattern, and confirmed that the environment is ready for CDC ingestion, Spark-based quality enforcement, Warehouse-based history tracking, Delta recovery testing, and end-to-end orchestration.