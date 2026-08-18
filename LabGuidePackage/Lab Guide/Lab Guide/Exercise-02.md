# Challenge 2: Implement CDC ingestion into the Bronze layer

### Estimated Duration: 40 Minutes

## Scenario
In the previous challenge, you confirmed the Microsoft Fabric workspace and medallion-aligned items that will support the rest of the lab. In this challenge, you will configure a Copy job that ingests order data from the `Contoso_Operations` SQL source into the Bronze Lakehouse table `bronze_orders_cdc`. You will first establish the baseline load, then rerun the same design after the prepared source changes are available so you can prove the ingestion pattern captures only incremental changes.

## Overview
In this challenge, you will open the same Fabric workspace and Lakehouse you prepared earlier, create or complete a Copy job, map the `Orders` source into `bronze_orders_cdc`, select incremental copy with CDC behavior, run the first load, and then monitor a second run to verify change capture. You will also record run evidence such as status, rows read, rows written, and the destination table state.

## Objectives
- Task 1: Provision the Contoso_Operations source database manually
- Task 2: Open the Fabric workspace and confirm the Bronze destination
- Task 3: Create and configure the Copy job for CDC-based ingestion
- Task 4: Run the baseline load and verify `bronze_orders_cdc`
- Task 5: Process the prepared changes and prove incremental behavior
- Task 6: Upload your CDC evidence for validation

> [!Important]
> This exercise assumes `C:\LabFiles\.env`, the `Contoso_Operations` Azure SQL database, the `Apply-OrderChanges.ps1` script, and a pre-provisioned validation storage account already exist on the lab VM. In environments deployed with a different bootstrap script, none of that is true — Task 1 below walks through creating and seeding `Contoso_Operations` yourself, Task 5 replaces the missing PowerShell script with an equivalent SQL script you run directly against the database, and Task 6 replaces the `.env`-based storage upload with a self-contained script that creates the validation storage account itself.

## Task 1: Provision the Contoso_Operations source database manually

In this task, you will create the Azure SQL database that later steps ingest from, since it is not pre-provisioned in this environment.

1. Sign in to the Azure portal at <https://portal.azure.com>.
2. Search for **SQL databases** and select **+ Create**.
3. **Basics** tab:
   - **Resource group**: use the existing resource group for this lab (for example **labvmrg**).
   - **Database name**: `Contoso_Operations`
   - **Server**: select **Create new**, then set:
     - **Server name**: a globally unique name, for example `sql-contoso-01`
     - **Location**: match your other lab resources
     - **Authentication method**: **Use SQL authentication**
     - **Server admin login**: `sqladmin`
     - **Password**: choose one and record it — you will reuse it in the Copy job connection
   - **Workload environment**: Development
4. **Compute + storage**: select **Configure database**, choose **Serverless** (General Purpose) or **Basic** (DTU-based), and apply.
5. **Networking** tab: set **Connectivity method** to **Public endpoint**, toggle **Allow Azure services and resources to access this server** to **Yes**, and add your current client IP address so you can run the provisioning script from the portal Query editor.
6. Select **Review + create**, then **Create**, and wait for deployment to finish.
7. Open the new database resource, select **Query editor (preview)**, and sign in with **SQL authentication** using `sqladmin` and your password.
   - If you see **Your IP address isn't allowed to access this server**, select the **Allowlist IP ... on server ...** link in the error message, wait about a minute, and select **Connect** again.
