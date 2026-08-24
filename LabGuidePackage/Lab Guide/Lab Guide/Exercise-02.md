# Challenge 2: Implement CDC ingestion into the Bronze layer

### Estimated Duration: 40 Minutes

## Scenario

Contoso's operational order data lives in the `Contoso_Operations` SQL database, which has change data capture enabled on `dbo.Orders`. The Bronze layer must land those operational changes without re-copying the entire table on every run. Your task is to build the ingestion path that captures the initial snapshot once, then captures only what changed afterwards.

## Overview

In this challenge you will configure the Copy job you created in Challenge 1 to ingest `Contoso_Operations.Orders` into the Bronze Lakehouse table `bronze_orders_cdc`. You will run a baseline load, apply a prepared change set at the source, run the job a second time, and prove from the run metrics that only the changed rows were processed.

## Objectives

- Task 1: Configure the Copy job for CDC-based ingestion
- Task 2: Run the baseline load and verify the Bronze table
- Task 3: Apply the source change set and prove incremental behaviour
- Task 4: Capture and upload your CDC evidence

## Task 1: Configure the Copy job for CDC-based ingestion

The `Contoso_Operations` Azure SQL database is pre-provisioned with 100,000 `Orders` rows, 5,000 `Customers`, and 1,000 `Products`, and CDC is already enabled on `dbo.Orders`. Its server name, database name, and admin credentials are in `C:\LabFiles\.env` on the lab VM.

Open the **orders-to-bronze-cdc** Copy job from Challenge 1 and configure it to move order data into Bronze:

- **Source** — a SQL connection to the `Contoso_Operations` database, selecting the `Orders` table. If no connection exists yet, create one using the credentials from `.env`.
- **Destination** — your **contoso_medallion_lh** Lakehouse, into the **Tables** area, with the destination table named exactly `bronze_orders_cdc`.
- **Copy mode** — **Incremental copy**, with a CDC-based change-tracking method.

> [!Important]
> The tracking method must be CDC-based (for example **Change Data Capture** or **Native CDC**), not a watermark or last-modified-column method. A watermark method means the wrong mode was selected, and Task 3 will not produce the incremental result the validation expects.

Save and run the job.

## Task 2: Run the baseline load and verify the Bronze table

Monitor the first run to completion and confirm it established the initial snapshot.

Confirm that `bronze_orders_cdc` exists in the Lakehouse as a Delta table, that it carries the 12-column `Orders` schema (OrderID, CustomerID, OrderDate, ShipDate, OrderStatus, ProductID, Quantity, UnitPrice, Discount, Revenue, ShippingCountry, PaymentMethod), and that it holds approximately **100,000** rows.

Record the **Rows read** and **Rows written** metrics and the resulting table row count — you will need them in Task 4.

> [!Note]
> In Fabric Copy job, incremental copy performs a full load on the first successful run. Later runs capture only inserts and updates recorded since the previous successful run.

## Task 3: Apply the source change set and prove incremental behaviour

Apply the prepared change set to the source by running **`C:\LabFiles\FabricChallengeLab\Scripts\Apply-OrderChanges.ps1`** from a PowerShell window on the lab VM. It inserts 350 new orders and updates 150 existing ones — a change set of about **500 rows**. Run it once only.

Run the **same** Copy job again and compare the second run's metrics against the baseline. The proof of correct CDC behaviour is that the second run wrote only the changed rows, not the full table.

Record the second run's **Rows written** and the new table row count.

> [!Important]
> If the second run's Rows written is close to 100,000, the job performed another full load. Revisit the copy mode and change-tracking settings in Task 1 before continuing.

## Task 4: Capture and upload your CDC evidence

Record the numbers you observed in Fabric into an evidence file and upload it to the lab's validation storage account, so the automated validation can confirm your work.

> [!Important]
> Run these commands from a **PowerShell window on the lab VM**, not from a Fabric notebook cell. Notebooks run on remote Spark compute and cannot write to this VM's file system. You are typing in the values you read off the Fabric screens.

```powershell
$envMap = @{}
Get-Content 'C:\LabFiles\.env' | ForEach-Object {
    if ($_ -match '^(?<k>[A-Z0-9_]+)=(?<v>.*)$') { $envMap[$Matches.k] = $Matches.v }
}

$evidence = [ordered]@{
    tableName               = 'bronze_orders_cdc'
    copyMode                = 'Incremental (CDC)'
    baselineRowCount        = 100000   # Task 2: row count after the first run
    postIncrementalRowCount = 100350   # Task 3: row count after the second run
    incrementalRowsWritten  = 500      # Task 3: Rows written on the second run
}

New-Item -ItemType Directory -Path 'C:\LabFiles\validation' -Force | Out-Null
$evidence | ConvertTo-Json | Set-Content 'C:\LabFiles\validation\cdc-ingestion.json' -Encoding utf8

if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }
$ctx = (Get-AzStorageAccount -ResourceGroupName "rg-fabricdataquality-$($envMap['DEPLOYMENT_ID'])" `
        -Name $envMap['VALIDATION_STORAGE_ACCOUNT']).Context
Set-AzStorageBlobContent -Context $ctx -Container $envMap['VALIDATION_CONTAINER'] `
    -File 'C:\LabFiles\validation\cdc-ingestion.json' -Blob 'cdc-ingestion.json' -Force
```

Replace the example numbers with the values you actually recorded. The validation compares them against the live Fabric table, so invented values will not pass.

## Success criteria

| Check | Expected result |
| --- | --- |
| Bronze table | `bronze_orders_cdc` exists in `contoso_medallion_lh` as a Delta table |
| Schema | 12 columns matching the `Orders` schema |
| Baseline run | Rows read and Rows written approximately **100,000** |
| Second run | Rows written approximately **500**, not ~100,000 |
| Final row count | Approximately **100,350** |
| Evidence | `cdc-ingestion.json` uploaded to the **validation** container |

<validation step="CDC ingestion outcomes"/>

## Summary

In this challenge you configured a Fabric Copy job to ingest `Contoso_Operations.Orders` into the Bronze Lakehouse table `bronze_orders_cdc`, established a baseline snapshot, and proved through run metrics that a second run captured only the prepared change set. The Bronze layer now reflects CDC-driven incremental ingestion.
