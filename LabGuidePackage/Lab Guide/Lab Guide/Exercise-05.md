# Challenge 5 - Audit, recover, and protect data with Delta Lake time travel

### Estimated Duration: 40 Minutes

## Scenario

A simulated corruption event has affected the `silver_orders` Delta table in your Microsoft Fabric medallion environment. Before you move on to full orchestration, you must investigate the table history, prove which version still contains the correct business data, restore the table to that verified state, and create a backup clone that the team can use for short-lived recovery readiness.

## Overview

In this challenge, you will use a Fabric notebook to inspect Delta Lake history for `silver_orders`, compare current data with a previous snapshot by using time travel, restore the live table to the correct version, and create a shallow clone backup table. You will also upload the required recovery evidence files so the lab validation can confirm your work.

## Objectives

- Task 1: Review Delta history and identify the last known good Silver version
- Task 2: Restore `silver_orders` and capture recovery evidence
- Task 3: Create a backup clone and upload the final validation files

## Task 1: Review Delta history and identify the last known good Silver version

In this task, you will use Delta history and read-only time travel to determine which version of `silver_orders` should be restored.

1. Sign in to Microsoft Fabric with the lab credentials.
   - Username: <inject key="AzureAdUserEmail"></inject>
   - Password: <inject key="AzureAdUserPassword"></inject>
2. Confirm that you are working in the lab environment associated with **Deployment ID: <inject key="DeploymentID" enableCopy="false"/>**.
3. Open the Fabric workspace you used in the previous challenges, and then open the Lakehouse that contains the `silver_orders` table.
4. From the Lakehouse, open a notebook that is attached to the same Lakehouse. If you do not already have a notebook for Silver-layer operations, create a new notebook named `silver_recovery_investigation`.
5. Add a new code cell and run the following PySpark statements to inspect the current table and its Delta history:

   ```python
   from delta.tables import DeltaTable

   table_name = "silver_orders"
   delta_table = DeltaTable.forName(spark, table_name)

   current_df = spark.table(table_name)
   print("Current row count:", current_df.count())
   display(current_df.limit(20))
   display(delta_table.history())
   ```

6. In the history output, identify the most recent write operations and locate the version that appears to represent the simulated corruption event. Record the following values from the history grid in your working notes:
   - the corrupted version number
   - the last known good version number immediately before the corruption
   - the timestamp of both events
7. Add a second code cell and compare the current data with the earlier snapshot by using Delta time travel. Replace `GOOD_VERSION` with the version number you identified in the previous step.

   ```python
   good_version = GOOD_VERSION

   historical_df = spark.read.format("delta").option("versionAsOf", good_version).table("silver_orders")

   print("Historical row count:", historical_df.count())
   display(historical_df.limit(20))
   ```

8. Compare the current results with the historical snapshot. Confirm that the historical snapshot removes the corruption symptoms you observed in the live table.
9. Add a third code cell and save your history investigation evidence to a JSON file on the lab VM. Update the version numbers before you run it.

   ```python
   import json
   import os

   history_evidence = {
       "tableName": "silver_orders",
       "corruptedVersion": CORRUPTED_VERSION,
       "lastKnownGoodVersion": GOOD_VERSION
   }

   output_path = r"C:\LabFiles\validation\silver-recovery-history.json"
   os.makedirs(os.path.dirname(output_path), exist_ok=True)

   with open(output_path, "w", encoding="utf-8") as f:
       json.dump(history_evidence, f, indent=2)

   print(f"Saved {output_path}")
   ```

> [!Important]
> Delta Lake time travel is read-only. Use it to verify the historical snapshot before you run a restore.

> [!Tip]
> Microsoft Learn recommends running `DESCRIBE HISTORY` or the DeltaTable history method before choosing a restore target. This reduces the chance of restoring the wrong version.

## Task 2: Restore `silver_orders` and capture recovery evidence

In this task, you will restore the Silver table to the correct version and verify that the current business state is healthy again.

1. In the same notebook, add a new code cell and restore the table to the last known good version. Replace `GOOD_VERSION` with the version you validated in Task 1.

   ```python
   from delta.tables import DeltaTable

   table_name = "silver_orders"
   good_version = GOOD_VERSION

   delta_table = DeltaTable.forName(spark, table_name)
   delta_table.restoreToVersion(good_version)
   ```

2. After the restore completes, add another code cell and verify that the current table now matches the recovered state.

   ```python
   restored_df = spark.table("silver_orders")
   restored_count = restored_df.count()

   print("Restored row count:", restored_count)
   display(restored_df.limit(20))
   display(DeltaTable.forName(spark, "silver_orders").history())
   ```

