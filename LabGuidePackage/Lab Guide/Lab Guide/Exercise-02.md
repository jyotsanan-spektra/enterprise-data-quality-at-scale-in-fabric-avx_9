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
- Task 5: Upload your CDC evidence for validation

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
2. Open the **orders-to-bronze-cdc** Copy job you created in Challenge 1 rather than creating a new one.
   - If that item does not exist yet, select **+ New item**, search for **Copy job**, select it, enter **orders-to-bronze-cdc** as the name, and then select **Create**.
3. On the **Choose data source** page, select the SQL source connection that exposes the `Contoso_Operations` database. The connection name typically references `Contoso_Operations` or `Contoso` directly — if more than one connection is listed, confirm the correct one with your environment's connection details pane before continuing.
4. When the source objects are displayed, select the `Orders` table.
5. Continue to the destination step and select your existing Lakehouse (**contoso_medallion_lh**) from Challenge 1.
6. When prompted for the destination object, map the source table to the Lakehouse **Tables** area and set the destination table name to `bronze_orders_cdc`.
7. Open the copy settings step.
8. Set the copy mode to **Incremental copy**.
9. In the incremental copy settings, locate the change-tracking method field and confirm it shows a CDC-based tracking method (for example, **Change Data Capture** or **Native CDC**) rather than a watermark or last-modified-column method. The source tables are CDC-enabled, so a watermark-based method here means the wrong tracking mode was selected — go back and reselect the CDC option before continuing.
10. Review the table mapping and confirm the source still reads `Orders` and the destination still reads `bronze_orders_cdc`.
11. Confirm the destination is still pointed at the same Lakehouse and table name you verified in Task 1.
12. On the summary page, confirm three specific fields: the copy mode reads **Incremental (CDC)** or an equivalent CDC-aware incremental label, the source reads `Contoso_Operations.Orders`, and the destination table name reads exactly `bronze_orders_cdc`.
13. Select **Save + Run**.

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

1. Apply the prepared source-side update set for `Contoso_Operations.Orders`. On the lab VM, open a PowerShell window and run:

   ```powershell
   & 'C:\LabFiles\FabricChallengeLab\Scripts\Apply-OrderChanges.ps1'
   ```

   This inserts approximately 350 new order rows and updates approximately 150 existing rows, for a change set of about 500 rows. Run it only once, and only after the baseline Copy job run in Task 3 has already succeeded.
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

## Task 5: Upload your CDC evidence for validation

In this task, you will record the numbers you just observed in Fabric into an evidence file and upload it, so the lab's automated validation can confirm your work.

> [!Important]
> Run every command in this task from a **PowerShell window on the lab VM**, not from a Fabric notebook cell. Fabric notebooks execute on remote Spark compute and cannot write to this VM's `C:\LabFiles` folder. You are typing in the values you read off the Fabric screens.

1. On the lab VM, open PowerShell.
2. Fill in the four values below with the numbers you recorded in Tasks 3 and 4, then run the block to create the evidence file:

   ```powershell
   $evidence = [ordered]@{
       tableName               = 'bronze_orders_cdc'
       copyMode                = 'Incremental (CDC)'
       baselineRowCount        = 100000   # Task 3: row count after the first run
       postIncrementalRowCount = 100500   # Task 4, step 9: row count after the second run
       incrementalRowsWritten  = 500      # Task 4, step 6: Rows written on the second run
   }

   New-Item -ItemType Directory -Path 'C:\LabFiles\validation' -Force | Out-Null
   $evidence | ConvertTo-Json | Set-Content -Path 'C:\LabFiles\validation\cdc-ingestion.json' -Encoding utf8
   Get-Content 'C:\LabFiles\validation\cdc-ingestion.json'
   ```

3. Upload the evidence file to the validation storage account. The account name and resource group are derived from your deployment ID, and the script reads them from the environment file the lab created for you:

   ```powershell
   $envMap = @{}
   Get-Content 'C:\LabFiles\.env' | ForEach-Object {
       if ($_ -match '^(?<k>[A-Z0-9_]+)=(?<v>.*)$') { $envMap[$Matches.k] = $Matches.v }
   }

   Connect-AzAccount -Identity -ErrorAction SilentlyContinue | Out-Null
   if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }

   $storageAccountName = $envMap['VALIDATION_STORAGE_ACCOUNT']
   $resourceGroup      = "rg-fabricdataquality-$($envMap['DEPLOYMENT_ID'])"
   $ctx = (Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName).Context

   Set-AzStorageBlobContent -Context $ctx -Container 'validation' `
       -File 'C:\LabFiles\validation\cdc-ingestion.json' -Blob 'cdc-ingestion.json' -Force | Out-Null

   Get-AzStorageBlob -Context $ctx -Container 'validation' | Select-Object Name
   ```

4. Confirm that `cdc-ingestion.json` appears in the output of the final command.

> [!Note]
> You will reuse this same upload pattern in Challenges 3, 4, 5, and 6. Only the local file name and blob name change each time.

<validation step="CDC ingestion outcomes"/>

## Summary
In this challenge, you configured a Microsoft Fabric Copy job to ingest `Contoso_Operations.Orders` into the Bronze Lakehouse table `bronze_orders_cdc`. You ran the initial load, monitored the Copy job metrics, and then reran the same ingestion path after prepared source changes were available to demonstrate CDC-driven incremental behavior in the Bronze layer.
