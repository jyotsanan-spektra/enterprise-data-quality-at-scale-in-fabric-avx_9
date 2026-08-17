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

6. In the history output, scan the **operation** column for the most recent entries. Look for a `MERGE` operation near the top of the list — this is the operation type the incident simulation script uses to corrupt data. Record its version number as your **candidate corrupted version**, and record the version number immediately before it as your **candidate last-known-good version**.
7. Confirm your candidates are correct by checking the data itself rather than relying on the operation type alone. The simulated incident sets `Revenue` to 0 for 1,000 rows, so count zero-Revenue rows at each candidate version:

   ```python
   candidate_good = CANDIDATE_GOOD_VERSION
   candidate_corrupted = CANDIDATE_CORRUPTED_VERSION

   for v in [candidate_good, candidate_corrupted]:
       version_df = spark.read.format("delta").option("versionAsOf", v).table("silver_orders")
       zero_revenue_count = version_df.filter("Revenue = 0").count()
       print(f"Version {v}: rows with Revenue = 0 -> {zero_revenue_count}")
   ```

8. Confirm the candidate good version shows a low, expected zero-Revenue count and the candidate corrupted version shows a count at or near **1,000**. If neither candidate shows a spike near 1,000, check one version earlier and one version later in the history and repeat step 7 until you find the version boundary where the count jumps.
9. Once confirmed, note the final version numbers as `GOOD_VERSION` and `CORRUPTED_VERSION` for the remaining steps in this challenge.
10. Add a code cell and take a closer look at the confirmed historical snapshot to make sure it looks correct end-to-end, not just on the Revenue column:

    ```python
    historical_df = spark.read.format("delta").option("versionAsOf", GOOD_VERSION).table("silver_orders")

    print("Historical row count:", historical_df.count())
    display(historical_df.limit(20))
    ```

11. Add a code cell and save your history investigation evidence to a JSON file on the lab VM. Use the confirmed version numbers from step 9.

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
> Microsoft Learn recommends running `DESCRIBE HISTORY` or the DeltaTable history method before choosing a restore target. Confirming the version against the actual data, as in step 7 above, avoids restoring to the wrong version just because its operation type looked right.

## Task 2: Restore `silver_orders` and capture recovery evidence

In this task, you will restore the Silver table to the correct version and verify that the current business state is healthy again.

1. In the same notebook, add a new code cell and restore the table to the last known good version confirmed in Task 1.

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

3. Confirm the restore created a new history entry with operation `RESTORE`. This new entry does not remove the previous corruption event from the log — you should still see the earlier `MERGE` entry below it.
4. Confirm zero remaining corruption symptoms directly:

   ```python
   post_restore_zero_revenue = restored_df.filter("Revenue = 0").count()
   print("Rows with Revenue = 0 after restore:", post_restore_zero_revenue)
   ```

   This count should now match the low, expected baseline count you observed for the good version in Task 1 — not the ~1,000 you saw at the corrupted version.
5. For a full row-level comparison, confirm the difference count between the restored table and the known-good version is 0:

   ```python
   good_version_df = spark.read.format("delta").option("versionAsOf", good_version).table("silver_orders")

   difference_count = restored_df.exceptAll(good_version_df).count() + good_version_df.exceptAll(restored_df).count()
   print("Difference count:", difference_count)
   ```

6. Save the restore evidence to a second JSON file by running the following cell:

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

7. Open File Explorer on the lab VM and verify that both files exist in `C:\LabFiles\validation`:
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

2. Verify that the clone exists and is queryable, and confirm its row count matches the restored table's row count from Task 2.

   ```python
   clone_df = spark.table("silver_orders_backup")
   clone_count = clone_df.count()
   print("Clone row count:", clone_count)
   display(clone_df.limit(20))
   ```

3. Save the clone evidence to a third JSON file by running the following cell:

   ```python
   import json
   import os

   clone_evidence = {
       "sourceTable": "silver_orders",
       "cloneTable": "silver_orders_backup",
       "cloneType": "shallow",
       "cloneRowCount": clone_count
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

6. Confirm all three files uploaded successfully by running `Get-AzStorageBlob -Context $ctx -Container $containerName | Select-Object Name` and checking that all three filenames appear in the output.
7. Record in your notes why a shallow clone is appropriate for short-lived recovery testing and point-in-time validation, but not for long-term archival. Because a shallow clone references the source table's files, later cleanup operations such as aggressive file removal can break that dependency.

> [!Important]
> In Microsoft Fabric, `SHALLOW CLONE` is supported, but deep clone is not. A shallow clone is fast and storage-efficient because it references the source table's OneLake files.

> [!Tip]
> If your team needs a durable independent backup, create a full copy by writing the data into another table instead of relying only on shallow clone.

## Summary

In this challenge, you inspected Delta history for `silver_orders`, used time travel to verify the last known good snapshot, restored the current table to that version, created a `silver_orders_backup` shallow clone, and uploaded the required recovery evidence files for validation. These steps establish the Silver-layer recovery controls that you will rely on before validating the end-to-end pipeline in the final challenge.