3. Confirm that the restore operation created a new history entry. The new entry should show that a restore occurred; it does not remove the previous corruption event from the log.
4. If you want a direct comparison between the restored current table and the known-good version, run the following check and confirm that the difference count is 0 after the restore:

   ```python
   good_version_df = spark.read.format("delta").option("versionAsOf", good_version).table("silver_orders")

   difference_count = restored_df.exceptAll(good_version_df).count() + good_version_df.exceptAll(restored_df).count()
   print("Difference count:", difference_count)
   ```

5. Save the restore evidence to a second JSON file by running the following cell:

   ```python
   import json
   import os

   restore_evidence = {
       "tableName": "silver_orders",
       "restoredToVersion": good_version,
       "restoredRowCount": restored_count
   }

   output_path = r"C:\LabFiles\validation\silver-recovery-restore.json"
   os.makedirs(os.path.dirname(output_path), exist_ok=True)

   with open(output_path, "w", encoding="utf-8") as f:
       json.dump(restore_evidence, f, indent=2)

   print(f"Saved {output_path}")
   ```

6. Open File Explorer on the lab VM and verify that both files exist in `C:\LabFiles\validation`:
   - `silver-recovery-history.json`
   - `silver-recovery-restore.json`

> [!Note]
> Delta Lake `RESTORE` creates a new current version that points back to the selected historical state. It does not erase the history of the corruption event.

<validation step="5"/>

## Task 3: Create a backup clone and upload the final validation files

In this task, you will create a shallow clone of the restored table and upload all three recovery evidence files to the validation storage account.

1. Return to the notebook and add a new code cell to create a backup clone table named `silver_orders_backup`.

   ```python
   spark.sql("DROP TABLE IF EXISTS silver_orders_backup")
   spark.sql("CREATE TABLE silver_orders_backup SHALLOW CLONE silver_orders")
   ```

2. Verify that the clone exists and is queryable.

   ```python
   clone_df = spark.table("silver_orders_backup")
   print("Clone row count:", clone_df.count())
   display(clone_df.limit(20))
   ```

3. Save the clone evidence to a third JSON file by running the following cell:

   ```python
   import json
   import os

   clone_evidence = {
       "sourceTable": "silver_orders",
       "cloneTable": "silver_orders_backup",
       "cloneType": "shallow"
   }

   output_path = r"C:\LabFiles\validation\silver-recovery-clone.json"
   os.makedirs(os.path.dirname(output_path), exist_ok=True)

   with open(output_path, "w", encoding="utf-8") as f:
       json.dump(clone_evidence, f, indent=2)

   print(f"Saved {output_path}")
   ```

4. Note the values you will use in PowerShell for the upload step:
   - Deployment ID: <inject key="DeploymentID" enableCopy="false"/>
   - Resource group: `rg-fabricdataquality-<your deployment id>`
   - Storage account: `stfabricval<deployment id without hyphens, first 12 characters>`
   - Container: `validation`
5. On the lab VM, open PowerShell and upload the three evidence files to the validation storage account by running the following script. Before you run it, replace `YOUR-DEPLOYMENT-ID` and `YOUR-STORAGE-ACCOUNT-NAME` with the values from the previous step.

   ```powershell
   $deploymentId = "YOUR-DEPLOYMENT-ID"
   $resourceGroup = "rg-fabricdataquality-$deploymentId"
   $storageAccountName = "YOUR-STORAGE-ACCOUNT-NAME"
   $containerName = "validation"
   $localFolder = "C:\LabFiles\validation"

   $ctx = (Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName).Context

   @(
       "silver-recovery-history.json",
       "silver-recovery-restore.json",
       "silver-recovery-clone.json"
   ) | ForEach-Object {
       Set-AzStorageBlobContent -Context $ctx -Container $containerName -File (Join-Path $localFolder $_) -Blob $_ -Force | Out-Null
   }
   ```

6. Confirm that all three files uploaded successfully to the `validation` container.
7. Record in your notes why a shallow clone is appropriate for short-lived recovery testing and point-in-time validation, but not for long-term archival. Because a shallow clone references the source table files, later cleanup operations such as aggressive file removal can break that dependency.

> [!Important]
> In Microsoft Fabric, `SHALLOW CLONE` is supported, but deep clone is not. A shallow clone is fast and storage-efficient because it references the source table's OneLake files.

> [!Tip]
> If your team needs a durable independent backup, create a full copy by writing the data into another table instead of relying only on shallow clone.

## Summary

In this challenge, you inspected Delta history for `silver_orders`, used time travel to verify the last known good snapshot, restored the current table to that version, created a `silver_orders_backup` shallow clone, and uploaded the required recovery evidence files for validation. These steps establish the Silver-layer recovery controls that you will rely on before validating the end-to-end pipeline in the final challenge.