8. Paste the following script into the query pane and select **Run**. It creates the `Orders`, `Customers`, and `Products` tables, seeds ~100,000 / 5,000 / 1,000 rows respectively, and enables CDC on `dbo.Orders`:

   ```sql
   IF OBJECT_ID('dbo.Orders','U') IS NOT NULL DROP TABLE dbo.Orders;
   CREATE TABLE dbo.Orders (
       OrderID         INT NOT NULL PRIMARY KEY,
       CustomerID      INT NOT NULL,
       OrderDate       DATE NOT NULL,
       ShipDate        DATE NULL,
       OrderStatus     VARCHAR(20) NOT NULL,
       ProductID       INT NOT NULL,
       Quantity        INT NOT NULL,
       UnitPrice       DECIMAL(10,2) NOT NULL,
       Discount        DECIMAL(5,2) NOT NULL,
       Revenue         DECIMAL(12,2) NOT NULL,
       ShippingCountry VARCHAR(50) NOT NULL,
       PaymentMethod   VARCHAR(30) NOT NULL
   );

   IF OBJECT_ID('dbo.Customers','U') IS NOT NULL DROP TABLE dbo.Customers;
   CREATE TABLE dbo.Customers (
       CustomerID   INT NOT NULL PRIMARY KEY,
       CustomerName VARCHAR(200) NOT NULL,
       Segment      VARCHAR(50) NOT NULL,
       Country      VARCHAR(50) NOT NULL
   );

   IF OBJECT_ID('dbo.Products','U') IS NOT NULL DROP TABLE dbo.Products;
   CREATE TABLE dbo.Products (
       ProductID   INT NOT NULL PRIMARY KEY,
       ProductName VARCHAR(200) NOT NULL,
       Category    VARCHAR(100) NOT NULL
   );

   ;WITH Tally AS (
       SELECT TOP (1000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
       FROM sys.all_objects
   )
   INSERT INTO dbo.Products (ProductID, ProductName, Category)
   SELECT rn, CONCAT('Product ', rn),
       CASE (rn % 5)
           WHEN 0 THEN 'Hardware' WHEN 1 THEN 'Software' WHEN 2 THEN 'Services'
           WHEN 3 THEN 'Accessories' ELSE 'Support'
       END
   FROM Tally;

   ;WITH Tally AS (
       SELECT TOP (5000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
       FROM sys.all_objects a CROSS JOIN sys.all_objects b
   )
   INSERT INTO dbo.Customers (CustomerID, CustomerName, Segment, Country)
   SELECT
       rn,
       CONCAT('Contoso Customer ', rn),
       CASE (rn % 5)
           WHEN 0 THEN 'Enterprise' WHEN 1 THEN 'SMB' WHEN 2 THEN 'Consumer'
           WHEN 3 THEN 'Public Sector' ELSE 'Education'
       END,
       CASE (rn % 10)
           WHEN 0 THEN 'United States' WHEN 1 THEN 'Canada' WHEN 2 THEN 'United Kingdom'
           WHEN 3 THEN 'Germany' WHEN 4 THEN 'France' WHEN 5 THEN 'Australia'
           WHEN 6 THEN 'India' WHEN 7 THEN 'Japan' WHEN 8 THEN 'Brazil' ELSE 'Mexico'
       END
   FROM Tally;

   ;WITH Tally AS (
       SELECT TOP (100000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
       FROM sys.all_objects a CROSS JOIN sys.all_objects b
   )
   INSERT INTO dbo.Orders (OrderID, CustomerID, OrderDate, ShipDate, OrderStatus, ProductID, Quantity, UnitPrice, Discount, Revenue, ShippingCountry, PaymentMethod)
   SELECT
       rn AS OrderID,
       ((rn - 1) % 5000) + 1 AS CustomerID,
       DATEADD(DAY, -(rn % 400), CAST(GETDATE() AS DATE)) AS OrderDate,
       DATEADD(DAY, -(rn % 400) + 3, CAST(GETDATE() AS DATE)) AS ShipDate,
       CASE (rn % 4) WHEN 0 THEN 'Submitted' WHEN 1 THEN 'Shipped' WHEN 2 THEN 'Delivered' ELSE 'Cancelled' END,
       ((rn - 1) % 1000) + 1 AS ProductID,
       ((rn % 10) + 1) AS Quantity,
       CAST((((rn % 50) + 10) * 1.25) AS DECIMAL(10,2)) AS UnitPrice,
       CAST((rn % 5) AS DECIMAL(5,2)) AS Discount,
       CAST(((((rn % 50) + 10) * 1.25) * ((rn % 10) + 1)) AS DECIMAL(12,2)) AS Revenue,
       CASE (rn % 10)
           WHEN 0 THEN 'United States' WHEN 1 THEN 'Canada' WHEN 2 THEN 'United Kingdom'
           WHEN 3 THEN 'Germany' WHEN 4 THEN 'France' WHEN 5 THEN 'Australia'
           WHEN 6 THEN 'India' WHEN 7 THEN 'Japan' WHEN 8 THEN 'Brazil' ELSE 'Mexico'
       END,
       CASE (rn % 3) WHEN 0 THEN 'CreditCard' WHEN 1 THEN 'PayPal' ELSE 'BankTransfer' END
   FROM Tally;

   IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = DB_NAME() AND is_cdc_enabled = 1)
   BEGIN
       EXEC sys.sp_cdc_enable_db;
   END

   IF NOT EXISTS (SELECT 1 FROM cdc.change_tables WHERE capture_instance = 'dbo_Orders')
   BEGIN
       EXEC sys.sp_cdc_enable_table
           @source_schema = N'dbo',
           @source_name   = N'Orders',
           @role_name     = NULL,
           @supports_net_changes = 1;
   END
   ```

