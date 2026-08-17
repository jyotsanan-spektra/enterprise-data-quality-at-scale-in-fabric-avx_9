# Challenge 3: Implement SCD Type 2 history in the Gold Warehouse

### Estimated Duration: 40 Minutes

## Scenario

The Contoso operations team needs the Gold layer to preserve customer attribute history instead of overwriting prior values. In this challenge, you will use the Warehouse item you created in Challenge 1 to build a customer dimension that supports SCD Type 2 behavior, run an initial load, process a change set, and prove that historical and current customer versions are stored correctly.

## Overview

In this challenge, you will open your Fabric Warehouse, create a customer dimension table with surrogate-key and history-tracking columns, load the first version of the customer records, apply a second load that contains customer changes, and validate that changed customers now have expired and current versions side by side.

## Objectives

- Task 1: Create the customer dimension table in the Gold Warehouse
- Task 2: Load the initial customer dimension rows
- Task 3: Apply SCD Type 2 changes and validate history
- Task 4: Upload your SCD Type 2 evidence for validation

## Task 1: Create the customer dimension table in the Gold Warehouse

In this task, you will open the Warehouse from Challenge 1 and create the customer dimension structure required for Type 2 history tracking.

1. Open Microsoft Fabric at <https://app.fabric.microsoft.com> and sign in with the lab credentials if you are prompted:
   - Username: <inject key="AzureAdUserEmail"></inject>
   - Password: <inject key="AzureAdUserPassword"></inject>
2. Open the workspace you used earlier in the lab, and then select the Warehouse item you created for the Gold layer in Challenge 1 (**contoso_gold_wh**).
3. On the Warehouse ribbon, select **New SQL query** to open the SQL query editor.
4. Create the customer dimension table named `dim_customer` by running the following statement. These columns map directly to the prepared `customers_baseline.csv` source file plus the four SCD Type 2 tracking columns:

   ```sql
   CREATE TABLE dim_customer (
       CustomerKey   BIGINT IDENTITY(1,1) NOT NULL,
       CustomerID    INT           NOT NULL,
       CustomerName  VARCHAR(200)  NOT NULL,
       Segment       VARCHAR(50)   NOT NULL,
       Country       VARCHAR(50)   NOT NULL,
       EffectiveDate DATE          NOT NULL,
       ExpiryDate    DATE          NULL,
       IsCurrent     BIT           NOT NULL
   );
   ```

5. Run the statement, then refresh the Warehouse explorer and confirm `dim_customer` appears with 8 columns.
6. Run `SELECT COUNT(*) FROM dim_customer;` and confirm the result is **0** — the table must be empty before Task 2.
7. Record the deployment context for this lab run using **<inject key="DeploymentID" enableCopy="false"/>** so you can tie your validation evidence to the correct environment.

> [!Important]
> Microsoft Learn documents table creation in Fabric Warehouse through the SQL query editor and notes that `IDENTITY` surrogate keys use the `BIGINT` data type. Keep the dimension in the Warehouse item itself, not in the SQL analytics endpoint of another item.

## Task 2: Load the initial customer dimension rows

In this task, you will populate the first version of the customer dimension so you have a baseline state before any tracked changes occur.

1. Confirm the prepared customer source file exists at `C:\LabFiles\FabricChallengeLab\Samples\customers_baseline.csv` on the lab VM, and open it to review its columns: `CustomerID`, `CustomerName`, `Segment`, `Country`. This file contains 5,000 customer rows.
2. Upload `customers_baseline.csv` into your Lakehouse's **Files** area: open **contoso_medallion_lh**, select **Files**, then **Upload > Upload files**, and choose the CSV.
3. Load the file into `dim_customer` using one of the following methods, depending on what your environment supports:
   - **Preferred — COPY INTO:** In the Warehouse SQL query editor, use **COPY INTO dim_customer** pointed at the uploaded file's OneLake path (right-click the file in **Files** and select **Copy Path** to get the exact path), mapping only the `CustomerID`, `CustomerName`, `Segment`, and `Country` source columns.
   - **Fallback — notebook write:** If `COPY INTO` from a Files location is not available in your environment, open a notebook attached to `contoso_medallion_lh` and run a cell like the following, replacing `<JDBC_CONNECTION_STRING>` with the JDBC connection string you recorded in Challenge 1, Task 2:

     ```python
     from pyspark.sql import functions as F

     baseline_df = spark.read.option("header", True).csv("Files/customers_baseline.csv") \
         .select("CustomerID", "CustomerName", "Segment", "Country") \
         .withColumn("EffectiveDate", F.current_date()) \
         .withColumn("ExpiryDate", F.lit(None).cast("date")) \
         .withColumn("IsCurrent", F.lit(1))

     baseline_df.write.format("jdbc") \
         .option("url", "<JDBC_CONNECTION_STRING>") \
         .option("dbtable", "dim_customer") \
         .mode("append") \
         .save()
     ```
