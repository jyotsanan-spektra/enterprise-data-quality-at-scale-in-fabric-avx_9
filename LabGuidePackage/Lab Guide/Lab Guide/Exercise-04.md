# Challenge 4: Enforce Spark-based data quality gates before Silver promotion

### Estimated Duration: 40 Minutes

## Scenario
The CDC process you configured earlier now lands operational changes in the Bronze layer, but Bronze data isn't trusted automatically. In this challenge, you will build a PySpark quality gate in Microsoft Fabric so that `bronze_orders_cdc` is promoted to `silver_orders` only when required checks pass. You will also capture failure evidence that can be reused in the final orchestration challenge.

## Overview
You will open or create a Fabric notebook, attach it to your Lakehouse, and implement five explicit validations against the Bronze orders table: null, range, referential integrity, freshness, and schema checks. You will then add conditional write logic so `silver_orders` is updated only when all rules pass, record the quality results, and rerun the notebook with a controlled defect to verify that promotion is blocked.

> [!Note]
> The code in this challenge is a working reference implementation, not a fixed script you must match line-for-line. Column names and thresholds below match the 12-column `bronze_orders_cdc` schema used elsewhere in this lab (OrderID, CustomerID, OrderDate, ShipDate, OrderStatus, ProductID, Quantity, UnitPrice, Discount, Revenue, ShippingCountry, PaymentMethod). If your deployment's actual grading rubric expects different column names or thresholds, adapt the code accordingly and confirm against that rubric before relying on it for validation.

## Objectives
- Task 1: Prepare the Lakehouse and notebook context for the quality gate
- Task 2: Implement and run the PySpark quality checks
- Task 3: Trigger the failure path and confirm Silver promotion is blocked
- Task 4: Upload your quality gate evidence for validation

## Task 1: Prepare the Lakehouse and notebook context for the quality gate

In this task, you will return to your learner-created Fabric items and prepare the notebook environment that will enforce the Bronze-to-Silver gate.

> [!Important]
> This exercise's expected `bronze_orders_cdc` row count assumes Challenge 2's change set added exactly 500 rows. In this environment, the change set was 350 inserts + 150 updates, and updates don't add rows — so the correct expected count throughout this exercise is your actual Challenge 2 result (**100,350** if you followed the corrected Challenge 2 guide), not the "100,500" figure below. Use your real observed number wherever this exercise says ~100,500.

1. Sign in to Microsoft Fabric by using Username: <inject key="AzureAdUserEmail"></inject> and Password: <inject key="AzureAdUserPassword"></inject>.
2. Open the Fabric workspace you used in the previous challenges.
3. Note the deployment reference for this lab environment as **<inject key="DeploymentID" enableCopy="false"/>**.
4. Open the Lakehouse you created or confirmed in Challenge 1 (**contoso_medallion_lh**).
5. In the **Tables** pane, confirm that the Bronze table `bronze_orders_cdc` exists and shows approximately 100,500 rows (the baseline plus incremental rows from Challenge 2) — or your actual corrected count (approximately 100,350) if you followed the corrected Challenge 2 guide.
6. Confirm whether `silver_orders` already exists. If it does, keep it as the target curated table for this challenge. If it doesn't exist yet, you will create it from the notebook only after the quality checks pass.
7. From the Lakehouse page, select **Open notebook**, then select **Existing notebook** and choose **nb_data_quality_gate** (the notebook you created in Challenge 1) to open it. If it does not appear in the list, select **New notebook** instead and rename the new notebook to **nb_data_quality_gate**.
8. If more than one Lakehouse is attached to the notebook, make sure **contoso_medallion_lh** is pinned as the default Lakehouse before you run Spark SQL or use relative table paths.
9. In the first notebook cell, confirm you can query `bronze_orders_cdc` and review its columns:

   ```python
   bronze_df = spark.read.format("delta").table("bronze_orders_cdc")
   bronze_df.printSchema()
   print("Row count:", bronze_df.count())
   display(bronze_df.limit(10))
   ```

