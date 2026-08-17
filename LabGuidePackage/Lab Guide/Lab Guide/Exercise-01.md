# Challenge 1: Confirm the medallion foundation and target state

### Estimated Duration: 40 Minutes

## Scenario

You have joined the Contoso data engineering team to build the Fabric foundation for an enterprise medallion solution. The Azure-side sandbox prerequisites are already in place, but the Microsoft Fabric control-plane items required for this lab are not pre-created. In this challenge, you will sign in, create the Microsoft Fabric workspace yourself, create the core Fabric items inside that workspace, and verify that the environment is ready for CDC ingestion, Spark quality gates, Warehouse-based historical modeling, and orchestration in the later challenges.

## Overview

In this challenge, you will access the lab environment, open Microsoft Fabric, create a new learner-owned workspace, and then create the Lakehouse, Warehouse, notebook, pipeline, and copy job required to support the Bronze, Silver, and Gold layers used throughout the lab.

## Objectives

- Task 1: Sign in and create the Fabric workspace
- Task 2: Create the core Lakehouse and Warehouse items
- Task 3: Create supporting notebook, pipeline, and copy job items
- Task 4: Verify target-state readiness for the remaining challenges

## Task 1: Sign in and create the Fabric workspace

In this task, you will sign in with the lab account, open Microsoft Fabric, and create the workspace that will contain all learner-created Fabric items for the rest of the lab.

1. Sign in to the Azure portal at <https://portal.azure.com> by using the following credentials:
   - Username: <inject key="AzureAdUserEmail"></inject>
   - Password: <inject key="AzureAdUserPassword"></inject>
2. Record the deployment identifier for this lab session as **<inject key="DeploymentID" enableCopy="false"/>**.
3. In a new browser tab, open the Microsoft Fabric portal at <https://app.fabric.microsoft.com>.
4. If prompted, sign in with the same lab account.
5. In the left navigation menu, select **Workspaces**.
6. Select **+ New workspace** (labeled just **New workspace** in some Fabric versions).
7. In the **Create a workspace** pane, enter **contoso-fabric-<inject key="DeploymentID"></inject>** as the workspace name.
8. Optionally, enter a short description such as **Workspace for the Contoso medallion challenge lab**.
9. Expand **Advanced** if the option is available.
10. Verify that the workspace is assigned to a Fabric-capable workspace type or capacity. If your environment exposes a **Workspace type** choice, select **Fabric** or **Fabric Trial** as appropriate for the lab environment.
11. Select **Apply** to create the workspace.
12. Wait for the new workspace to open.
13. Confirm that the workspace opens successfully and that you can see the **+ New item** option.

> [!Note]
> Microsoft Learn documents the Fabric workspace as the container for lakehouses, warehouses, notebooks, pipelines, and other Fabric items. In this lab, the workspace is learner-created and is not pre-seeded for you.

## Task 2: Create the core Lakehouse and Warehouse items

In this task, you will create the primary storage and analytical items for the medallion architecture inside the workspace you just created.

1. In your new workspace, select **+ New item**.
2. In the item picker, search for **Lakehouse**, and then select **Lakehouse**.
3. In the **New lakehouse** dialog, enter **contoso_medallion_lh** as the name.
4. Leave the default **Lakehouse schemas** setting enabled unless your environment requires a different setting, and then select **Create**.
5. Wait for the Lakehouse to open in the explorer view.
6. Confirm that the new Lakehouse contains the **Tables** and **Files** areas.
7. Return to the workspace.
8. Select **+ New item** again.
9. Search for **Warehouse**, and then select **Warehouse**.
10. In the **New warehouse** dialog, enter **contoso_gold_wh** as the name.
11. Select **Create**.
12. Wait until the Warehouse opens successfully.
13. In the Warehouse, note that this item will later host the Gold-layer customer dimension and SCD Type 2 logic.
14. Select **Settings** (or the connection icon) on the Warehouse ribbon and record both the **SQL connection string** and the **JDBC connection string** shown there. Save these values in `C:\LabFiles\fabric-item-names.txt` — later challenges reuse them to reach `contoso_gold_wh` from a notebook or pipeline activity without querying through the attached-item experience.
15. Return to the workspace and verify that both **contoso_medallion_lh** and **contoso_gold_wh** are now listed.