4. Regardless of method, insert one row per source customer with:
   - `CustomerID`, `CustomerName`, `Segment`, `Country` copied directly from the source file
   - `EffectiveDate` set to today's load date
   - `ExpiryDate` set to `NULL`
   - `IsCurrent` set to `1`
5. Run the initial load.
6. Run `SELECT COUNT(*) FROM dim_customer;` and confirm the result is exactly **5000** — matching the row count in `customers_baseline.csv`.
7. Run the following query and confirm it returns **zero rows**, proving each customer currently appears only once:

   ```sql
   SELECT CustomerID, COUNT(*) AS RowCount
   FROM dim_customer
   GROUP BY CustomerID
   HAVING COUNT(*) > 1;
   ```

8. Record **5000** as your baseline row count — you will compare against it after Task 3.

> [!Note]
> An initial SCD Type 2 load behaves like a full current snapshot: all rows are inserted as the first active versions. Versioning behavior becomes visible only when a later change set modifies tracked attributes for an existing customer.

## Task 3: Apply SCD Type 2 changes and validate history

In this task, you will process the prepared customer changes by expiring prior rows and inserting replacement current rows, then verify the final state with SQL queries.

1. Confirm the prepared change file exists at `C:\LabFiles\FabricChallengeLab\Samples\customers_changes.csv` and open it. It contains 200 rows, each with a `CustomerID` that already exists in `dim_customer` and an updated `Segment` and/or `Country` value.
2. Upload `customers_changes.csv` into the Lakehouse **Files** area alongside the baseline file.
3. Load the change file into a staging table named `stg_customer_changes` in the Warehouse, using the same COPY INTO or notebook-based method you used in Task 2.
4. Run `SELECT COUNT(*) FROM stg_customer_changes;` and confirm the result is exactly **200**.
5. In the Warehouse SQL query editor, expire the current row for every changed customer. The `JOIN ... WHERE` clause only matches customers whose staged `Segment` or `Country` actually differs from their current dimension row — this makes the logic safe to run more than once, which matters in Challenge 6 where the pipeline invokes this same logic through a stored procedure:

   ```sql
   UPDATE d
   SET IsCurrent = 0,
       ExpiryDate = CAST(GETDATE() AS DATE)
   FROM dim_customer d
   JOIN stg_customer_changes s ON s.CustomerID = d.CustomerID
   WHERE d.IsCurrent = 1
     AND (d.Segment <> s.Segment OR d.Country <> s.Country);
   ```

6. Insert a new current row only for customers who do not already have a current row matching the staged values — this is what keeps step 5 and this step idempotent together:

   ```sql
   INSERT INTO dim_customer (CustomerID, CustomerName, Segment, Country, EffectiveDate, ExpiryDate, IsCurrent)
   SELECT s.CustomerID, s.CustomerName, s.Segment, s.Country, CAST(GETDATE() AS DATE), NULL, 1
   FROM stg_customer_changes s
   WHERE NOT EXISTS (
       SELECT 1 FROM dim_customer d
       WHERE d.CustomerID = s.CustomerID
         AND d.IsCurrent = 1
         AND d.Segment = s.Segment
         AND d.Country = s.Country
   );
   ```

   > [!Note]
   > Running steps 5–6 a second time against the same, already-applied `stg_customer_changes` data will affect **zero** rows, because every customer already has a current row that matches staging. This is intentional: Challenge 6 reruns this same logic through `usp_process_customer_changes`, and it must be safe to execute against data that was already processed.

7. Run `SELECT COUNT(*) FROM dim_customer;` and confirm the result is exactly **5200** — the original 5,000 plus 200 new versions.
8. Run the following query and confirm it returns exactly **200 rows**, one per changed customer with both an expired and a current version:

   ```sql
   SELECT CustomerID, COUNT(*) AS VersionCount
   FROM dim_customer
   GROUP BY CustomerID
   HAVING COUNT(*) = 2;
   ```

9. Run each of the following validation queries and confirm the stated result:
   - Expired rows are dated correctly:
     ```sql
     SELECT COUNT(*) FROM dim_customer WHERE IsCurrent = 0 AND ExpiryDate = CAST(GETDATE() AS DATE);
     ```
     Expected result: **200**.
   - Every customer has exactly one current row:
     ```sql
     SELECT COUNT(*) FROM dim_customer WHERE IsCurrent = 1;
     ```
     Expected result: **5000**.
   - No customer has more than one current row:
     ```sql
     SELECT CustomerID, COUNT(*) FROM dim_customer WHERE IsCurrent = 1 GROUP BY CustomerID HAVING COUNT(*) > 1;
     ```
     Expected result: **zero rows returned**.
   - Unchanged customers still have exactly one row:
     ```sql
     SELECT CustomerID, COUNT(*) FROM dim_customer
     WHERE CustomerID NOT IN (SELECT CustomerID FROM stg_customer_changes)
     GROUP BY CustomerID
     HAVING COUNT(*) <> 1;
     ```
     Expected result: **zero rows returned**.