10. Confirm the printed schema lists all 12 expected columns and the row count matches your actual Challenge 2 result (approximately 100,350 in this environment, not 100,500).

> [!Note]
> Microsoft Learn notes that the pinned default Lakehouse determines the root context for relative paths and Spark SQL in a notebook. Verify the correct Lakehouse is pinned before you run validation code.

## Task 2: Implement and run the PySpark quality checks

In this task, you will build the step-by-step validation logic that determines whether Bronze data is allowed into the Silver layer.

1. Add a new notebook section named **Quality gate setup** and import what you'll need:

   ```python
   from pyspark.sql import functions as F
   from datetime import datetime
   import json

   bronze_df = spark.read.format("delta").table("bronze_orders_cdc")
   total_rows = bronze_df.count()
   results = []
   ```

2. **Null check** — required columns must not be null, failing if the null rate exceeds 0.1%:

   ```python
   required_cols = ["OrderID", "CustomerID", "OrderDate", "Revenue"]
   null_counts = {c: bronze_df.filter(F.col(c).isNull()).count() for c in required_cols}
   worst_null_rate = max(null_counts.values()) / total_rows
   null_check_passed = worst_null_rate <= 0.001
   results.append({"rule": "null_check", "status": "Passed" if null_check_passed else "Failed",
                    "failedRowCount": max(null_counts.values()), "message": str(null_counts)})
   ```

3. **Range check** — Revenue must fall between 0 and 1,000,000; outliers are flagged but do not block promotion on their own:

   ```python
   out_of_range_count = bronze_df.filter((F.col("Revenue") < 0) | (F.col("Revenue") > 1000000)).count()
   range_check_passed = out_of_range_count == 0
   results.append({"rule": "range_check", "status": "Passed" if range_check_passed else "Flagged",
                    "failedRowCount": out_of_range_count, "message": "Revenue outside 0-1,000,000"})
   ```

4. **Referential integrity check** — every `CustomerID` in Orders must exist in the customer dimension, failing if the orphan rate exceeds 0.5%.
   - **Preferred:** Attach `contoso_gold_wh` to the notebook first (**Explorer > Add data items > Warehouse**) if your workspace supports querying a Warehouse table directly from Spark SQL, then use the first line below.
   - **Fallback:** If you cannot attach the Warehouse, use the second line below instead, replacing `<JDBC_CONNECTION_STRING>` with the JDBC connection string you recorded in Challenge 1, Task 2.

   ```python
   # Preferred, if contoso_gold_wh is attached directly to the notebook:
   customer_ids_df = spark.sql("SELECT DISTINCT CustomerID FROM contoso_gold_wh.dbo.dim_customer")

   # Fallback, if the Warehouse is not attached:
   # customer_ids_df = spark.read.format("jdbc") \
   #     .option("url", "<JDBC_CONNECTION_STRING>") \
   #     .option("query", "SELECT DISTINCT CustomerID FROM dim_customer") \
   #     .load()

   orphan_count = bronze_df.join(customer_ids_df, "CustomerID", "left_anti").count()
   orphan_rate = orphan_count / total_rows
   ref_check_passed = orphan_rate <= 0.005
   results.append({"rule": "referential_integrity", "status": "Passed" if ref_check_passed else "Failed",
                    "failedRowCount": orphan_count, "message": f"orphan_rate={orphan_rate:.4f}"})
   ```

5. **Freshness check** — the most recent `OrderDate` must be within 2 days of the current date:

   ```python
   max_order_date = bronze_df.select(F.max("OrderDate")).first()[0]
   freshness_days = (datetime.now().date() - max_order_date).days
   freshness_check_passed = freshness_days <= 2
   results.append({"rule": "freshness_check", "status": "Passed" if freshness_check_passed else "Failed",
                    "failedRowCount": 0, "message": f"max OrderDate is {freshness_days} day(s) old"})
   ```

