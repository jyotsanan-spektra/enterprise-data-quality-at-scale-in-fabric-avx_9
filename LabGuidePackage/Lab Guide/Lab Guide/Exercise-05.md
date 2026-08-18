# Challenge 5 - Audit, recover, and protect data with Delta Lake time travel

### Estimated Duration: 40 Minutes

## Scenario

A bad upstream job has corrupted revenue values in the `silver_orders` Delta table in your Microsoft Fabric medallion environment. In this challenge you will first reproduce that incident in a controlled way, then investigate the table history, prove which version still contains the correct business data, restore the table to that verified state, and create a backup clone that the team can use for short-lived recovery readiness.

## Overview

In this challenge, you will trigger a controlled corruption event against `silver_orders`, use a Fabric notebook to inspect Delta Lake history, compare current data with a previous snapshot by using time travel, restore the live table to the correct version, and create a shallow clone backup table. You will also upload the required recovery evidence files so the lab validation can confirm your work.

## Objectives

- Task 1: Reproduce the controlled corruption incident
- Task 2: Review Delta history and identify the last known good Silver version
- Task 3: Restore `silver_orders` and capture recovery evidence
- Task 4: Create a backup clone and upload the final validation files

> [!Important]
> This exercise's evidence example values assume `silver_orders` has ~100,500 rows, carried over from Challenge 2's assumed change-set size. In this environment, the corrected row count is ~100,350 (see the note at the top of Challenge 4, Task 1). Use your actual observed row counts throughout Task 4, not the example numbers below. Task 4 step 5 also assumes `C:\LabFiles\.env` and a pre-provisioned validation storage account exist — since they don't in this environment, step 5 below reuses the storage account created in Challenge 2, Task 6 by looking it up directly instead.

## Task 1: Reproduce the controlled corruption incident

In this task, you will simulate the upstream incident that damaged the Silver table, so that there is a real corruption event in the Delta history for you to investigate and recover from.

1. Sign in to Microsoft Fabric with the lab credentials.
   - Username: <inject key="AzureAdUserEmail"></inject>
   - Password: <inject key="AzureAdUserPassword"></inject>
2. Confirm that you are working in the lab environment associated with **Deployment ID: <inject key="DeploymentID" enableCopy="false"/>**.
3. Open the Fabric workspace you used in the previous challenges, and then open the Lakehouse that contains the `silver_orders` table.
4. From the Lakehouse, open a notebook that is attached to the same Lakehouse. If you do not already have a notebook for Silver-layer operations, create a new notebook named `silver_recovery_investigation`.
5. Confirm the table is currently healthy before you damage it. Run the following cell and note the row count and the zero-Revenue count, which should be **0**:

   ```python
   healthy_count = spark.table("silver_orders").count()
   healthy_zero_revenue = spark.table("silver_orders").filter("Revenue = 0").count()
   print("Row count:", healthy_count)
   print("Rows with Revenue = 0 before the incident:", healthy_zero_revenue)
   ```

   > [!Note]
   > If `silver_orders` does not exist, go back and complete Challenge 4, Task 2 — the quality gate must write the Silver table before you can recover it here.

6. Run the following cell to simulate the faulty upstream job. It performs a Delta `MERGE` that zeroes out `Revenue` for exactly 1,000 orders, which is the incident you will investigate and undo:

   ```python
   spark.sql("""
       MERGE INTO silver_orders AS t
       USING (SELECT explode(sequence(1, 1000)) AS OrderID) AS s
       ON t.OrderID = s.OrderID
       WHEN MATCHED THEN UPDATE SET t.Revenue = 0
   """)
   ```

7. Confirm the damage landed as expected. The zero-Revenue count should now be **1000**, and the total row count should be unchanged from step 5:

   ```python
   print("Rows with Revenue = 0 after the incident:", spark.table("silver_orders").filter("Revenue = 0").count())
   print("Row count after the incident:", spark.table("silver_orders").count())
   ```

> [!Important]
> The `MERGE` you just ran is recorded as its own version in the Delta transaction log. That is what makes the recovery workflow in the next tasks possible — the previous, healthy version is still retained and readable.

## Task 2: Review Delta history and identify the last known good Silver version

In this task, you will use Delta history and read-only time travel to determine which version of `silver_orders` should be restored.

