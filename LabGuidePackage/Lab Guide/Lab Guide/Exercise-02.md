# Challenge 2: Implement CDC ingestion into the Bronze layer

### Estimated Duration: 40 Minutes

## Scenario
In the previous challenge, you confirmed the Microsoft Fabric workspace and medallion-aligned items that will support the rest of the lab. In this challenge, you will configure a Copy job that ingests order data from the `Contoso_Operations` SQL source into the Bronze Lakehouse table `bronze_orders_cdc`. You will first establish the baseline load, then rerun the same design after the prepared source changes are available so you can prove the ingestion pattern captures only incremental changes.

## Overview
In this challenge, you will open the same Fabric workspace and Lakehouse you prepared earlier, create or complete a Copy job, map the `Orders` source into `bronze_orders_cdc`, select incremental copy with CDC behavior, run the first load, and then monitor a second run to verify change capture. You will also record run evidence such as status, rows read, rows written, and the destination table state.

## Objectives
- Task 1: Open the Fabric workspace and confirm the Bronze destination
- Task 2: Create and configure the Copy job for CDC-based ingestion
- Task 3: Run the baseline load and verify `bronze_orders_cdc`
- Task 4: Process the prepared changes and prove incremental behavior

## Task 1: Open the Fabric workspace and confirm the Bronze destination
In this task, you will return to the Fabric items you prepared in the previous challenge and confirm the destination that will receive the CDC data.

1. Open a browser and go to the Microsoft Fabric portal at <https://app.fabric.microsoft.com>.
2. Sign in with the lab credentials:
   - Username: <inject key="AzureAdUserEmail"></inject>
   - Password: <inject key="AzureAdUserPassword"></inject>
3. If prompted to choose an experience, stay in Microsoft Fabric.
4. Open the workspace that you created or confirmed in Challenge 1.
5. Verify that you are working in the same lab context tied to deployment **<inject key="DeploymentID" enableCopy="false"></inject>**.
6. In the workspace item list, select the Lakehouse that you created for the Bronze and Silver layers in Challenge 1.
7. In the Lakehouse explorer, review the **Tables** area and confirm whether `bronze_orders_cdc` already exists.
   - If the table does not exist yet, that is expected. The first Copy job run will create and populate it.
   - If the table already exists because you partially configured this challenge earlier, keep using the same table and do not create a second destination table.
8. Record the names of the workspace and Lakehouse that you will use for the rest of this challenge.

> [!Important]
> Microsoft Fabric workspaces, Lakehouses, and Copy jobs are control-plane items. In this lab, those items are learner-created or learner-confirmed inside Fabric. Do not assume they were provisioned by Azure Resource Manager.

## Task 2: Create and configure the Copy job for CDC-based ingestion
In this task, you will create or complete the Copy job that reads from the SQL source and writes to the Bronze table.

1. Return to your Fabric workspace.
2. Select **+ New item**.
3. Search for **Copy job**, select it, enter a meaningful name such as `orders-to-bronze-cdc`, and then select **Create**.
   - If you already created a Copy job for this challenge, open that existing job instead of creating another one.
4. On the **Choose data source** page, select the SQL source connection that exposes the `Contoso_Operations` database.
5. When the source objects are displayed, select the `Orders` table.
6. Continue to the destination step and select your existing Lakehouse from Challenge 1.
7. When prompted for the destination object, map the source table to the Lakehouse **Tables** area and set the destination table name to `bronze_orders_cdc`.
8. Open the copy settings step.
9. Set the copy mode to **Incremental copy**.
10. Because this lab uses a CDC-enabled source, confirm that the Copy job is configured to use CDC behavior for subsequent runs rather than a repeated full copy.
11. Review the table mapping and ensure the source remains `Orders` and the destination remains `bronze_orders_cdc`.
12. Leave the destination pointed to the same Lakehouse and same table name that you verified in Task 1.
13. Review the summary page carefully and confirm the configuration supports this pattern:
    - first run creates the baseline snapshot
    - later runs apply only captured source changes
14. Select **Save + Run**.

> [!Note]
> In Microsoft Fabric Copy job, incremental copy performs an initial full load on the first successful run. For CDC-enabled database sources, later runs capture inserted and updated changes since the previous successful run.

## Task 3: Run the baseline load and verify `bronze_orders_cdc`
In this task, you will monitor the first run and confirm that the Bronze table contains the initial dataset.

1. Stay in the Copy job panel after selecting **Save + Run**.
2. Watch the run status until it reaches **Succeeded**.
3. Review the job metrics and note the values for **Rows read** and **Rows written**.
4. If needed, select **View run history** or open **Monitor** from the left navigation pane to inspect the job details.
5. Confirm that the run shows a successful initial load into the Lakehouse destination.
6. Return to your Lakehouse.
7. Open the table `bronze_orders_cdc` from the **Tables** list.
8. Review the table preview and confirm that order data has been written to the Bronze layer.
9. Record baseline evidence for validation. Capture at least the following details in your notes:
   - Copy job status
   - destination table name `bronze_orders_cdc`
   - rows read and rows written for the first run
   - visible evidence that the table now contains data
10. Leave the Copy job and Lakehouse available because you will reuse the same objects in the next task.

## Task 4: Process the prepared changes and prove incremental behavior
In this task, you will rerun the same job after the prepared source delta is available and confirm that only changes are processed.

1. Apply or trigger the prepared source-side update set for `Contoso_Operations.Orders` that is provided in the lab environment.
   - Use the lab-provided method for generating the change set if your instructor notes or environment instructions expose one.
   - Do not create a new source table or a second destination table.
2. Return to the existing Copy job `orders-to-bronze-cdc` or the equivalent name you used.
3. Select **Run** to execute the same Copy job again.
4. Monitor the run until it reaches **Succeeded**.
5. Open the run details and compare the second run to the baseline run.
6. Confirm that the second run reflects incremental behavior against the existing `bronze_orders_cdc` table instead of rebuilding the entire destination from scratch.
7. Review the run metrics again and record the updated **Rows read** and **Rows written** values.
8. Return to the Lakehouse and reopen `bronze_orders_cdc`.
9. Verify that the table now reflects the prepared source changes.
10. Compare the first-run evidence and second-run evidence. Your proof should show that:
    - the baseline run established the initial snapshot
    - the later run processed only the changes captured after the first successful run
11. Keep your evidence available for validation, including the two run outcomes and the post-run table state.

<validation step="CDC ingestion outcomes"/>
<question>

## Summary
In this challenge, you configured a Microsoft Fabric Copy job to ingest `Contoso_Operations.Orders` into the Bronze Lakehouse table `bronze_orders_cdc`. You ran the initial load, monitored the Copy job metrics, and then reran the same ingestion path after prepared source changes were available to demonstrate CDC-driven incremental behavior in the Bronze layer.