6. **Schema drift check** — column count must equal 12 and column names must match exactly:

   ```python
   expected_columns = ["OrderID", "CustomerID", "OrderDate", "ShipDate", "OrderStatus", "ProductID",
                        "Quantity", "UnitPrice", "Discount", "Revenue", "ShippingCountry", "PaymentMethod"]
   schema_check_passed = (bronze_df.columns == expected_columns)
   results.append({"rule": "schema_check", "status": "Passed" if schema_check_passed else "Failed",
                    "failedRowCount": 0, "message": f"columns={bronze_df.columns}"})
   ```

7. Combine and display the results:

   ```python
   results_df = spark.createDataFrame(results)
   display(results_df)
   ```

8. Determine the overall gate status. The range check is flag-only per the scenario, so it does not block promotion on its own — the other four checks do:

   ```python
   overall_passed = null_check_passed and ref_check_passed and freshness_check_passed and schema_check_passed
   overall_status = "Passed" if overall_passed else "Failed"
   print("Overall gate status:", overall_status)
   ```

9. Persist the run's results to a quality evidence table so it survives outside the notebook cell output:

   ```python
   results_df.withColumn("runTimestamp", F.current_timestamp()) \
             .withColumn("overallStatus", F.lit(overall_status)) \
             .write.format("delta").mode("append").saveAsTable("quality_gate_log")
   ```

10. Add conditional write logic so `silver_orders` is written only when the gate passes:

    ```python
    if overall_passed:
        bronze_df.write.format("delta").mode("overwrite").saveAsTable("silver_orders")
        print("silver_orders written.")
    else:
        raise Exception(f"Quality gate failed: {[r for r in results if r['status'] == 'Failed']}")
    ```

11. Run the notebook with the current valid Bronze data and confirm all four blocking checks show **Passed** in the displayed results table.
12. Refresh the Lakehouse **Tables** pane and confirm `silver_orders` exists (or was updated) after the successful run.
13. Run `spark.table("silver_orders").count()` and record the row count as baseline evidence before testing the failure path in Task 3.

> [!Important]
> Microsoft Learn documents Delta tables in Fabric Lakehouse as the default managed table format and shows `saveAsTable()` as the standard pattern for writing Spark output to Lakehouse tables. Keep the Silver write inside the pass-only branch of your notebook logic.

## Task 3: Trigger the failure path and confirm Silver promotion is blocked

In this task, you will deliberately test the gate with bad data and confirm the notebook records the failure without refreshing the Silver table.

1. `quality_defect.csv` is not pre-created in this environment. Generate it on the lab VM with the following PowerShell script — 100 rows in the same 12-column schema as `bronze_orders_cdc`, with the first 10 rows carrying a blank `OrderID`:

   ```powershell
   $countries = @('United States', 'Canada', 'United Kingdom', 'Germany', 'France', 'Australia', 'India', 'Japan', 'Brazil', 'Mexico')

   $rows = for ($i = 1; $i -le 100; $i++) {
       $orderId = if ($i -le 10) { '' } else { 900000 + $i }
       $unitPrice = [math]::Round((($i % 50) + 10) * 1.5, 2)
       $quantity = ($i % 10) + 1

       [pscustomobject]@{
           OrderID         = $orderId
           CustomerID      = ($i % 5000) + 1
           OrderDate       = (Get-Date).AddDays(-$i).ToString('yyyy-MM-dd')
           ShipDate        = (Get-Date).AddDays(-$i + 3).ToString('yyyy-MM-dd')
           OrderStatus     = 'Submitted'
           ProductID       = ($i % 500) + 1
           Quantity        = $quantity
           UnitPrice       = $unitPrice
           Discount        = 0
           Revenue         = [math]::Round($unitPrice * $quantity, 2)
           ShippingCountry = $countries[$i % $countries.Count]
           PaymentMethod   = 'CreditCard'
       }
   }

   New-Item -ItemType Directory -Path 'C:\LabFiles\FabricChallengeLab\Samples' -Force | Out-Null
   $rows | Export-Csv -Path 'C:\LabFiles\FabricChallengeLab\Samples\quality_defect.csv' -NoTypeInformation -Force
   ```

   Confirm it printed 100 rows with 10 blank `OrderID` values before continuing.