9. Confirm success by running:
   ```sql
   SELECT COUNT(*) FROM dbo.Orders;    -- expect 100000
   SELECT COUNT(*) FROM dbo.Customers; -- expect 5000
   SELECT COUNT(*) FROM dbo.Products;  -- expect 1000
   SELECT is_cdc_enabled FROM sys.databases WHERE name = DB_NAME(); -- expect 1
   ```
   The portal's Query editor only shows the result of the last statement when several `SELECT`s run together — an overall **Succeeded** status with no errors confirms the earlier statements worked too.
10. Record the server name (for example `sql-contoso-01.database.windows.net`), database name (`Contoso_Operations`), and admin login (`sqladmin` / your password) in `C:\LabFiles\fabric-item-names.txt` — you will enter these exact values into the Fabric Copy job connection in Task 3.

## Task 2: Open the Fabric workspace and confirm the Bronze destination
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

## Task 3: Create and configure the Copy job for CDC-based ingestion
In this task, you will create or complete the Copy job that reads from the SQL source and writes to the Bronze table.

1. Return to your Fabric workspace.
2. Open the **orders-to-bronze-cdc** Copy job you created in Challenge 1 rather than creating a new one.
   - If that item does not exist yet, select **+ New item**, search for **Copy job**, select it, enter **orders-to-bronze-cdc** as the name, and then select **Create**.
3. On the **Choose data source** page, select **SQL Server database** as the connector, then under **Connection settings** enter the values from Task 1:
   - **Server**: the server name you recorded, for example `sql-contoso-01.database.windows.net`
   - **Database**: `Contoso_Operations`
   - **Connection**: **Create new connection**
   - **Connection name**: leave the default or rename to `Contoso_Operations`
   - **Data gateway**: `(none)` — this is a public Azure SQL endpoint, no on-premises gateway is needed
   - **Authentication kind**: **Basic**, then enter the `sqladmin` username and password from Task 1
   - Select **Next**.
4. On the **Choose data** page, expand the table list and check **dbo.Orders**. Skip the `cdc.*` system tables shown above it (`cdc.captured_columns`, `cdc.cdc_jobs`, `cdc.change_tables`, `cdc.dbo_Orders_CT`, etc.) — those are SQL Server's internal CDC metadata tables, not the source data. The Copy job reads change data through `dbo.Orders` automatically because CDC is already enabled on it. Select **Next**.
5. Continue to the destination step and select your existing Lakehouse (**contoso_medallion_lh**) from Challenge 1. Select **Tables** as the destination root folder.
6. On **Map to destination**, leave the destination schema as **dbo** and change the destination table name field from **Orders** to **bronze_orders_cdc**. Leave the default column mapping as-is (all 12 columns map straight through). Select **Next**.
7. On the **Settings** page:
   - Confirm **Copy mode** is set to **Incremental copy**.
   - Under **Write method**, select **Merge**, then select **Edit write method** and set **OrderID** as the key column (Merge requires a key column to match existing rows for updates versus new rows for inserts — Fabric shows an error on this page until a key column is set).
   - Leave **Overwrite destination on full load** checked (it only applies to the very first run).
   - This version of the Copy job UI does not show a separate "change-tracking method" dropdown for Azure SQL sources that already have CDC enabled at the table level — Fabric detects the CDC capture instance on `dbo.Orders` automatically once Incremental copy is selected. If your environment's UI does show an explicit tracking-method field, select the CDC-based option (for example **Change Data Capture** or **Native CDC**) rather than a watermark or last-modified-column method.
   - Select **Next**.