1. In the same notebook, add a new code cell and run the following PySpark statements to inspect the current table and its Delta history:

   ```python
   from delta.tables import DeltaTable

   table_name = "silver_orders"
   delta_table = DeltaTable.forName(spark, table_name)

   current_df = spark.table(table_name)
   print("Current row count:", current_df.count())
   display(current_df.limit(20))
   display(delta_table.history())
   ```

2. In the history output, scan the **operation** column for the most recent entries. Look for a `MERGE` operation near the top of the list — this is the operation type the incident simulation script uses to corrupt data. Record its version number as your **candidate corrupted version**, and record the version number immediately before it as your **candidate last-known-good version**.
3. Confirm your candidates are correct by checking the data itself rather than relying on the operation type alone. The simulated incident sets `Revenue` to 0 for 1,000 rows, so count zero-Revenue rows at each candidate version. Replace the two values below with the actual integer version numbers you recorded in step 2 (for example, `4` and `5`) before running the cell:

   ```python
   candidate_good = 0        # replace with your candidate last-known-good version from step 2
   candidate_corrupted = 0   # replace with your candidate corrupted version from step 2

   for v in [candidate_good, candidate_corrupted]:
       version_df = spark.read.format("delta").option("versionAsOf", v).table("silver_orders")
       zero_revenue_count = version_df.filter("Revenue = 0").count()
       print(f"Version {v}: rows with Revenue = 0 -> {zero_revenue_count}")
   ```

4. Confirm the candidate good version shows a low, expected zero-Revenue count and the candidate corrupted version shows a count at or near **1,000**. If neither candidate shows a spike near 1,000, check one version earlier and one version later in the history and repeat step 3 until you find the version boundary where the count jumps.
5. Once confirmed, add a code cell that fixes the two version numbers as plain Python variables so the rest of the notebook can reuse them without retyping the literal numbers:

    ```python
    GOOD_VERSION = candidate_good          # or the confirmed integer, if it differs from your first candidate
    CORRUPTED_VERSION = candidate_corrupted
    ```

6. Add a code cell and take a closer look at the confirmed historical snapshot to make sure it looks correct end-to-end, not just on the Revenue column:

    ```python
    historical_df = spark.read.format("delta").option("versionAsOf", GOOD_VERSION).table("silver_orders")

    print("Historical row count:", historical_df.count())
    display(historical_df.limit(20))
    ```

7. Print the two confirmed version numbers so you can copy them onto the lab VM in Task 4:

    ```python
    print("CORRUPTED_VERSION =", CORRUPTED_VERSION)
    print("GOOD_VERSION      =", GOOD_VERSION)
    ```

    Write both numbers down. You will type them into a PowerShell command on the lab VM later.

    > [!Important]
    > Fabric notebooks run on remote Spark compute, not on your lab VM. A notebook cell cannot write a file to `C:\LabFiles`, so all validation evidence files in this challenge are created on the VM in Task 4 using the values you record here.

> [!Important]
> Delta Lake time travel is read-only. Use it to verify the historical snapshot before you run a restore.

> [!Tip]
> Microsoft Learn recommends running `DESCRIBE HISTORY` or the DeltaTable history method before choosing a restore target. Confirming the version against the actual data, as in step 3 above, avoids restoring to the wrong version just because its operation type looked right.

## Task 3: Restore `silver_orders` and capture recovery evidence

In this task, you will restore the Silver table to the correct version and verify that the current business state is healthy again.

1. In the same notebook, add a new code cell and restore the table to the last known good version confirmed in Task 2.

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

   This count should now match the low, expected baseline count you observed for the good version in Task 2 — not the ~1,000 you saw at the corrupted version.
5. For a full row-level comparison, confirm the difference count between the restored table and the known-good version is 0:

   ```python
   good_version_df = spark.read.format("delta").option("versionAsOf", good_version).table("silver_orders")

   difference_count = restored_df.exceptAll(good_version_df).count() + good_version_df.exceptAll(restored_df).count()
   print("Difference count:", difference_count)
   ```

6. Print the restore results so you can record them for the evidence files you create in Task 4:

   ```python
   print("restoredToVersion =", good_version)
   print("restoredRowCount  =", restored_count)
   ```

   Write both values down alongside the version numbers you recorded in Task 2.

> [!Note]
> Delta Lake `RESTORE` creates a new current version that points back to the selected historical state. It does not erase the history of the corruption event.

## Task 4: Create a backup clone and upload the final validation files

In this task, you will create a shallow clone of the restored table and upload all three recovery evidence files to the validation storage account.

