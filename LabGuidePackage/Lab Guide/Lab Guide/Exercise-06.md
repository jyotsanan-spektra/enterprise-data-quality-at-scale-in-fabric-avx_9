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
4. Confirm the following learner-created items are available in the workspace before you build the orchestration:
   - The Lakehouse that contains the Bronze and Silver tables.
   - The Warehouse that contains the Gold dimension objects.
   - The CDC ingestion asset or copy process you configured for `bronze_orders_cdc`.
   - The PySpark notebook that performs the Bronze-to-Silver quality gate.
   - The Gold load process you used for the customer dimension history load.
5. In the workspace, select **+ New item**.
6. Search for **Data pipeline**, select it, and create a new pipeline.
7. Name the pipeline **contoso-medallion-orchestration**.
8. On the pipeline canvas, add the first activity that represents the Bronze ingestion step.
   - If you are using a pipeline activity, add **Copy data**.
   - If your earlier ingestion implementation is encapsulated in another reusable item, add the activity type that executes that item and point it to the ingestion logic you created in Challenge 2.
9. Rename the first activity to **Bronze CDC ingestion**.
10. Add the activity that runs your quality notebook.
11. Rename it to **Bronze to Silver quality gate**.
12. In the notebook activity settings, select the notebook you created in Challenge 4.
13. If your notebook requires a Lakehouse context, make sure it points to the same Lakehouse you used earlier in the lab.
14. Add the activity that performs the downstream Gold processing.
15. Rename it to **Gold dimension load**.
16. Configure that activity to use the Warehouse-related load process you completed in Challenge 3.
17. Connect **Bronze CDC ingestion** to **Bronze to Silver quality gate** by dragging the green success dependency from the first activity to the second.
18. Connect **Bronze to Silver quality gate** to **Gold dimension load** with a success dependency.
19. If your design includes a separate Silver promotion step outside the notebook, insert that activity between the notebook and the Gold load, and make both downstream activities dependent on a successful quality result.
20. Select **Save**.

> [!Important]
> Microsoft Fabric pipelines, lakehouses, warehouses, and notebooks are Fabric control-plane items. In this lab, they are learner-created inside the workspace and are not discovered through Azure Resource Manager.

## Task 2: Configure dependencies, retry behavior, and failure handling

In this task, you will make the orchestration resilient to transient activity failures while ensuring that true data-quality failures block downstream processing.

1. Select the **Bronze to Silver quality gate** activity on the pipeline canvas.
2. In the properties pane, open the **General** tab.
3. Turn on **Enable retries**.
4. Set **Retry** to **1**.
5. Leave **Retry interval (sec)** at **30** unless your instructor specifies a different value.
6. If the retry settings in your Fabric environment expose **Retry conditions (preview)**, configure them only for transient failures that should be retried.
7. Do not configure retries in a way that masks known bad-data failures from the quality notebook.
8. Return to the pipeline canvas and review the success dependency between the quality gate and the Gold load.
9. Confirm that **Gold dimension load** runs only when the quality gate succeeds.
10. Add a failure branch from **Bronze to Silver quality gate**.
11. For the failure branch, add a control-flow activity that records a clear failure outcome.
   - If **Fail** is available in your activity list, use it and enter a meaningful error message such as `Quality gate failed. Downstream Gold processing was blocked.`
   - If your workspace uses another approved evidence step, use that step to capture the failure path while still leaving the run visibly failed in Fabric monitoring.
12. Rename the failure-path activity to **Quality failure evidence**.
13. Save the pipeline.
14. Select **View run history** or open the **Monitor** hub and verify that the pipeline is ready to expose per-activity status, inputs, outputs, and errors after execution.

> [!Note]
> Microsoft Learn documents that Fabric pipeline activities expose **General** settings such as **Enable retries**, **Retry**, and **Retry interval (sec)**, and that run monitoring can be reviewed through **View run history** and the **Monitor** experience.

## Task 3: Run the success and failure paths and capture internal evidence

In this task, you will test the orchestration twice and collect the evidence required for the final validation.

1. Make sure your workspace is in the clean-data state that allows the quality notebook to pass.
2. On the pipeline canvas, select **Run**.
3. Wait for the pipeline run to finish.
4. Open **View run history** for the pipeline.
5. Select the completed run and review the activity list.
6. Confirm that:
   - **Bronze CDC ingestion** completed successfully.
   - **Bronze to Silver quality gate** completed successfully.
   - **Gold dimension load** completed successfully.
7. Open the activity details and review the available **Input**, **Output**, and status information for the successful run.
8. Capture the successful run evidence you need for validation.
9. Export or save the success evidence as a JSON file named **pipeline-success.json**.
10. Now reintroduce the controlled quality-defect scenario that you used earlier in the lab so the quality notebook fails.
11. Run the same pipeline again.
12. Open the new run in **View run history** or the **Monitor** hub.
13. Confirm that:
   - The quality gate activity failed.
   - The failure path executed or the run was clearly marked failed.
   - The downstream Gold activity did not complete successfully.
14. Review the failed run details and capture the activity status, error text, and branch behavior.
15. Export or save the failure evidence as a JSON file named **pipeline-failure.json**.
16. Using the lab VM or the lab-provided tooling, upload both evidence files to the **validation** container in the validation storage account associated with your deployment.
17. Record the deployment context in your notes: **Deployment ID: <inject key="DeploymentID" enableCopy="false"/>**.
18. Recheck that both files are present before you continue.

<validation step="Validate orchestration success/failure run states and dependency behavior using internal pipeline evidence."/>

## Summary

In this challenge, you built a Fabric pipeline that orchestrates the Bronze, Silver, and Gold flow by reusing the items you created earlier in the lab. You configured activity sequencing, added retry-aware handling for the quality gate, blocked downstream processing when validation failed, and proved both success and failure behavior by reviewing native Fabric run-state evidence and saving the required validation artifacts.