> [!Important]
> Create a blank Warehouse, not a sample warehouse. You need an empty object that you will configure during later challenges.

## Task 3: Create supporting notebook, pipeline, and copy job items

In this task, you will create the remaining Fabric items that support Spark validation, orchestration, and ingestion.

1. In the workspace, select **+ New item**.
2. Search for **Notebook**, and then select **Notebook**.
3. Create a notebook named **nb_data_quality_gate**.
4. When the notebook opens, confirm that the default notebook canvas is available, and then return to the workspace.
5. Select **+ New item**.
6. Search for **Data pipeline**, and then select **Data pipeline**.
7. Create a pipeline named **contoso-medallion-orchestration**.
8. When the pipeline canvas opens, confirm it loads successfully, and then return to the workspace.
9. Select **+ New item** one more time.
10. Search for **Copy job**, and then select **Copy job**.
11. Enter **orders-to-bronze-cdc** as the copy job name, and create the item.
12. When the copy job interface opens, stop before configuring the source and destination because that work is completed in the next challenge.
13. Return to the workspace.
14. Verify that all six learner-created Fabric items are visible in the workspace:
    - **contoso-fabric-<inject key="DeploymentID"></inject>**
    - **contoso_medallion_lh**
    - **contoso_gold_wh**
    - **nb_data_quality_gate**
    - **contoso-medallion-orchestration**
    - **orders-to-bronze-cdc**
15. Record these exact names in your notes because you will reuse them throughout the lab.

## Task 4: Verify target-state readiness for the remaining challenges

In this task, you will map each created item to the medallion design and confirm the environment is ready for downstream implementation.

1. Confirm that your new workspace is the container for all Fabric items you will build in this lab.
2. Open **contoso_medallion_lh** and confirm that it will be used for the Bronze and Silver Delta tables in this lab. Neither `bronze_orders_cdc` nor `silver_orders` exists yet — Challenges 2 and 4 create them.
3. Open `C:\LabFiles\fabric-item-names.txt` (the notes file you started in Task 2) and add these two lines so the layer mapping is recorded before you build it:
   - `bronze_orders_cdc -> Bronze layer table in contoso_medallion_lh (created in Challenge 2)`
   - `silver_orders -> Silver layer table in contoso_medallion_lh (created in Challenge 4)`
4. Open **contoso_gold_wh** and confirm that it will be used for the Gold-layer dimensional model, including the customer dimension that will track historical changes.
5. Open **nb_data_quality_gate** and confirm that this notebook will later hold the PySpark logic that checks null handling, ranges, referential integrity, freshness, and schema expectations before Silver promotion.
6. Open **orders-to-bronze-cdc** and confirm that this item will later ingest data from the prepared Contoso_Operations source into the Bronze layer.
7. Open **contoso-medallion-orchestration** and confirm that this pipeline will later orchestrate ingestion, quality validation, Gold loading, and success or failure branches.
8. Review the overall medallion flow and confirm that each major requirement from the scenario now has a matching learner-created Fabric item:
   - Workspace container for the lab solution
   - Bronze ingestion
   - Silver quality gate
   - Gold history tracking
   - Delta audit and recovery operations
   - End-to-end orchestration
9. Verify that you can open each item without errors.
10. Keep your recorded item names available for the later challenges.

<validation step="Validate prerequisite environment readiness and required Fabric object baseline for the medallion scenario."/>

## Summary

In this challenge, you signed in to Microsoft Fabric, created your own workspace, created the core learner-owned Fabric items for the lab, and confirmed how each item supports the target medallion architecture. Your environment is now prepared for CDC ingestion into Bronze, quality-controlled promotion into Silver, SCD Type 2 modeling in the Gold Warehouse, recovery testing, and orchestration in the remaining challenges.
