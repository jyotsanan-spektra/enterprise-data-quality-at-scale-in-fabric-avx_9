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
6. On the pipeline canvas, add the first activity that represents the Bronze ingestion step. Add the activity type that invokes an existing Copy job item — depending on your Fabric version this appears either as a native **Copy job** activity or as an activity that references an existing item by name. Configure it to run the **orders-to-bronze-cdc** Copy job you created in Challenge 2, rather than rebuilding a new Copy data activity from scratch.
7. Rename the first activity to **Bronze CDC ingestion**.
8. Add a **Notebook** activity that runs your quality notebook.
9. Rename it to **Bronze to Silver quality gate**.
10. In the notebook activity settings, select **nb_data_quality_gate**, the notebook you created in Challenge 4.
11. Confirm the notebook activity's Lakehouse context points to **contoso_medallion_lh** — the same Lakehouse you used earlier in the lab.
12. Add a **Script** or **Stored procedure** activity for the downstream Gold processing.
13. Rename it to **Gold dimension load**.
14. Configure this activity's connection to point at **contoso_gold_wh** (using the SQL connection string you saved in Challenge 1, Task 2), and set its query or stored procedure call to:

    ```sql
    EXEC usp_process_customer_changes;
    ```

15. Connect **Bronze CDC ingestion** to **Bronze to Silver quality gate** by dragging the green success dependency from the first activity to the second.
16. Connect **Bronze to Silver quality gate** to **Gold dimension load** with a success dependency.
17. If your design includes a separate Silver promotion step outside the notebook, insert that activity between the notebook and the Gold load, and make both downstream activities dependent on a successful quality result.
18. Select **Save**.

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
10. Add a failure branch from **Bronze to Silver quality gate**.
11. For the failure branch, add a control-flow activity that records a clear failure outcome.
    - If **Fail** is available in your activity list, use it and enter a meaningful error message such as `Quality gate failed. Downstream Gold processing was blocked.`
    - If **Fail** is not available in your environment, add a **Set variable** activity instead to record the failure text, but confirm the overall pipeline run still shows as **Failed** in Fabric monitoring — a **Set variable** activity alone succeeds, so pair it with the upstream failed activity to keep the run status accurate.
12. Rename the failure-path activity to **Quality failure evidence**.
13. Save the pipeline.
14. Select **View run history** or open the **Monitor** hub and verify that the pipeline is ready to expose per-activity status, inputs, outputs, and errors after execution.

> [!Note]
> Microsoft Learn documents that Fabric pipeline activities expose **General** settings such as **Enable retries**, **Retry**, and **Retry interval (sec)**, and that run monitoring can be reviewed through **View run history** and the **Monitor** experience.

## Task 3: Run the success and failure paths and capture internal evidence

In this task, you will test the orchestration twice and collect the evidence required for the final validation.

1. Make sure your workspace is in the clean-data state that allows the quality notebook to pass — `bronze_orders_cdc` should not currently contain the `quality_defect.csv` rows from Challenge 4, Task 3.
2. On the pipeline canvas, select **Run**.
3. Wait for the pipeline run to finish.
4. Open **View run history** for the pipeline.
5. Select the completed run and review the activity list.
6. Confirm that:
   - **Bronze CDC ingestion** completed successfully.
   - **Bronze to Silver quality gate** completed successfully.
   - **Gold dimension load** completed successfully.
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
    - In the notebook, add a new cell and run:

      ```python
      from pyspark.sql import functions as F

      # Cast every column to the Bronze table's own schema so the append cannot fail on a type mismatch.
      bronze_schema = spark.table("bronze_orders_cdc").schema

      defect_df = spark.read.option("header", True).csv("Files/quality_defect.csv") \
          .select(*[F.col(field.name).cast(field.dataType).alias(field.name) for field in bronze_schema])

      defect_df.write.format("delta").mode("append").saveAsTable("bronze_orders_cdc")
      ```

    - Run `SELECT COUNT(*) FROM bronze_orders_cdc WHERE OrderID IS NULL;` and confirm it returns **10**, proving the defect rows are now part of the live Bronze table that the pipeline will read.
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

16. Upload both evidence files to the **validation** container:

    ```powershell
    $envMap = @{}
    Get-Content 'C:\LabFiles\.env' | ForEach-Object {
        if ($_ -match '^(?<k>[A-Z0-9_]+)=(?<v>.*)$') { $envMap[$Matches.k] = $Matches.v }
    }

    if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }

    $resourceGroup = "rg-fabricdataquality-$($envMap['DEPLOYMENT_ID'])"
    $ctx = (Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $envMap['VALIDATION_STORAGE_ACCOUNT']).Context

    @('pipeline-success.json', 'pipeline-failure.json') | ForEach-Object {
        Set-AzStorageBlobContent -Context $ctx -Container 'validation' `
            -File (Join-Path 'C:\LabFiles\validation' $_) -Blob $_ -Force | Out-Null
    }
    ```

17. Confirm both files uploaded by running `Get-AzStorageBlob -Context $ctx -Container 'validation' | Select-Object Name` and checking that both filenames appear in the output, alongside the evidence files from the earlier challenges.
18. Record the deployment context in your notes: **Deployment ID: <inject key="DeploymentID" enableCopy="false"/>**.

<validation step="Validate orchestration success/failure run states and dependency behavior using internal pipeline evidence."/>

## Summary

In this challenge, you built a Fabric pipeline that orchestrates the Bronze, Silver, and Gold flow by reusing the items you created earlier in the lab. You configured activity sequencing, added retry-aware handling for the quality gate, blocked downstream processing when validation failed, and proved both success and failure behavior by reviewing native Fabric run-state evidence and saving the required validation artifacts.
