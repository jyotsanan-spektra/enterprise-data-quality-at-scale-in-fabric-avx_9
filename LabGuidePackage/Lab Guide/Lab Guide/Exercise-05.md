# Challenge 5: Audit, recover, and protect data with Delta Lake time travel

### Estimated Duration: 40 Minutes

## Scenario

A faulty upstream job has corrupted revenue values in the `silver_orders` Delta table. Before Contoso can trust the medallion pipeline in production, the team must be able to prove what went wrong, identify the last version of the data that was still correct, and return the table to that state without losing the audit trail of the incident itself.

## Overview

In this challenge you will reproduce the incident in a controlled way, use Delta Lake history and time travel to identify the last known good version, restore `silver_orders` to it, and create a shallow clone as a short-lived recovery backup. You will then upload three evidence files describing the incident and the recovery.

## Objectives

- Task 1: Reproduce the controlled corruption incident
- Task 2: Identify the last known good version
- Task 3: Restore the table and verify recovery
- Task 4: Create a backup clone and upload your recovery evidence

## Task 1: Reproduce the controlled corruption incident

Open a notebook attached to the Lakehouse that contains `silver_orders`. If you do not already have one for Silver-layer work, create **`silver_recovery_investigation`**.

First confirm the table is healthy: note its row count and confirm the number of rows with `Revenue = 0` is **0**.

Then simulate the faulty job with a Delta `MERGE` that sets `Revenue` to 0 for exactly **1,000 orders** (`OrderID` 1 through 1000). Confirm afterwards that the zero-revenue count is now **1000** and the total row count is unchanged.

> [!Important]
> The `MERGE` is recorded as its own version in the Delta transaction log. That is what makes the recovery workflow in the following tasks possible — the previous healthy version is still retained and readable.

> [!Note]
> If `silver_orders` does not exist, complete Challenge 4 first — the quality gate must write the Silver table before you can recover it.

## Task 2: Identify the last known good version

Inspect the Delta history for `silver_orders` and find the `MERGE` operation you just performed. Record its version number as the **corrupted version**, and the version immediately before it as the **last known good version**.

Do not rely on the operation type alone — confirm the boundary against the data itself by counting zero-revenue rows at each candidate version using time travel:

| Version | Expected zero-revenue rows |
| --- | --- |
| Last known good | **0** |
| Corrupted | **1000** |

If neither candidate shows the spike, check one version earlier and one later until you find the boundary where the count jumps. Record both version numbers — you will need them in Tasks 3 and 4.

> [!Tip]
> Delta Lake time travel is read-only. Use it to verify the historical snapshot *before* running a restore, so you do not restore to the wrong version just because its operation type looked right.

## Task 3: Restore the table and verify recovery

Restore `silver_orders` to the last known good version you confirmed, then verify the recovery on three points:

- The zero-revenue count is back to **0**.
- A row-level comparison between the restored table and the good version shows a difference count of **0**.
- The Delta history now contains a new `RESTORE` entry, and the earlier `MERGE` entry is still visible below it.

Record the restored row count.

> [!Note]
> `RESTORE` creates a new current version that points back to the selected historical state. It does not erase the history of the corruption event — the audit trail is preserved.

## Task 4: Create a backup clone and upload your recovery evidence

Create a shallow clone of the restored table named **`silver_orders_backup`** and confirm its row count matches the restored table.

> [!Important]
> Fabric supports `SHALLOW CLONE` but not deep clone. A shallow clone is fast and storage-efficient because it references the source table's OneLake files — which also means it is suitable for short-lived recovery testing, not long-term archival, since later file cleanup can break the dependency.

From a **PowerShell window on the lab VM**, create and upload all three evidence files, using the version numbers and row counts you actually recorded:

```powershell
$envMap = @{}
Get-Content 'C:\LabFiles\.env' | ForEach-Object {
    if ($_ -match '^(?<k>[A-Z0-9_]+)=(?<v>.*)$') { $envMap[$Matches.k] = $Matches.v }
}

$corruptedVersion = 5        # Task 2: your actual corrupted version number
$goodVersion      = 4        # Task 2: your actual last-known-good version number
$restoredRowCount = 100350   # Task 3: your actual restored row count
$cloneRowCount    = 100350   # Task 4: your actual clone row count

New-Item -ItemType Directory -Path 'C:\LabFiles\validation' -Force | Out-Null

[ordered]@{ tableName = 'silver_orders'; corruptedVersion = $corruptedVersion; lastKnownGoodVersion = $goodVersion } |
    ConvertTo-Json | Set-Content 'C:\LabFiles\validation\silver-recovery-history.json' -Encoding utf8

[ordered]@{ tableName = 'silver_orders'; restoredToVersion = $goodVersion; restoredRowCount = $restoredRowCount } |
    ConvertTo-Json | Set-Content 'C:\LabFiles\validation\silver-recovery-restore.json' -Encoding utf8

[ordered]@{ sourceTable = 'silver_orders'; cloneTable = 'silver_orders_backup'; cloneType = 'shallow'; cloneRowCount = $cloneRowCount } |
    ConvertTo-Json | Set-Content 'C:\LabFiles\validation\silver-recovery-clone.json' -Encoding utf8

if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }
$ctx = (Get-AzStorageAccount -ResourceGroupName "rg-fabricdataquality-$($envMap['DEPLOYMENT_ID'])" `
        -Name $envMap['VALIDATION_STORAGE_ACCOUNT']).Context

@('silver-recovery-history.json','silver-recovery-restore.json','silver-recovery-clone.json') | ForEach-Object {
    Set-AzStorageBlobContent -Context $ctx -Container $envMap['VALIDATION_CONTAINER'] `
        -File "C:\LabFiles\validation\$_" -Blob $_ -Force | Out-Null
}
```

## Success criteria

| Check | Expected result |
| --- | --- |
| Incident | 1,000 rows with `Revenue = 0` at the corrupted version |
| History | A `MERGE` entry identifying the corruption, with a good version before it |
| Restore | Zero-revenue count back to **0**; difference count **0** vs the good version |
| Audit trail | `RESTORE` entry added; the `MERGE` entry still visible |
| Backup | `silver_orders_backup` exists as a shallow clone with a matching row count |
| Evidence | All three `silver-recovery-*.json` files uploaded to the **validation** container |

<validation step="Validate Delta Lake history investigation, restore, and backup clone evidence for silver_orders."/>

## Summary

In this challenge you reproduced a controlled corruption event, used Delta history and time travel to prove which version was still correct, restored `silver_orders` to that version while preserving the incident in the audit trail, and created a shallow clone backup — establishing the Silver-layer recovery controls the final challenge relies on.
