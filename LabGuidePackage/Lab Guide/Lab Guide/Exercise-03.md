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

> [!Important]
> This exercise assumes `customers_baseline.csv` and `customers_changes.csv` already exist under `C:\LabFiles\FabricChallengeLab\Samples`, and that `C:\LabFiles\.env` and a pre-provisioned validation storage account exist for the upload step. In environments deployed with a different bootstrap script, none of that is true. This version adds: PowerShell scripts to generate both CSV files locally (Tasks 2 and 3), a fix for the `IDENTITY(1,1)` syntax that Fabric Warehouse rejects (Task 1), a staging-table pattern for `COPY INTO` since it cannot populate the SCD Type 2 tracking columns directly (Tasks 2 and 3), a callout explaining how to find the workspace ID and Lakehouse ID that `COPY INTO` needs, and a Task 4 upload script that reuses the validation storage account created in Challenge 2 instead of reading it from `.env`.

> [!Tip] Finding your workspace ID and Lakehouse ID for OneLake paths
> Several steps below need a full OneLake file path in the form `https://onelake.dfs.fabric.microsoft.com/<workspace-id>/<lakehouse-id>/Files/<filename>`. Get both IDs from the browser address bar:
> 1. Open **contoso_medallion_lh** in Fabric.
> 2. Look at the URL — it looks like `https://app.fabric.microsoft.com/groups/<workspace-id>/lakehouses/<lakehouse-id>?...`.
> 3. The GUID right after `/groups/` is your **workspace ID**. The GUID right after `/lakehouses/` is your **Lakehouse ID**.
> 4. Alternatively, in the Lakehouse's **Files** area, right-click any uploaded file and select **Copy path** (or check **Properties**) — this gives you the complete OneLake URL with both IDs already filled in, for that specific file.

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
       CustomerKey   BIGINT IDENTITY NOT NULL,
       CustomerID    INT           NOT NULL,
       CustomerName  VARCHAR(200)  NOT NULL,
       Segment       VARCHAR(50)   NOT NULL,
       Country       VARCHAR(50)   NOT NULL,
       EffectiveDate DATE          NOT NULL,
       ExpiryDate    DATE          NULL,
       IsCurrent     BIT           NOT NULL
   );
   ```

   > [!Note]
   > Fabric Data Warehouse's `IDENTITY` columns do not support an explicit seed/increment, unlike SQL Server or Azure SQL Database. Writing `IDENTITY(1,1)` fails with `Msg 24742 ... Identity column 'CustomerKey' does not support specifying SEED or INCREMENT`. Use plain `IDENTITY` with no parentheses — it defaults to seed 1, increment 1 automatically, exactly as shown above.

5. Run the statement, then refresh the Warehouse explorer and confirm `dim_customer` appears with 8 columns:
   - In the left **Explorer** panel, expand **contoso_gold_wh** → **Schemas** (or **Tables**, if your Warehouse view doesn't use schemas).
   - If `dim_customer` doesn't appear immediately, right-click **contoso_gold_wh** (or the Tables folder) and select **Refresh**.
   - Expand **dim_customer** to confirm all 8 columns are listed: CustomerKey, CustomerID, CustomerName, Segment, Country, EffectiveDate, ExpiryDate, IsCurrent.
6. Run `SELECT COUNT(*) FROM dim_customer;` and confirm the result is **0** — the table must be empty before Task 2.
7. Record the deployment context for this lab run using **<inject key="DeploymentID" enableCopy="false"/>** so you can tie your validation evidence to the correct environment.

> [!Important]
> Microsoft Learn documents table creation in Fabric Warehouse through the SQL query editor and notes that `IDENTITY` surrogate keys use the `BIGINT` data type. Keep the dimension in the Warehouse item itself, not in the SQL analytics endpoint of another item.

## Task 2: Load the initial customer dimension rows

In this task, you will populate the first version of the customer dimension so you have a baseline state before any tracked changes occur.

1. `customers_baseline.csv` is not pre-created in this environment. Generate it on the lab VM with the following PowerShell script — it reproduces the same 5,000-row dataset the lab design expects, with `CustomerID`, `CustomerName`, `Segment`, `Country` columns:

   ```powershell
   $segments = @('Enterprise', 'SMB', 'Consumer', 'Public Sector', 'Education')
   $countries = @('United States', 'Canada', 'United Kingdom', 'Germany', 'France', 'Australia', 'India', 'Japan', 'Brazil', 'Mexico')

   $rows = for ($i = 1; $i -le 5000; $i++) {
       [pscustomobject]@{
           CustomerID   = $i
           CustomerName = "Contoso Customer $i"
           Segment      = $segments[$i % $segments.Count]
           Country      = $countries[$i % $countries.Count]
       }
   }

   New-Item -ItemType Directory -Path 'C:\LabFiles\FabricChallengeLab\Samples' -Force | Out-Null
   $rows | Export-Csv -Path 'C:\LabFiles\FabricChallengeLab\Samples\customers_baseline.csv' -NoTypeInformation -Force
   ```

   Then open the resulting file to confirm the four columns and 5,000 rows.
2. Upload `customers_baseline.csv` into your Lakehouse's **Files** area: open **contoso_medallion_lh**, select **Files**, then **Upload > Upload files**, and choose the CSV.
3. Load the file into `dim_customer` using one of the following methods, depending on what your environment supports:
   - **Preferred — COPY INTO via a staging table:** `COPY INTO` maps columns by position and cannot fill in the `EffectiveDate`/`ExpiryDate`/`IsCurrent` tracking columns that don't exist in the source file, so load into a staging table first, then insert from staging into `dim_customer`:

     ```sql
     CREATE TABLE stg_customer_baseline (
         CustomerID   INT           NOT NULL,
         CustomerName VARCHAR(200)  NOT NULL,
         Segment      VARCHAR(50)   NOT NULL,
         Country      VARCHAR(50)   NOT NULL
     );

     COPY INTO stg_customer_baseline
     FROM 'https://onelake.dfs.fabric.microsoft.com/<workspace-id>/<lakehouse-id>/Files/customers_baseline.csv'
     WITH (
         FILE_TYPE = 'CSV',
         FIRSTROW = 2
     );
     ```
     Replace `<workspace-id>` and `<lakehouse-id>` using the Tip above. No `CREDENTIAL` clause is needed — the Warehouse can read directly from a Lakehouse in the same workspace. Verify with `SELECT COUNT(*) FROM stg_customer_baseline;` (expect 5000) before continuing to step 4.
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
4. If you used the staging-table method, insert from staging into `dim_customer`, adding the three SCD Type 2 columns the source file doesn't have:

   ```sql
   INSERT INTO dim_customer (CustomerID, CustomerName, Segment, Country, EffectiveDate, ExpiryDate, IsCurrent)
   SELECT CustomerID, CustomerName, Segment, Country, CAST(GETDATE() AS DATE), NULL, 1
   FROM stg_customer_baseline;
   ```
   Regardless of method, each row must end up with:
   - `CustomerID`, `CustomerName`, `Segment`, `Country` copied directly from the source file
   - `EffectiveDate` set to today's load date
   - `ExpiryDate` set to `NULL`
   - `IsCurrent` set to `1`

   > [!Important]
   > Run this `INSERT` **exactly once**. If you run it again — for example, by re-running an old query tab — you'll get duplicate rows (5,000 × however many times you ran it: 15,000 after two extra runs, and so on). If that happens, reset and reload cleanly:
   > ```sql
   > TRUNCATE TABLE dim_customer;   -- or: DELETE FROM dim_customer;
   > INSERT INTO dim_customer (CustomerID, CustomerName, Segment, Country, EffectiveDate, ExpiryDate, IsCurrent)
   > SELECT CustomerID, CustomerName, Segment, Country, CAST(GETDATE() AS DATE), NULL, 1
   > FROM stg_customer_baseline;
   > ```
5. Run the initial load.
6. Run `SELECT COUNT(*) FROM dim_customer;` and confirm the result is exactly **5000** — matching the row count in `customers_baseline.csv`.
7. Run the following query and confirm it returns **zero rows**, proving each customer currently appears only once:

   ```sql
   SELECT CustomerID, COUNT(*) AS RowCnt
   FROM dim_customer
   GROUP BY CustomerID
   HAVING COUNT(*) > 1;
   ```

   > [!Note]
   > The alias is `RowCnt`, not `RowCount` — `ROWCOUNT` is a reserved T-SQL keyword (used in `SET ROWCOUNT`), and using it unquoted as a column alias fails with `Msg 156 ... Incorrect syntax near the keyword 'RowCount'`. Wrapping it in brackets (`AS [RowCount]`) also works if you prefer to keep the original name.

8. Record **5000** as your baseline row count — you will compare against it after Task 3.

> [!Note]
> An initial SCD Type 2 load behaves like a full current snapshot: all rows are inserted as the first active versions. Versioning behavior becomes visible only when a later change set modifies tracked attributes for an existing customer.

## Task 3: Apply SCD Type 2 changes and validate history

In this task, you will process the prepared customer changes by expiring prior rows and inserting replacement current rows, then verify the final state with SQL queries.

1. `customers_changes.csv` is not pre-created in this environment either. Generate it on the lab VM with the following PowerShell script — it produces 200 rows for `CustomerID` values 25, 50, 75, ... up to 5000 (all of which already exist in your baseline), each with its `Segment` and `Country` shifted to a different value than the baseline row:

   ```powershell
   $segments = @('Enterprise', 'SMB', 'Consumer', 'Public Sector', 'Education')
   $countries = @('United States', 'Canada', 'United Kingdom', 'Germany', 'France', 'Australia', 'India', 'Japan', 'Brazil', 'Mexico')

   $rows = for ($i = 1; $i -le 200; $i++) {
       $customerId = $i * 25
       [pscustomobject]@{
           CustomerID   = $customerId
           CustomerName = "Contoso Customer $customerId"
           Segment      = $segments[($customerId + 1) % $segments.Count]
           Country      = $countries[($customerId + 1) % $countries.Count]
       }
   }

   New-Item -ItemType Directory -Path 'C:\LabFiles\FabricChallengeLab\Samples' -Force | Out-Null
   $rows | Export-Csv -Path 'C:\LabFiles\FabricChallengeLab\Samples\customers_changes.csv' -NoTypeInformation -Force
   ```

   Open the resulting file to confirm it has 200 rows with `CustomerID`, `CustomerName`, `Segment`, `Country` columns, each `CustomerID` already present in `dim_customer` from Task 2.
2. Upload `customers_changes.csv` into the Lakehouse **Files** area alongside the baseline file.
3. Load the change file into a staging table named `stg_customer_changes` in the Warehouse, using the same staging-table `COPY INTO` pattern as Task 2:

   ```sql
   CREATE TABLE stg_customer_changes (
       CustomerID   INT           NOT NULL,
       CustomerName VARCHAR(200)  NOT NULL,
       Segment      VARCHAR(50)   NOT NULL,
       Country      VARCHAR(50)   NOT NULL
   );

   COPY INTO stg_customer_changes
   FROM 'https://onelake.dfs.fabric.microsoft.com/<workspace-id>/<lakehouse-id>/Files/customers_changes.csv'
   WITH (
       FILE_TYPE = 'CSV',
       FIRSTROW = 2
   );
   ```
   Use the same `<workspace-id>` and `<lakehouse-id>` you found for Task 2 — it's the same Lakehouse, only the filename changes.
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

3. Upload the file, reusing the **same** validation storage account you created in Challenge 2, Task 6 — since `C:\LabFiles\.env` does not exist in this environment, this script finds that storage account by its `stfabricval*` naming prefix instead of reading it from a file:

   ```powershell
   $ErrorActionPreference = 'Stop'

   $resourceGroup = 'labvmrg'      # same resource group you used in Challenge 2
   $containerName = 'validation'

   if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }

   $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroup |
       Where-Object { $_.StorageAccountName -like 'stfabricval*' } |
       Select-Object -First 1

   if (-not $storageAccount) {
       throw "Could not find a storage account matching 'stfabricval*' in resource group '$resourceGroup'. Hardcode the exact name you recorded after Challenge 2, Task 6 instead: `$storageAccount = Get-AzStorageAccount -ResourceGroupName '$resourceGroup' -Name '<exact-name>'"
   }

   $ctx = $storageAccount.Context

   Set-AzStorageBlobContent -Context $ctx -Container $containerName `
       -File 'C:\LabFiles\validation\scd-type2.json' -Blob 'scd-type2.json' -Force | Out-Null

   Get-AzStorageBlob -Context $ctx -Container $containerName | Select-Object Name
   ```
   Adjust `$resourceGroup` if it doesn't match your environment. If you still have the exact storage account name that Challenge 2's script printed, hardcode it directly instead of relying on the `-like` lookup, for certainty.

4. Confirm that `scd-type2.json` appears in the output alongside `cdc-ingestion.json` from Challenge 2.

<validation step="Validate SCD Type 2 behavior in the customer dimension, including current/expired row states."/>

## Summary

In this challenge, you created a Gold customer dimension in Fabric Warehouse, loaded its initial customer records, applied Type 2 change processing, and verified that changed customers now have both historical and current versions. The Warehouse is now ready to support downstream reporting and orchestration steps that depend on preserved customer history.