10. Capture the output of all four validation queries for your records.
11. Optional, but required if you plan to orchestrate this challenge in Challenge 6: wrap steps 5–6 in a stored procedure so the change-processing logic can be invoked as a single orchestration step later.

    ```sql
    CREATE PROCEDURE usp_process_customer_changes
    AS
    BEGIN
        UPDATE d
        SET IsCurrent = 0,
            ExpiryDate = CAST(GETDATE() AS DATE)
        FROM dim_customer d
        JOIN stg_customer_changes s ON s.CustomerID = d.CustomerID
        WHERE d.IsCurrent = 1
          AND (d.Segment <> s.Segment OR d.Country <> s.Country);

        INSERT INTO dim_customer (CustomerID, CustomerName, Segment, Country, EffectiveDate, ExpiryDate, IsCurrent)
        SELECT s.CustomerID, s.CustomerName, s.Segment, s.Country, CAST(GETDATE() AS DATE), NULL, 1
        FROM stg_customer_changes s
        WHERE NOT EXISTS (
            SELECT 1 FROM dim_customer d
            WHERE d.CustomerID = s.CustomerID
              AND d.IsCurrent = 1
              AND d.Segment = s.Segment
              AND d.Country = s.Country
        );
    END;
    ```

    Run `EXEC usp_process_customer_changes;` once on a fresh load to confirm it reproduces the same counts as steps 5–8 above, then note the procedure name — Challenge 6 references it directly. Because the procedure uses the same idempotent logic as steps 5–6, running it again later (as Challenge 6's pipeline does) against unchanged staging data is safe and affects zero rows.

> [!Tip]
> Microsoft Learn describes the Type 2 pattern as expiring the old version and inserting a new current version rather than updating the descriptive values in place. If your result shows one overwritten row instead of two versions for a changed customer, the dimension is not behaving as Type 2.

## Task 4: Upload your SCD Type 2 evidence for validation

In this task, you will record the dimension counts you just verified into an evidence file and upload it for automated validation.

> [!Important]
> Run these commands from a **PowerShell window on the lab VM**, not from a Fabric notebook or the Warehouse query editor. You are typing in the values you read off the Warehouse query results.

1. On the lab VM, open PowerShell.
2. Fill in the four counts below with the results from Task 3, then run the block:

   ```powershell
   $evidence = [ordered]@{
       dimensionTableName     = 'dim_customer'
       totalRowCount          = 5200   # Task 3, step 7
       currentRowCount        = 5000   # Task 3, step 9 (IsCurrent = 1)
       expiredRowCount        = 200    # Task 3, step 9 (IsCurrent = 0)
       versionedCustomerCount = 200    # Task 3, step 8 (customers with 2 versions)
   }

   New-Item -ItemType Directory -Path 'C:\LabFiles\validation' -Force | Out-Null
   $evidence | ConvertTo-Json | Set-Content -Path 'C:\LabFiles\validation\scd-type2.json' -Encoding utf8
   Get-Content 'C:\LabFiles\validation\scd-type2.json'
   ```

3. Upload the file using the same pattern you used in Challenge 2, Task 5:

   ```powershell
   $envMap = @{}
   Get-Content 'C:\LabFiles\.env' | ForEach-Object {
       if ($_ -match '^(?<k>[A-Z0-9_]+)=(?<v>.*)$') { $envMap[$Matches.k] = $Matches.v }
   }

   if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }

   $resourceGroup = "rg-fabricdataquality-$($envMap['DEPLOYMENT_ID'])"
   $ctx = (Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $envMap['VALIDATION_STORAGE_ACCOUNT']).Context

   Set-AzStorageBlobContent -Context $ctx -Container 'validation' `
       -File 'C:\LabFiles\validation\scd-type2.json' -Blob 'scd-type2.json' -Force | Out-Null

   Get-AzStorageBlob -Context $ctx -Container 'validation' | Select-Object Name
   ```

4. Confirm that `scd-type2.json` appears in the output alongside `cdc-ingestion.json` from Challenge 2.

<validation step="Validate SCD Type 2 behavior in the customer dimension, including current/expired row states."/>

## Summary

In this challenge, you created a Gold customer dimension in Fabric Warehouse, loaded its initial customer records, applied Type 2 change processing, and verified that changed customers now have both historical and current versions. The Warehouse is now ready to support downstream reporting and orchestration steps that depend on preserved customer history.