1. Return to the notebook and add a new code cell to create a backup clone table named `silver_orders_backup`.

   ```python
   spark.sql("DROP TABLE IF EXISTS silver_orders_backup")
   spark.sql("CREATE TABLE silver_orders_backup SHALLOW CLONE silver_orders")
   ```

2. Verify that the clone exists and is queryable, and confirm its row count matches the restored table's row count from Task 3.

   ```python
   clone_df = spark.table("silver_orders_backup")
   clone_count = clone_df.count()
   print("Clone row count:", clone_count)
   display(clone_df.limit(20))
   ```

3. Print the clone row count so you can record it with your other evidence values:

   ```python
   print("cloneRowCount =", clone_count)
   ```

4. On the lab VM, open PowerShell. Fill in the four values below with the numbers you actually recorded in Tasks 2, 3, and 4 — use your real observed row count (approximately **100,350** in this environment, not the 100,500 shown as an example), then run the block to create all three evidence files at once:

   ```powershell
   $corruptedVersion = 5        # Task 2, step 7 - your actual corrupted version number
   $goodVersion      = 4        # Task 2, step 7 - your actual last-known-good version number
   $restoredRowCount = 100350   # Task 3, step 6 - your actual restored row count
   $cloneRowCount    = 100350   # Task 4, step 3 - your actual clone row count

   New-Item -ItemType Directory -Path 'C:\LabFiles\validation' -Force | Out-Null

   [ordered]@{
       tableName            = 'silver_orders'
       corruptedVersion     = $corruptedVersion
       lastKnownGoodVersion = $goodVersion
   } | ConvertTo-Json | Set-Content 'C:\LabFiles\validation\silver-recovery-history.json' -Encoding utf8

   [ordered]@{
       tableName         = 'silver_orders'
       restoredToVersion = $goodVersion
       restoredRowCount  = $restoredRowCount
   } | ConvertTo-Json | Set-Content 'C:\LabFiles\validation\silver-recovery-restore.json' -Encoding utf8

   [ordered]@{
       sourceTable   = 'silver_orders'
       cloneTable    = 'silver_orders_backup'
       cloneType     = 'shallow'
       cloneRowCount = $cloneRowCount
   } | ConvertTo-Json | Set-Content 'C:\LabFiles\validation\silver-recovery-clone.json' -Encoding utf8

   Get-ChildItem 'C:\LabFiles\validation'
   ```

5. Upload all three evidence files, reusing the **same** validation storage account created in Challenge 2, Task 6. Since `C:\LabFiles\.env` does not exist in this environment, this script finds the storage account by its `stfabricval*` naming prefix instead of reading it from a file:

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

   @(
       'silver-recovery-history.json',
       'silver-recovery-restore.json',
       'silver-recovery-clone.json'
   ) | ForEach-Object {
       Set-AzStorageBlobContent -Context $ctx -Container $containerName `
           -File (Join-Path 'C:\LabFiles\validation' $_) -Blob $_ -Force | Out-Null
   }
   ```
   Adjust `$resourceGroup` if it doesn't match your environment.

6. Confirm all three files uploaded successfully by running `Get-AzStorageBlob -Context $ctx -Container $containerName | Select-Object Name` and checking that all three filenames appear in the output, alongside `cdc-ingestion.json`, `scd-type2.json`, and `quality-gate.json` from the earlier challenges.
7. Record in your notes why a shallow clone is appropriate for short-lived recovery testing and point-in-time validation, but not for long-term archival. Because a shallow clone references the source table's files, later cleanup operations such as aggressive file removal can break that dependency.

> [!Important]
> In Microsoft Fabric, `SHALLOW CLONE` is supported, but deep clone is not. A shallow clone is fast and storage-efficient because it references the source table's OneLake files.

> [!Tip]
> If your team needs a durable independent backup, create a full copy by writing the data into another table instead of relying only on shallow clone.

<validation step="Validate Delta Lake history investigation, restore, and backup clone evidence for silver_orders."/>

## Summary

In this challenge, you reproduced a controlled corruption event against `silver_orders`, inspected the resulting Delta history, used time travel to verify the last known good snapshot, restored the current table to that version, created a `silver_orders_backup` shallow clone, and uploaded the required recovery evidence files for validation. These steps establish the Silver-layer recovery controls that you will rely on before validating the end-to-end pipeline in the final challenge.
