# Challenge 6: Orchestrate the end-to-end medallion pipeline with internal run-state validation

### Estimated Duration: 45 Minutes

## Scenario

You have implemented the core components of the Contoso medallion solution in Microsoft Fabric. The final step is to orchestrate those learner-created items into one pipeline that runs the Bronze ingestion step, the Spark quality gate, and the Gold load in a controlled sequence. You must also prove that the pipeline behaves correctly in both a clean-data run and a deliberate failure run, using only Fabric-native monitoring and run-state evidence.

## Overview

In this challenge, you will create or complete a Fabric pipeline that coordinates the medallion flow across the items you built in earlier challenges. You will configure activity order, retry behavior, and a failure branch, then run the pipeline twice: once for a successful path and once for a controlled quality-failure path. Finally, you will review run history and activity outputs and save the evidence required for validation.

## Objectives

- Task 1: Create the orchestration pipeline and add the required activities
- Task 2: Configure dependencies, retry behavior, and failure handling
- Task 3: Run the success and failure paths and capture internal evidence

> [!Important]
> This exercise assumes `C:\LabFiles\.env` and a pre-provisioned validation storage account exist, and that the `usp_process_customer_changes` stored procedure from Challenge 3 was actually created successfully. In this environment none of that can be assumed — Task 3's upload steps below reuse the storage account created in Challenge 2, Task 6 instead of reading `.env`, and this exercise adds explicit guidance for connection setup, the stored-procedure check, and a critical notebook cleanup step that the original steps did not call out.

## Task 1: Create the orchestration pipeline and add the required activities

In this task, you will create the pipeline canvas and add the activities that represent your end-to-end medallion process.

1. Open a browser and go to the Microsoft Fabric portal at <https://app.fabric.microsoft.com>.
2. Sign in with the lab credentials provided for your environment.
   - Username: <inject key="AzureAdUserEmail"></inject>
   - Password: <inject key="AzureAdUserPassword"></inject>
3. Open the workspace that you used throughout this lab.
4. Confirm the following four Fabric items, plus one Warehouse stored procedure, are available before you build the orchestration:
   - **contoso_medallion_lh** — the Lakehouse containing `bronze_orders_cdc` and `silver_orders` (Challenges 1, 2, 4)
   - **contoso_gold_wh** — the Warehouse containing `dim_customer` (Challenges 1, 3)
   - **orders-to-bronze-cdc** — the Copy job that ingests into `bronze_orders_cdc` (Challenge 2)
   - **nb_data_quality_gate** — the notebook that gates Bronze-to-Silver promotion (Challenge 4)
   - `usp_process_customer_changes` — the stored procedure inside `contoso_gold_wh` that applies SCD Type 2 changes (Challenge 3, Task 3, step 11)
5. In the workspace, open the pipeline item you created in Challenge 1 (**contoso-medallion-orchestration**) — this is the fifth Fabric item, and the one you build the orchestration into — rather than creating a new one.
   - If that item does not exist yet, select **+ New item**, search for **Data pipeline**, select it, and name the new pipeline **contoso-medallion-orchestration**.
6. On the pipeline canvas, go to the **Activities** ribbon and select the **Copy data** dropdown arrow. Select **Add copy job activity** from that menu — this references an existing Copy job item, unlike **Add copy data activity**, which would build a brand-new Copy Data activity with its own source/destination from scratch. Select **Use copy assistant** and **Add copy data activity** are both the wrong choice here.
7. Rename the first activity to **Bronze CDC ingestion**.
8. Select the activity, go to its **Settings** tab, and pick **orders-to-bronze-cdc** as the Copy job to invoke.
   - If **Connection** shows **Select...** with no results, select **Browse all**, then create a **new connection** representing this Fabric workspace (organizational account authentication) so the activity can find items in the same workspace. Confirm **Workspace** then shows your current workspace and **Copy job** shows `orders-to-bronze-cdc`.
