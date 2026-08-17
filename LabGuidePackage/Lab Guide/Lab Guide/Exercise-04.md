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

1. Sign in to Microsoft Fabric by using Username: <inject key="AzureAdUserEmail"></inject> and Password: <inject key="AzureAdUserPassword"></inject>.
2. Open the Fabric workspace you used in the previous challenges.
3. Note the deployment reference for this lab environment as **<inject key="DeploymentID" enableCopy="false"/>**.
4. Open the Lakehouse you created or confirmed in Challenge 1 (**contoso_medallion_lh**).
5. In the **Tables** pane, confirm that the Bronze table `bronze_orders_cdc` exists and shows approximately 100,500 rows (the baseline plus incremental rows from Challenge 2).
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

10. Confirm the printed schema lists all 12 expected columns and the row count is approximately 100,500.

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

1. Confirm the prepared defect file exists at `C:\LabFiles\FabricChallengeLab\Samples\quality_defect.csv`. It contains 100 order rows in the same 12-column schema, with exactly 10 rows carrying a blank `OrderID` — a 10% null rate, well above the 0.1% threshold from step 2 of Task 2.
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
5. Re-run the null check logic from Task 2, step 2 against `defect_df` instead of `bronze_df`, and confirm `null_check_passed` evaluates to `False`.
6. Confirm the failed rule is recorded in `quality_gate_log` by running `display(spark.table("quality_gate_log").orderBy(F.col("runTimestamp").desc()).limit(5))` and checking that the most recent row shows `status = "Failed"` for `rule = "null_check"`.
7. Confirm the notebook does **not** write the defective dataset to `silver_orders` — the conditional write logic from Task 2, step 10 should raise an exception rather than overwrite the table when run against `defect_df`.
8. Query `silver_orders` again (`spark.table("silver_orders").count()`) and verify its row count is unchanged from the value you recorded at the end of Task 2.
9. If you are also preparing for Challenge 6, confirm the `raise Exception(...)` statement in Task 2, step 10 executes and stops the notebook when the gate fails — this is what the pipeline's retry and failure-branch logic in Challenge 6 depends on to detect the failure.
10. Save the notebook after both the pass run (Task 2) and the fail run (this task) are complete.
11. Keep the Lakehouse, notebook, and logged output available for downstream verification.

## Task 4: Upload your quality gate evidence for validation

In this task, you will record both gate outcomes into an evidence file and upload it for automated validation.

> [!Important]
> Run these commands from a **PowerShell window on the lab VM**, not from a notebook cell. You are typing in the values you observed in the notebook output.

1. On the lab VM, open PowerShell.
2. Fill in the values below from your two notebook runs, then run the block. `silverRowCountAfterPassRun` and `silverRowCountAfterFailRun` must be equal — that is the proof that the failed gate did not overwrite Silver:

   ```powershell
   $evidence = [ordered]@{
       silverTableName            = 'silver_orders'
       passRunOverallStatus       = 'Passed'       # Task 2, step 8
       failRunOverallStatus       = 'Failed'       # Task 3, step 5
       failRunFailedRule          = 'null_check'   # Task 3, step 6
       silverRowCountAfterPassRun = 100500         # Task 2, step 13
       silverRowCountAfterFailRun = 100500         # Task 3, step 8 - must match the line above
   }

   New-Item -ItemType Directory -Path 'C:\LabFiles\validation' -Force | Out-Null
   $evidence | ConvertTo-Json | Set-Content -Path 'C:\LabFiles\validation\quality-gate.json' -Encoding utf8
   Get-Content 'C:\LabFiles\validation\quality-gate.json'
   ```

3. Upload the file using the same pattern as the previous challenges:

   ```powershell
   $envMap = @{}
   Get-Content 'C:\LabFiles\.env' | ForEach-Object {
       if ($_ -match '^(?<k>[A-Z0-9_]+)=(?<v>.*)$') { $envMap[$Matches.k] = $Matches.v }
   }

   if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }

   $resourceGroup = "rg-fabricdataquality-$($envMap['DEPLOYMENT_ID'])"
   $ctx = (Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $envMap['VALIDATION_STORAGE_ACCOUNT']).Context

   Set-AzStorageBlobContent -Context $ctx -Container 'validation' `
       -File 'C:\LabFiles\validation\quality-gate.json' -Blob 'quality-gate.json' -Force | Out-Null

   Get-AzStorageBlob -Context $ctx -Container 'validation' | Select-Object Name
   ```

4. Confirm that `quality-gate.json` appears in the output.

<validation step="Spark quality gate behavior"/>

## Summary
You implemented a Fabric notebook that evaluates `bronze_orders_cdc` with null, range, referential integrity, freshness, and schema checks before any Silver promotion occurs. You then wrote `silver_orders` only when the gate passed, captured quality evidence in the Lakehouse, and proved that a controlled defect prevents the Silver layer from being refreshed.
