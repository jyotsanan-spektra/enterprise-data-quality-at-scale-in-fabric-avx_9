# Challenge 4: Enforce Spark-based data quality gates before Silver promotion

### Estimated Duration: 40 Minutes

## Scenario

The CDC process now lands operational changes in the Bronze layer, but Bronze data is not trusted automatically. Contoso's rule is that curated data reaches Silver only when it passes an explicit set of quality checks — and when it fails, the failure must be visible and the Silver table must be left untouched. Your task is to build that gate.

## Overview

In this challenge you will implement a PySpark quality gate in the **nb_data_quality_gate** notebook that evaluates `bronze_orders_cdc` against five rules, writes `silver_orders` only when the gate passes, and records the outcome. You will then deliberately fail the gate with a defective dataset and prove that Silver was not refreshed.

## Objectives

- Task 1: Prepare the notebook and Lakehouse context
- Task 2: Implement the quality checks and conditional promotion
- Task 3: Trigger the failure path and confirm promotion is blocked
- Task 4: Capture and upload your quality gate evidence

## Task 1: Prepare the notebook and Lakehouse context

Open **nb_data_quality_gate** from Challenge 1 and attach it to the **contoso_medallion_lh** Lakehouse, pinned as the default Lakehouse so Spark SQL and relative table paths resolve correctly.

Confirm you can read `bronze_orders_cdc`, that it carries all 12 expected columns, and note its current row count (approximately **100,350** after Challenge 2).

## Task 2: Implement the quality checks and conditional promotion

Implement five checks against the Bronze orders table. Four of them block promotion; the range check is flag-only and records an issue without stopping the pipeline.

| Rule | Condition | Threshold | Blocks promotion |
| --- | --- | --- | --- |
| Null check | Required columns (`OrderID`, `CustomerID`, `OrderDate`, `Revenue`) must not be null | Null rate ≤ 0.1% | Yes |
| Range check | `Revenue` between 0 and 1,000,000 | Outliers flagged only | No |
| Referential integrity | Every `CustomerID` exists in `dim_customer` | Orphan rate ≤ 0.5% | Yes |
| Freshness | Most recent `OrderDate` is recent | Within 2 days | Yes |
| Schema drift | Column names and count match exactly | 12 columns, exact names | Yes |

Record each rule's outcome, then compute an overall gate status from the four blocking rules. Persist the per-rule results to a Delta table named `quality_gate_log` so the evidence survives outside the notebook's cell output.

Add conditional write logic so that:

- When the gate **passes**, `bronze_orders_cdc` is written to `silver_orders`.
- When the gate **fails**, the notebook **raises an exception** instead of writing.

> [!Important]
> The raised exception is not optional. Challenge 6 runs this notebook from a pipeline activity, and that activity can only detect the failure and trigger its failure branch if the notebook actually fails.

Run the notebook against the current, valid Bronze data. Confirm all four blocking checks pass, that `silver_orders` now exists, and record its row count as your baseline.

## Task 3: Trigger the failure path and confirm promotion is blocked

Use the prepared defect file at `C:\LabFiles\FabricChallengeLab\Samples\quality_defect.csv` — 100 rows in the same 12-column schema, of which exactly **10 carry a blank `OrderID`**, a 10% null rate far above the 0.1% threshold.

Upload it to the Lakehouse **Files** area and run the same null-check logic against it. Confirm that the check reports 10 nulls, that the gate evaluates to failed, and that the notebook raises rather than writing.

Then query `silver_orders` again and confirm its row count is **unchanged** from the baseline you recorded in Task 2. That equality is the proof that a failing gate did not refresh Silver.

> [!Note]
> When calculating the defect null rate, divide by the defect file's own row count (100), not the Bronze table's count. Dividing by the wrong denominator produces a rate below the threshold and the gate will appear to pass.

## Task 4: Capture and upload your quality gate evidence

From a **PowerShell window on the lab VM**, record both runs and upload the evidence. The two Silver row counts must be equal:

```powershell
$envMap = @{}
Get-Content 'C:\LabFiles\.env' | ForEach-Object {
    if ($_ -match '^(?<k>[A-Z0-9_]+)=(?<v>.*)$') { $envMap[$Matches.k] = $Matches.v }
}

$evidence = [ordered]@{
    silverTableName            = 'silver_orders'
    passRunOverallStatus       = 'Passed'
    failRunOverallStatus       = 'Failed'
    failRunFailedRule          = 'null_check'
    silverRowCountAfterPassRun = 100350   # Task 2: your actual observed count
    silverRowCountAfterFailRun = 100350   # Task 3: must match the line above
}

New-Item -ItemType Directory -Path 'C:\LabFiles\validation' -Force | Out-Null
$evidence | ConvertTo-Json | Set-Content 'C:\LabFiles\validation\quality-gate.json' -Encoding utf8

if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }
$ctx = (Get-AzStorageAccount -ResourceGroupName "rg-fabricdataquality-$($envMap['DEPLOYMENT_ID'])" `
        -Name $envMap['VALIDATION_STORAGE_ACCOUNT']).Context
Set-AzStorageBlobContent -Context $ctx -Container $envMap['VALIDATION_CONTAINER'] `
    -File 'C:\LabFiles\validation\quality-gate.json' -Blob 'quality-gate.json' -Force
```

## Success criteria

| Check | Expected result |
| --- | --- |
| Pass run | All four blocking checks pass; `silver_orders` written |
| Quality log | `quality_gate_log` table contains per-rule results |
| Defect detection | 10 null `OrderID` rows detected, ~10% rate |
| Fail run | Notebook raises an exception; overall status Failed |
| Silver protection | `silver_orders` row count unchanged between the two runs |
| Evidence | `quality-gate.json` uploaded to the **validation** container |

<validation step="Spark quality gate behavior"/>

## Summary

In this challenge you implemented a five-rule PySpark quality gate over `bronze_orders_cdc`, promoted data to `silver_orders` only when the blocking rules passed, captured per-rule evidence in the Lakehouse, and proved that a controlled defect blocks promotion and fails the notebook — the behaviour the final orchestration challenge depends on.