2. Upload `quality_defect.csv` into your Lakehouse **Files** area.
3. In a new notebook cell, load the defect file and run it through the same checks instead of `bronze_orders_cdc`:

   ```python
   defect_df = spark.read.option("header", True).csv("Files/quality_defect.csv")
   defect_total = defect_df.count()
   defect_null_orderid_count = defect_df.filter(F.col("OrderID").isNull() | (F.col("OrderID") == "")).count()
   defect_null_rate = defect_null_orderid_count / defect_total
   print(f"OrderID null count: {defect_null_orderid_count} / {defect_total} (rate={defect_null_rate:.2%})")
   ```

4. Confirm the printed null count is **10** and the rate is approximately **10%**, well above the 0.1% threshold — this check should report **Failed**.
5. Re-run the null check logic from Task 2, step 2 against `defect_df` instead of `bronze_df`:

   ```python
   required_cols = ["OrderID", "CustomerID", "OrderDate", "Revenue"]

   defect_null_counts = {
       c: defect_df.filter(F.col(c).isNull() | (F.col(c) == "")).count()
       for c in required_cols
   }
   worst_defect_null_rate = max(defect_null_counts.values()) / defect_total
   null_check_passed = worst_defect_null_rate <= 0.001

   print("defect_null_counts:", defect_null_counts)
   print("worst_defect_null_rate:", worst_defect_null_rate)
   print("null_check_passed:", null_check_passed)
   ```

   > [!Important]
   > Divide by `defect_total` (100), not `total_rows` (which is still bound to `bronze_df`'s ~100,350 count from Task 2). Dividing by the wrong denominator gives a rate of `10/100350 ≈ 0.01%` — below the 0.1% threshold — which would wrongly report **Passed** and defeat the point of this test. Also note `defect_df` was loaded from CSV without a schema, so missing `OrderID` values are empty strings, not true `NULL` — the check above tests for both, same as step 3.

   Confirm `null_check_passed` prints as **False**.

6. Build a results list for this defect run and persist it to `quality_gate_log`, using separate variable names so you don't overwrite the bronze run's `results`/`overall_passed` from Task 2:

   ```python
   defect_results = [{
       "rule": "null_check",
       "status": "Passed" if null_check_passed else "Failed",
       "failedRowCount": max(defect_null_counts.values()),
       "message": str(defect_null_counts)
   }]

   defect_overall_passed = null_check_passed  # one failed blocking check is enough to fail the whole gate
   defect_overall_status = "Passed" if defect_overall_passed else "Failed"
   print("Overall gate status (defect run):", defect_overall_status)

   defect_results_df = spark.createDataFrame(defect_results)
   defect_results_df.withColumn("runTimestamp", F.current_timestamp()) \
                     .withColumn("overallStatus", F.lit(defect_overall_status)) \
                     .write.format("delta").mode("append").saveAsTable("quality_gate_log")
   ```

   Then confirm the failed rule is recorded by running `display(spark.table("quality_gate_log").orderBy(F.col("runTimestamp").desc()).limit(5))` and checking that the most recent row shows `status = "Failed"` for `rule = "null_check"`.
7. Confirm the notebook does **not** write the defective dataset to `silver_orders` — re-run the conditional write logic from Task 2, step 10, but against `defect_df`, `defect_overall_passed`, and `defect_results` (not the bronze run's `overall_passed`/`results`, which are unrelated to this test):

   ```python
   if defect_overall_passed:
       defect_df.write.format("delta").mode("overwrite").saveAsTable("silver_orders")
       print("silver_orders written.")
   else:
       raise Exception(f"Quality gate failed: {[r for r in defect_results if r['status'] == 'Failed']}")
   ```
   This should raise an exception (visible as a red error/traceback in the cell output) rather than printing "silver_orders written." If you get `NameError: name 'defect_overall_passed' is not defined`, you skipped step 6 above — run it first, then retry this cell.
8. Query `silver_orders` again (`spark.table("silver_orders").count()`) and verify its row count is unchanged from the value you recorded at the end of Task 2.
9. If you are also preparing for Challenge 6, note that the exception raised in step 7 above **is** the confirmation this step asks for — a notebook activity that raises an unhandled exception reports as Failed to a pipeline, which is what triggers Challenge 6's on-failure branch. No additional code is needed here.
10. Save the notebook after both the pass run (Task 2) and the fail run (this task) are complete.
11. Keep the Lakehouse, notebook, and logged output available for downstream verification.

## Task 4: Upload your quality gate evidence for validation

In this task, you will record both gate outcomes into an evidence file and upload it for automated validation.

> [!Important]
> Run these commands from a **PowerShell window on the lab VM**, not from a notebook cell. You are typing in the values you observed in the notebook output.

1. On the lab VM, open PowerShell.
2. Fill in the values below from your two notebook runs, then run the block. `silverRowCountAfterPassRun` and `silverRowCountAfterFailRun` must be equal — that is the proof that the failed gate did not overwrite Silver. Use your actual observed row count (approximately **100,350** in this environment, not the guide's 100,500 — see the note at the top of Task 1):

   ```powershell
   $evidence = [ordered]@{
       silverTableName            = 'silver_orders'
       passRunOverallStatus       = 'Passed'       # Task 2, step 8
       failRunOverallStatus       = 'Failed'       # Task 3, step 5
       failRunFailedRule          = 'null_check'   # Task 3, step 6
       silverRowCountAfterPassRun = 100350         # Task 2, step 13 - your actual observed count
       silverRowCountAfterFailRun = 100350         # Task 3, step 8 - must match the line above
   }

   New-Item -ItemType Directory -Path 'C:\LabFiles\validation' -Force | Out-Null
   $evidence | ConvertTo-Json | Set-Content -Path 'C:\LabFiles\validation\quality-gate.json' -Encoding utf8
   Get-Content 'C:\LabFiles\validation\quality-gate.json'
   ```

3. Upload the file, reusing the **same** validation storage account created in Challenge 2, Task 6. Since `C:\LabFiles\.env` does not exist in this environment, this script finds the storage account by its `stfabricval*` naming prefix instead of reading it from a file:

   ```powershell
   $ErrorActionPreference = 'Stop'

   $resourceGroup = 'labvmrg'      # same resource group you used in previous challenges
   $containerName = 'validation'

   if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }

   $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroup |
       Where-Object { $_.StorageAccountName -like 'stfabricval*' } |
       Select-Object -First 1

   if (-not $storageAccount) {
       throw "Could not find a storage account matching 'stfabricval*' in resource group '$resourceGroup'. Hardcode the exact name instead: `$storageAccount = Get-AzStorageAccount -ResourceGroupName '$resourceGroup' -Name '<exact-name>'"
   }

   $ctx = $storageAccount.Context

   Set-AzStorageBlobContent -Context $ctx -Container $containerName `
       -File 'C:\LabFiles\validation\quality-gate.json' -Blob 'quality-gate.json' -Force | Out-Null

   Get-AzStorageBlob -Context $ctx -Container $containerName | Select-Object Name
   ```
   Adjust `$resourceGroup` if it doesn't match your environment.

4. Confirm that `quality-gate.json` appears in the output alongside `cdc-ingestion.json` and `scd-type2.json` from the earlier challenges.

<validation step="Spark quality gate behavior"/>

## Summary
You implemented a Fabric notebook that evaluates `bronze_orders_cdc` with null, range, referential integrity, freshness, and schema checks before any Silver promotion occurs. You then wrote `silver_orders` only when the gate passed, captured quality evidence in the Lakehouse, and proved that a controlled defect prevents the Silver layer from being refreshed.