8. Review the table mapping and confirm the source still reads `Orders` and the destination still reads `bronze_orders_cdc`.
9. Confirm the destination is still pointed at the same Lakehouse and table name you verified in Task 2.
10. On the summary/**Review + save** page, confirm three specific fields: the copy mode reads **Incremental (CDC)** or an equivalent CDC-aware incremental label, the source reads `Contoso_Operations.Orders`, and the destination table name reads exactly `bronze_orders_cdc`.
11. Select **Save + Run**.

> [!Note]
> In Microsoft Fabric Copy job, incremental copy performs an initial full load on the first successful run. For CDC-enabled database sources, later runs capture inserted and updated changes since the previous successful run. Saving the job may also set up a recurring schedule (for example, "Copy every 15 minutes") — that is expected and does not interfere with the manual runs in Tasks 4 and 5.

## Task 4: Run the baseline load and verify `bronze_orders_cdc`
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

## Task 5: Process the prepared changes and prove incremental behavior
In this task, you will rerun the same job after the prepared source delta is available and confirm that only changes are processed.

1. Apply the prepared source-side update set for `Contoso_Operations.Orders`. Since `C:\LabFiles\FabricChallengeLab\Scripts\Apply-OrderChanges.ps1` does not exist in this environment, run the equivalent SQL directly against the database instead — open the **Query editor (preview)** for `Contoso_Operations` in the Azure portal (or SSMS on the lab VM) and run:

   ```sql
   IF NOT EXISTS (SELECT 1 FROM dbo.Orders WHERE OrderID = 100001)
   BEGIN
       ;WITH Tally AS (
           SELECT TOP (350) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
           FROM sys.all_objects
       )
       INSERT INTO dbo.Orders (OrderID, CustomerID, OrderDate, ShipDate, OrderStatus, ProductID, Quantity, UnitPrice, Discount, Revenue, ShippingCountry, PaymentMethod)
       SELECT
           100000 + rn,
           ((rn - 1) % 5000) + 1,
           CAST(GETDATE() AS DATE),
           DATEADD(DAY, 3, CAST(GETDATE() AS DATE)),
           'Submitted',
           ((rn - 1) % 1000) + 1,
           ((rn % 10) + 1),
           CAST((((rn % 50) + 10) * 1.25) AS DECIMAL(10,2)),
           CAST((rn % 5) AS DECIMAL(5,2)),
           CAST(((((rn % 50) + 10) * 1.25) * ((rn % 10) + 1)) AS DECIMAL(12,2)),
           'United States',
           'CreditCard'
       FROM Tally;
   END

   UPDATE TOP (150) dbo.Orders
   SET OrderStatus = 'Shipped',
       ShipDate = CAST(GETDATE() AS DATE)
   WHERE OrderID BETWEEN 1 AND 150;
   ```

   This inserts 350 new order rows (OrderID 100001-100350) and updates 150 existing rows (OrderID 1-150), for a change set of about 500 rows. Run it only once, and only after the baseline Copy job run in Task 4 has already succeeded.
   - Do not run this in a Fabric notebook cell — notebook cells use Spark SQL, which does not understand this T-SQL syntax and has no connection to the Azure SQL database. Run it against `Contoso_Operations` directly, as shown above.
   - Do not create a new source table or a second destination table.
2. Return to the existing Copy job `orders-to-bronze-cdc`.
3. Select **Run** to execute the same Copy job again (or wait for its schedule to trigger it, if one was created when you saved it).
4. Monitor the run until it reaches **Succeeded**. You can watch progress in the **Results** panel at the bottom of the Copy job screen.
5. Open the run details and compare the second run's metrics to the baseline run from Task 4.
6. Compare **Rows written** between the two runs: the second run's Rows written should be close to **500** — the number of changed rows in the prepared update set — not close to the full baseline count of 100,000. If the second run's Rows written is close to 100,000, the job re-ran a full load instead of an incremental one; revisit the copy mode and write-method settings from Task 3 before continuing.
7. Record the updated **Rows read** and **Rows written** values from the second run.
8. Return to the Lakehouse and reopen `bronze_orders_cdc`.
9. Run `SELECT COUNT(*) FROM bronze_orders_cdc;` again and confirm the new total is approximately **100,350** — the original ~100,000 rows plus the 350 newly inserted rows. The 150 updated rows (OrderID 1-150) do not add to the row count; Merge modifies those rows in place, it does not duplicate them. (Do not expect ~100,500 here — that number would only be correct if all 500 changed rows were inserts, but 150 of them are updates to already-existing OrderIDs.)
10. Compare the first-run evidence and second-run evidence in your notes. Your proof should show that the baseline run established the initial snapshot of ~100,000 rows and the second run added only the 350 net-new rows (plus updated 150 existing rows in place) captured after the first successful run.
11. Keep your evidence available for validation, including the two run outcomes and the post-run table state.

## Task 6: Upload your CDC evidence for validation

In this task, you will record the numbers you just observed in Fabric into an evidence file and upload it, so the lab's automated validation can confirm your work.

> [!Important]
> Run every command in this task from a **PowerShell window on the lab VM**, not from a Fabric notebook cell. Fabric notebooks execute on remote Spark compute and cannot write to this VM's `C:\LabFiles` folder. You are typing in the values you read off the Fabric screens.

1. On the lab VM, open PowerShell.
2. Fill in the values below with the numbers you actually recorded in Tasks 4 and 5, then run the block to create the evidence file:

   ```powershell
   $evidence = [ordered]@{
       tableName               = 'bronze_orders_cdc'
       copyMode                = 'Incremental (CDC)'
       baselineRowCount        = 100000   # Task 4: row count after the first run
       postIncrementalRowCount = 100350   # Task 5, step 9: row count after the second run
       incrementalRowsWritten  = 500      # Task 5, step 6: Rows written on the second run (350 inserts + 150 updates)
   }

   New-Item -ItemType Directory -Path 'C:\LabFiles\validation' -Force | Out-Null
   $evidence | ConvertTo-Json | Set-Content -Path 'C:\LabFiles\validation\cdc-ingestion.json' -Encoding utf8
   Get-Content 'C:\LabFiles\validation\cdc-ingestion.json'
   ```

3. Upload the evidence file to a validation storage account. Since `C:\LabFiles\.env` and a pre-provisioned validation storage account do not exist in this environment, the script below creates the storage account itself (if it does not already exist) instead of reading connection details from `.env`:

   ```powershell
   $ErrorActionPreference = 'Stop'

   # Adjust these to match your environment: resourceGroup should match the resource group
   # shown on your Azure SQL database's Overview page (for example "labvmrg"). storageAccountName
   # must be globally unique (lowercase letters/numbers only, 3-24 characters).
   $resourceGroup      = 'labvmrg'
   $storageAccountName = 'stfabricval' + (Get-Random -Minimum 10000 -Maximum 99999)
   $location           = 'westus2'   # match the region your other lab resources are in
   $containerName      = 'validation'

   foreach ($module in @('Az.Accounts', 'Az.Storage')) {
       if (-not (Get-Module -ListAvailable -Name $module)) {
           Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
       }
   }

   # Sign in with the same lab credentials you used for the Azure portal, if you are not already
   # signed in. Choose "Work or school account" at the sign-in prompt — lab accounts are
   # organizational (Microsoft Entra ID) accounts, not personal Microsoft accounts.
   if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }

   $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName -ErrorAction SilentlyContinue
   if (-not $storageAccount) {
       Write-Host "Creating storage account '$storageAccountName' in resource group '$resourceGroup'..."
       $storageAccount = New-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName `
           -Location $location -SkuName Standard_LRS -Kind StorageV2
   }

   $ctx = $storageAccount.Context

   if (-not (Get-AzStorageContainer -Context $ctx -Name $containerName -ErrorAction SilentlyContinue)) {
       New-AzStorageContainer -Context $ctx -Name $containerName -Permission Off | Out-Null
   }

   Set-AzStorageBlobContent -Context $ctx -Container $containerName `
       -File 'C:\LabFiles\validation\cdc-ingestion.json' -Blob 'cdc-ingestion.json' -Force | Out-Null

   Get-AzStorageBlob -Context $ctx -Container $containerName | Select-Object Name

   Write-Host "Validation storage account: $storageAccountName (record this — you will reuse the same account and container in Challenges 3-6)"
   ```

   Double-check `$resourceGroup` and `$location` before running — set them to match your actual environment if `labvmrg`/`westus2` are not correct.
4. Confirm that `cdc-ingestion.json` appears in the output, and note the printed storage account name.
5. Record the storage account name and container name (`validation`) in `C:\LabFiles\fabric-item-names.txt` so you can reuse the exact same storage account in later challenges instead of creating a new one each time.

> [!Note]
> You will reuse this same storage account and container in Challenges 3, 4, 5, and 6 — only the local file name and blob name change each time. Reuse the `$storageAccountName` value this script printed; do not generate a new random name in later challenges.

<validation step="CDC ingestion outcomes"/>

## Summary
In this challenge, you configured a Microsoft Fabric Copy job to ingest `Contoso_Operations.Orders` into the Bronze Lakehouse table `bronze_orders_cdc`. You ran the initial load, monitored the Copy job metrics, and then reran the same ingestion path after prepared source changes were available to demonstrate CDC-driven incremental behavior in the Bronze layer.