9. Add a **Notebook** activity (visible directly on the ribbon) that runs your quality notebook.
10. Rename it to **Bronze to Silver quality gate**.
11. In the notebook activity's **Settings** tab, select **nb_data_quality_gate**, the notebook you created in Challenge 4.
12. There is no separate Lakehouse field on this activity's Settings tab — the Lakehouse context comes from whichever Lakehouse is pinned as default *inside the notebook itself*. Select **Open** next to the Notebook field to open `nb_data_quality_gate` directly, and confirm **contoso_medallion_lh** is pinned as its default Lakehouse in the notebook's own Explorer pane. Fix it there if it isn't, then return to the pipeline.
13. Back on the ribbon, add a **Script** activity for the downstream Gold processing (this is the activity type available in current Fabric versions; "Stored procedure" may not appear as a separate type).
14. Rename it to **Gold dimension load**.
15. Configure this activity's connection — this needs a **new** connection to `contoso_gold_wh`, not the one you already created for `Contoso_Operations` in Challenge 2 (they are different databases):
    - Select the activity's **Settings** tab, and for **Connection** select **Browse all** → create a **new connection** of type **SQL Server database**.
    - **Server**: the `contoso_gold_wh` SQL connection string — open `contoso_gold_wh` → **Settings** → **SQL endpoint** tab to get it (same place you recorded it in Challenge 1, Task 2). Do not reuse the `Contoso_Operations` server value.
    - **Authentication kind**: **Organizational account** (your signed-in Entra ID identity) — not Basic/SQL auth, since that's for the source database's SQL login, not the Warehouse.
    - If you see `An exception occurred: ... Authentication token is missing in the federated authentication message`, the sign-in step for Organizational account didn't complete — retry it and make sure any sign-in popup isn't blocked.
    - Once connected, set **Database** to **contoso_gold_wh** (not `Contoso_Operations`).
    - Set **Script type** to **NonQuery** (since `EXEC` returns no result set).
    - Click into the **Script** text box (dismiss the Dynamic content popup if it opens — you don't need it here) and enter:
      ```sql
      EXEC usp_process_customer_changes;
      ```
    - Before relying on this, verify the procedure actually exists — open `contoso_gold_wh`, run a new SQL query:
      ```sql
      SELECT SCHEMA_NAME(schema_id) AS SchemaName, name
      FROM sys.procedures
      WHERE name = 'usp_process_customer_changes';
      ```
      If this returns zero rows, the `CREATE PROCEDURE` statement from Challenge 3, Task 3, step 11 was never actually committed — rerun it now before continuing.
16. Connect **Bronze CDC ingestion** to **Bronze to Silver quality gate**: on the canvas, drag from the small **green checkmark** connector square on the right edge of the first activity onto the second activity's box. This draws the success dependency.
17. Connect **Bronze to Silver quality gate** to **Gold dimension load** the same way, using its green checkmark connector.
18. If your design includes a separate Silver promotion step outside the notebook, insert that activity between the notebook and the Gold load, and make both downstream activities dependent on a successful quality result. (Not needed here — Silver promotion already happens inside `nb_data_quality_gate`.)
19. Select **Validate** in the toolbar and resolve any remaining "invalid activity" errors it lists (commonly a missing Connection or missing Query/Script) before saving.
20. Select **Save**.

> [!Important]
> Microsoft Fabric pipelines, lakehouses, warehouses, and notebooks are Fabric control-plane items. In this lab, they are learner-created inside the workspace and are not discovered through Azure Resource Manager.

## Task 2: Configure dependencies, retry behavior, and failure handling

In this task, you will make the orchestration resilient to transient activity failures while ensuring that true data-quality failures block downstream processing.

1. Select the **Bronze to Silver quality gate** activity on the pipeline canvas.
2. In the properties pane, open the **General** tab.
3. Turn on **Enable retries**.
4. Set **Retry** to **1**.
5. Leave **Retry interval (sec)** at **30**.
6. If the retry settings in your Fabric environment expose **Retry conditions (preview)**, configure them only for transient failures that should be retried.
7. Do not configure retries in a way that masks known bad-data failures from the quality notebook — the notebook raises an explicit exception on a failed gate (Challenge 4, Task 2, step 10), and a retry against the same bad Bronze data will fail again for the same reason, which is the correct, expected behavior.
8. Return to the pipeline canvas and review the success dependency between the quality gate and the Gold load.
9. Confirm that **Gold dimension load** runs only when the quality gate succeeds.
10. Add a failure branch from **Bronze to Silver quality gate**. The canvas does **not** create a blank activity automatically when you drag a connector onto empty space — add the target activity first, then connect to it:
    - Go to the **Activities** ribbon and find **Fail** (check the **...** "more activities" button if it's not directly visible). Drag it onto an empty area of the canvas as its own box.
    - Now select **Bronze to Silver quality gate**, and drag from its **red X** connector square (on the right edge, alongside the green checkmark and blue arrow) directly onto the **Fail** activity box you just placed. This draws the "on Failure" dependency arrow.
11. Configure the failure-branch activity to record a clear failure outcome.
    - If you used **Fail**: select it, go to its **Settings** tab, and fill in **Fail message** with `Quality gate failed. Downstream Gold processing was blocked.` and any non-empty value for **Error code** (e.g. `QualityGateFailure`).
    - If **Fail** is not available in your environment, add a **Set variable** activity instead (same drag-and-connect method) to record the failure text — you'll need a pipeline-level **Variable** defined first (via the **Variables** tab at the pipeline level, not the activity level). Confirm the overall pipeline run still shows as **Failed** in Fabric monitoring — a **Set variable** activity alone succeeds, so pair it with the upstream failed activity to keep the run status accurate.
12. Rename the failure-path activity to **Quality failure evidence**.
13. Save the pipeline. Run **Validate** first if you want to confirm no configuration errors remain.
14. Select **View run history** or open the **Monitor** hub and verify that the pipeline is ready to expose per-activity status, inputs, outputs, and errors after execution. You don't need an actual run yet for this check — an empty run history is expected and fine at this point.

> [!Note]
> Microsoft Learn documents that Fabric pipeline activities expose **General** settings such as **Enable retries**, **Retry**, and **Retry interval (sec)**, and that run monitoring can be reviewed through **View run history** and the **Monitor** experience.

## Task 3: Run the success and failure paths and capture internal evidence

In this task, you will test the orchestration twice and collect the evidence required for the final validation.

1. Make sure your workspace is in the clean-data state that allows the quality notebook to pass — `bronze_orders_cdc` should not currently contain the `quality_defect.csv` rows from Challenge 4, Task 3.

   > [!Important]
   > Before your first run, open `nb_data_quality_gate` and remove any leftover **manual-testing cells** from Challenge 4, Task 3 — anything referencing `defect_df`, `quality_defect.csv`, `defect_null_counts`, `defect_results`, or `defect_overall_passed`. Those cells were only for interactive, one-off verification. When the pipeline's Notebook activity runs this notebook, it executes **every cell top-to-bottom in a fresh session** — none of your earlier manual-run variables carry over. If a later cell references a `defect_*` variable that an earlier cell in that same fresh run didn't define, you get `NameError: name 'defect_overall_passed' is not defined`, which fails even a run over clean Bronze data. Keep only the Challenge 4, Task 2 production cells (setup, the 5 checks, `overall_passed`, the `quality_gate_log` write, and the final conditional write/raise based on `overall_passed`/`results`). Use the notebook's search (find `defect_df`) to locate every leftover test cell and delete each one, then save.
2. On the pipeline canvas, select **Run**.
3. Wait for the pipeline run to finish.
4. Open **View run history** for the pipeline.
5. Select the completed run and review the activity list.
6. Confirm that:
   - **Bronze CDC ingestion** completed successfully.
   - **Bronze to Silver quality gate** completed successfully.
   - **Gold dimension load** completed successfully.

   If **Gold dimension load** fails with `Could not find stored procedure 'usp_process_customer_changes'`, the procedure from Challenge 3, Task 3, step 11 was never actually committed. Open `contoso_gold_wh`, run:
   ```sql
   SELECT SCHEMA_NAME(schema_id) AS SchemaName, name
   FROM sys.procedures
   WHERE name = 'usp_process_customer_changes';
   ```
   If this returns zero rows, recreate it with the `CREATE PROCEDURE` statement from Challenge 3, then re-run the pipeline.
7. Open the activity details for each of the three activities and review the available **Input**, **Output**, and status information for the successful run.
8. Run `SELECT COUNT(*) FROM dim_customer;` against `contoso_gold_wh` and confirm the count reflects the SCD Type 2 processing from `usp_process_customer_changes` (5,200 if this is the first time the procedure has run against unprocessed staging data, or unchanged if Challenge 3 already ran it against the same staging data — the procedure only updates or inserts rows whose staged values differ from the current dimension row, so re-running it here is safe and does not create duplicate versions).
9. On the lab VM, open PowerShell and save the success run evidence. Set each activity's `status` to the status you actually saw in the run history:

   ```powershell
   New-Item -ItemType Directory -Path 'C:\LabFiles\validation' -Force | Out-Null

   [ordered]@{
       pipelineName     = 'contoso-medallion-orchestration'
       pipelineRunStatus = 'Succeeded'
       activities = @(
           [ordered]@{ activityName = 'Bronze CDC ingestion';          status = 'Succeeded' }
           [ordered]@{ activityName = 'Bronze to Silver quality gate'; status = 'Succeeded' }
           [ordered]@{ activityName = 'Gold dimension load';           status = 'Succeeded' }
       )
   } | ConvertTo-Json -Depth 5 | Set-Content 'C:\LabFiles\validation\pipeline-success.json' -Encoding utf8

   Get-Content 'C:\LabFiles\validation\pipeline-success.json'
   ```

   > [!Important]
   > Create this file from a PowerShell window on the lab VM, not from a Fabric notebook. Notebooks run on remote Spark compute and cannot write to this VM's `C:\LabFiles` folder.

10. Reintroduce the controlled quality-defect scenario from Challenge 4 so the quality notebook fails during an automated pipeline run. In Challenge 4, Task 3 you tested the defect rows in separate, manually run cells — that proved the check logic works, but the pipeline's **Bronze to Silver quality gate** activity runs the whole notebook non-interactively, and the notebook's real gate logic (Challenge 4, Task 2) reads from `bronze_orders_cdc`, not from `quality_defect.csv` directly. To make the automated run fail for real, append the 10 defective rows into `bronze_orders_cdc` itself:
    - In **`nb_data_quality_gate`** (the same notebook, attached to `contoso_medallion_lh` — this cell needs that Lakehouse context to resolve the relative `Files/...` path and the `bronze_orders_cdc` table), add a new cell and run:

      ```python
      from pyspark.sql import functions as F

      # Cast every column to the Bronze table's own schema so the append cannot fail on a type mismatch.
      bronze_schema = spark.table("bronze_orders_cdc").schema

      defect_df = spark.read.option("header", True).csv("Files/quality_defect.csv") \
          .select(*[F.col(field.name).cast(field.dataType).alias(field.name) for field in bronze_schema])

      defect_df.write.format("delta").mode("append").saveAsTable("bronze_orders_cdc")
      ```

    - Run `SELECT COUNT(*) FROM bronze_orders_cdc WHERE OrderID IS NULL;` and confirm it returns **10**, proving the defect rows are now part of the live Bronze table that the pipeline will read.
    - This cell permanently modifies `bronze_orders_cdc` — it's a one-time manual step, not something the automated pipeline should run itself. After you've confirmed the failure run below, delete this cell from the notebook again (same cleanup approach as step 1's note) so a future pipeline run doesn't re-append more defect rows every time it executes.
11. Run the same pipeline again.
12. Open the new run in **View run history** or the **Monitor** hub.
13. Confirm that:
    - The quality gate activity failed, and the run history shows it was attempted twice (the retry configured in Task 2).
    - The failure path (**Quality failure evidence**) executed, or the run was clearly marked failed.
    - The downstream **Gold dimension load** activity did not complete successfully.
14. Review the failed run details and record the activity status, error text, and branch behavior for the quality gate activity.
15. In PowerShell on the lab VM, save the failure run evidence. The **Gold dimension load** entry must show a non-success status, because a blocked quality gate must stop downstream Gold processing:

    ```powershell
    [ordered]@{
        pipelineName      = 'contoso-medallion-orchestration'
        pipelineRunStatus = 'Failed'
        activities = @(
            [ordered]@{ activityName = 'Bronze CDC ingestion';          status = 'Succeeded' }
            [ordered]@{ activityName = 'Bronze to Silver quality gate'; status = 'Failed' }
            [ordered]@{ activityName = 'Gold dimension load';           status = 'Skipped' }
        )
    } | ConvertTo-Json -Depth 5 | Set-Content 'C:\LabFiles\validation\pipeline-failure.json' -Encoding utf8

    Get-Content 'C:\LabFiles\validation\pipeline-failure.json'
    ```

16. Upload both evidence files, reusing the **same** validation storage account created in Challenge 2, Task 6. Since `C:\LabFiles\.env` does not exist in this environment, this script finds the storage account by its `stfabricval*` naming prefix instead of reading it from a file:

    ```powershell
    $ErrorActionPreference = 'Stop'

    $resourceGroup  = 'labvmrg'      # same resource group you used in previous challenges
    $containerName  = 'validation'

    if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }

    $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroup |
        Where-Object { $_.StorageAccountName -like 'stfabricval*' } |
        Select-Object -First 1

    if (-not $storageAccount) {
        throw "Could not find a storage account matching 'stfabricval*' in resource group '$resourceGroup'. Hardcode the exact name instead: `$storageAccount = Get-AzStorageAccount -ResourceGroupName '$resourceGroup' -Name '<exact-name>'"
    }

    $ctx = $storageAccount.Context

    @('pipeline-success.json', 'pipeline-failure.json') | ForEach-Object {
        Set-AzStorageBlobContent -Context $ctx -Container $containerName `
            -File (Join-Path 'C:\LabFiles\validation' $_) -Blob $_ -Force | Out-Null
    }

    Get-AzStorageBlob -Context $ctx -Container $containerName | Select-Object Name
    ```
    Adjust `$resourceGroup` if it doesn't match your environment.

17. Confirm both files appear in the output from the script above, alongside `cdc-ingestion.json`, `scd-type2.json`, `quality-gate.json`, and the three `silver-recovery-*.json` files from the earlier challenges.
18. Record the deployment context in your notes: **Deployment ID: <inject key="DeploymentID" enableCopy="false"/>**.

<validation step="Validate orchestration success/failure run states and dependency behavior using internal pipeline evidence."/>

## Summary

In this challenge, you built a Fabric pipeline that orchestrates the Bronze, Silver, and Gold flow by reusing the items you created earlier in the lab. You configured activity sequencing, added retry-aware handling for the quality gate, blocked downstream processing when validation failed, and proved both success and failure behavior by reviewing native Fabric run-state evidence and saving the required validation artifacts.
