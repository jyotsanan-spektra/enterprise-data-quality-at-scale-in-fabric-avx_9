# Challenge 3: Implement SCD Type 2 history in the Gold Warehouse

### Estimated Duration: 40 Minutes

## Scenario

The Contoso operations team needs the Gold layer to preserve customer attribute history rather than overwriting prior values. When a customer moves segment or country, the business must still be able to report on what that customer looked like before the change. Your task is to build a customer dimension that keeps both the historical and the current version of every changed record.

## Overview

In this challenge you will build a `dim_customer` table in the **contoso_gold_wh** Warehouse with surrogate-key and history-tracking columns, load a baseline of 5,000 customers, process a change set of 200 customers, and prove that each changed customer ends up with one expired row and one current row.

## Objectives

- Task 1: Create the customer dimension table
- Task 2: Load the baseline customer records
- Task 3: Apply SCD Type 2 changes and validate the history
- Task 4: Capture and upload your SCD Type 2 evidence

## Task 1: Create the customer dimension table

In the **contoso_gold_wh** Warehouse, create a `dim_customer` table that carries the four source attributes plus the columns required for Type 2 history tracking:

| Column | Type | Purpose |
| --- | --- | --- |
| `CustomerKey` | `BIGINT IDENTITY(1,1)` | Surrogate key |
| `CustomerID` | `INT` | Natural key from the source |
| `CustomerName`, `Segment`, `Country` | `VARCHAR` | Tracked attributes |
| `EffectiveDate` | `DATE` | When this version became current |
| `ExpiryDate` | `DATE NULL` | When this version was superseded |
| `IsCurrent` | `BIT` | Marks the active version |

Confirm the table is created and empty before continuing.

> [!Important]
> Build the dimension inside the Warehouse item itself, not in the SQL analytics endpoint of another item. Fabric Warehouse uses `BIGINT` for `IDENTITY` surrogate keys.

## Task 2: Load the baseline customer records

Load the 5,000 customers from `C:\LabFiles\FabricChallengeLab\Samples\customers_baseline.csv` into `dim_customer`. The file carries `CustomerID`, `CustomerName`, `Segment`, and `Country`; you supply the tracking columns.

Every baseline row must be inserted as a first, active version: `EffectiveDate` set to today, `ExpiryDate` null, and `IsCurrent` set to `1`.

Use whichever load path your environment supports — `COPY INTO` from the file's OneLake path after uploading it to the Lakehouse **Files** area, or a Spark notebook that writes to the Warehouse through the JDBC connection string you saved in Challenge 1.

Confirm the table holds exactly **5000** rows and that no `CustomerID` appears more than once.

> [!Note]
> An initial Type 2 load behaves like a full current snapshot. Versioning only becomes visible when a later change set modifies tracked attributes.

## Task 3: Apply SCD Type 2 changes and validate the history

Load the 200 changed customers from `C:\LabFiles\FabricChallengeLab\Samples\customers_changes.csv` into a staging table named `stg_customer_changes`, then process them using the Type 2 pattern:

1. **Expire** the current row of every customer whose staged `Segment` or `Country` differs from what is currently stored — set `IsCurrent = 0` and stamp `ExpiryDate` with today's date.
2. **Insert** a new current row for each of those customers using the staged values, with `ExpiryDate` null and `IsCurrent = 1`.

Match on the changed attributes rather than blindly on `CustomerID`, so the logic can run more than once without creating duplicate versions. Challenge 6 invokes this same logic through a pipeline, so it must be safe to re-run.

Wrap both statements in a stored procedure named **`usp_process_customer_changes`** — Challenge 6 calls it directly by that name.

Validate the result with SQL:

| Query | Expected result |
| --- | --- |
| Total rows in `dim_customer` | **5200** |
| Customers with exactly 2 versions | **200** |
| Rows where `IsCurrent = 1` | **5000** |
| Rows where `IsCurrent = 0` and `ExpiryDate` is today | **200** |
| Any customer with more than one current row | **zero rows** |
| Unchanged customers with more than one row | **zero rows** |

> [!Tip]
> Type 2 means expiring the old version and inserting a new one. If a changed customer shows a single overwritten row instead of two versions, the dimension is behaving as Type 1 and will not pass validation.

## Task 4: Capture and upload your SCD Type 2 evidence

From a **PowerShell window on the lab VM**, record the counts you validated and upload them:

```powershell
$envMap = @{}
Get-Content 'C:\LabFiles\.env' | ForEach-Object {
    if ($_ -match '^(?<k>[A-Z0-9_]+)=(?<v>.*)$') { $envMap[$Matches.k] = $Matches.v }
}

$evidence = [ordered]@{
    dimensionTableName     = 'dim_customer'
    totalRowCount          = 5200
    currentRowCount        = 5000
    expiredRowCount        = 200
    versionedCustomerCount = 200
}

New-Item -ItemType Directory -Path 'C:\LabFiles\validation' -Force | Out-Null
$evidence | ConvertTo-Json | Set-Content 'C:\LabFiles\validation\scd-type2.json' -Encoding utf8

if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }
$ctx = (Get-AzStorageAccount -ResourceGroupName "rg-fabricdataquality-$($envMap['DEPLOYMENT_ID'])" `
        -Name $envMap['VALIDATION_STORAGE_ACCOUNT']).Context
Set-AzStorageBlobContent -Context $ctx -Container $envMap['VALIDATION_CONTAINER'] `
    -File 'C:\LabFiles\validation\scd-type2.json' -Blob 'scd-type2.json' -Force
```

## Success criteria

| Check | Expected result |
| --- | --- |
| Dimension table | `dim_customer` exists in `contoso_gold_wh` with the tracking columns |
| Baseline load | 5,000 rows, one per customer |
| After change processing | **5200** total rows |
| Versioned customers | **200** customers with both an expired and a current row |
| Current rows | **5000**, exactly one per customer |
| Stored procedure | `usp_process_customer_changes` exists and is safe to re-run |
| Evidence | `scd-type2.json` uploaded to the **validation** container |

<validation step="Validate SCD Type 2 behavior in the customer dimension, including current/expired row states."/>

## Summary

In this challenge you built a Gold customer dimension in Fabric Warehouse, loaded its baseline records, applied Type 2 change processing through a re-runnable stored procedure, and verified that changed customers now carry both historical and current versions.
