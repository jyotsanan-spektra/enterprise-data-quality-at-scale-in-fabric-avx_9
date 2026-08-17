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
6. In the workspace item list, select the Lakehouse that you created for the Bronze and Silver layers in Challenge 1 (**contoso_medallion_lh**).
7. In the Lakehouse explorer, expand **Tables** and confirm whether `bronze_orders_cdc` already exists.
   - If the table does not exist yet, that is expected. The first Copy job run will create and populate it.
   - If the table already exists because you partially configured this challenge earlier, keep using the same table and do not create a second destination table.
8. Open `C:\LabFiles\fabric-item-names.txt` from Challenge 1 and confirm the workspace and Lakehouse names listed there match what is on screen. If the file does not exist yet, create it now and add the workspace and Lakehouse names.

> [!Important]
> Microsoft Fabric workspaces, Lakehouses, and Copy jobs are control-plane items. In this lab, those items are learner-created or learner-confirmed inside Fabric. Do not assume they were provisioned by Azure Resource Manager.

## Task 2: Create and configure the Copy job for CDC-based ingestion
In this task, you will create or complete the Copy job that reads from the SQL source and writes to the Bronze table.

1. Return to your Fabric workspace.
2. Select **+ New item**.
3. Search for **Copy job**, select it, enter **orders-to-bronze-cdc** as the name, and then select **Create**.
   - If you already created a Copy job for this challenge, open that existing job instead of creating another one.
4. On the **Choose data source** page, select the SQL source connection that exposes the `Contoso_Operations` database. The connection name typically references `Contoso_Operations` or `Contoso` directly — if more than one connection is listed, confirm the correct one with your environment's connection details pane before continuing.
5. When the source objects are displayed, select the `Orders` table.
6. Continue to the destination step and select your existing Lakehouse (**contoso_medallion_lh**) from Challenge 1.
7. When prompted for the destination object, map the source table to the Lakehouse **Tables** area and set the destination table name to `bronze_orders_cdc`.
8. Open the copy settings step.
9. Set the copy mode to **Incremental copy**.
10. In the incremental copy settings, locate the change-tracking method field and confirm it shows a CDC-based tracking method (for example, **Change Data Capture** or **Native CDC**) rather than a watermark or last-modified-column method. The source tables are CDC-enabled, so a watermark-based method here means the wrong tracking mode was selected — go back and reselect the CDC option before continuing.
11. Review the table mapping and confirm the source still reads `Orders` and the destination still reads `bronze_orders_cdc`.
12. Confirm the destination is still pointed at the same Lakehouse and table name you verified in Task 1.
13. On the summary page, confirm three specific fields: the copy mode reads **Incremental (CDC)** or an equivalent CDC-aware incremental label, the source reads `Contoso_Operations.Orders`, and the destination table name reads exactly `bronze_orders_cdc`.
14. Select **Save + Run**.

> [!Note]
> In Microsoft Fabric Copy job, incremental copy performs an initial full load on the first successful run. For CDC-enabled database sources, later runs capture inserted and updated changes since the previous successful run.

## Task 3: Run the baseline load and verify `bronze_orders_cdc`
In this task, you will monitor the first run and confirm that the Bronze table contains the initial dataset.

1. Stay in the Copy job panel after selecting **Save + Run**.
2. Watch the run status until it reaches **Succeeded**.
3. Review the job metrics and note the values for **Rows read** and **Rows written**. Both should read approximately **100,000**, matching the full-load row count from the prepared `Orders` source.
4. If needed, select **View run history** or open **Monitor** from the left navigation pane to inspect the job details.
5. Confirm that the run shows a successful initial load into the Lakehouse destination.
6. Return to your Lakehouse.
7. Open the table `bronze_orders_cdc` from the **Tables** list.
8. Review the table preview and confirm the columns match the 12-column Orders schema (OrderID, CustomerID, OrderDate, ShipDate, OrderStatus, ProductID, Quantity, UnitPrice, Discount, Revenue, ShippingCountry, PaymentMethod).
9. Run a row-count check — either from the Lakehouse SQL analytics endpoint (`SELECT COUNT(*) FROM bronze_orders_cdc;`) or from a notebook cell (`spark.table("bronze_orders_cdc").count()`) — and confirm the result is approximately 100,000.
10. Append the following details to `fabric-item-names.txt` or a separate notes file: Copy job status, destination table name `bronze_orders_cdc`, rows read and rows written for the first run, and the row count from step 9.
11. Leave the Copy job and Lakehouse available because you will reuse the same objects in the next task.

## Task 4: Process the prepared changes and prove incremental behavior
In this task, you will rerun the same job after the prepared source delta is available and confirm that only changes are processed.

1. Apply or trigger the prepared source-side update set for `Contoso_Operations.Orders` that is provided in the lab environment. This update set introduces approximately 500 changed or new order rows. Check your lab's Getting Started guide or the `C:\LabFiles` folder on the VM for the exact script or tool name provided in this deployment.
   - Do not create a new source table or a second destination table.
2. Return to the existing Copy job `orders-to-bronze-cdc`.
3. Select **Run** to execute the same Copy job again.
4. Monitor the run until it reaches **Succeeded**.
5. Open the run details and compare the second run's metrics to the baseline run from Task 3.
6. Compare **Rows written** between the two runs: the second run's Rows written should be close to **500** — the number of changed rows in the prepared update set — not close to the full baseline count of 100,000. If the second run's Rows written is close to 100,000, the job re-ran a full load instead of an incremental one; revisit the copy mode and CDC tracking settings from Task 2 before continuing.
7. Record the updated **Rows read** and **Rows written** values from the second run.
8. Return to the Lakehouse and reopen `bronze_orders_cdc`.
9. Run `SELECT COUNT(*) FROM bronze_orders_cdc;` again and confirm the new total is approximately 100,500 — the original ~100,000 rows plus the ~500 incremental rows.
10. Compare the first-run evidence and second-run evidence in your notes. Your proof should show that the baseline run established the initial snapshot of ~100,000 rows and the second run added only the ~500 changed rows captured after the first successful run.
11. Keep your evidence available for validation, including the two run outcomes and the post-run table state.

<validation step="CDC ingestion outcomes"/>
<question>

## Summary
In this challenge, you configured a Microsoft Fabric Copy job to ingest `Contoso_Operations.Orders` into the Bronze Lakehouse table `bronze_orders_cdc`. You ran the initial load, monitored the Copy job metrics, and then reran the same ingestion path after prepared source changes were available to demonstrate CDC-driven incremental behavior in the Bronze layer.
