# Challenge 6: Orchestrate the end-to-end medallion pipeline

### Estimated Duration: 45 Minutes

## Scenario

Every component of the Contoso medallion solution now works on its own. The final requirement is to run them as one controlled sequence — ingestion, then quality validation, then Gold loading — and to prove the orchestration behaves correctly in both directions: it completes when the data is clean, and it blocks downstream processing when the quality gate fails.

## Overview

In this challenge you will configure the **contoso-medallion-orchestration** pipeline to run the items you built earlier in the correct order, with retry behaviour and a failure branch. You will then run it twice — once on clean data and once with a deliberate defect — and capture the run-state evidence for both paths.

## Objectives

- Task 1: Build the orchestration pipeline
- Task 2: Configure dependencies, retries, and failure handling
- Task 3: Run the success and failure paths
- Task 4: Capture and upload your orchestration evidence

## Task 1: Build the orchestration pipeline

Confirm the items from earlier challenges are present, then open **contoso-medallion-orchestration** from Challenge 1 and add three activities:

| Activity name | Runs | From |
| --- | --- | --- |
| **Bronze CDC ingestion** | The **orders-to-bronze-cdc** Copy job | Challenge 2 |
| **Bronze to Silver quality gate** | The **nb_data_quality_gate** notebook | Challenge 4 |
| **Gold dimension load** | `EXEC usp_process_customer_changes;` against **contoso_gold_wh** | Challenge 3 |

Use the activity type that invokes the existing Copy job item rather than rebuilding a Copy data activity from scratch, point the notebook activity at the **contoso_medallion_lh** Lakehouse context, and configure the Gold activity's connection using the SQL connection string you saved in Challenge 1.

Chain the three activities with **success** dependencies, so each runs only when the previous one succeeds.

## Task 2: Configure dependencies, retries, and failure handling

Make the orchestration resilient to transient faults while ensuring genuine data-quality failures still stop the flow:

- On **Bronze to Silver quality gate**, enable retries with a retry count of **1** and a retry interval of **30** seconds.
- Confirm **Gold dimension load** runs only on the success of the quality gate.
- Add a **failure branch** from the quality gate to an activity named **Quality failure evidence** that records a clear failure outcome — a **Fail** activity with a message such as `Quality gate failed. Downstream Gold processing was blocked.`

> [!Important]
> Do not configure retries in a way that masks bad-data failures. The notebook raises an exception on a failed gate, so a retry against the same bad data will fail again for the same reason — that is the correct, expected behaviour.

## Task 3: Run the success and failure paths

**Success path.** With Bronze in its clean state, run the pipeline and confirm all three activities complete successfully. Review each activity's input, output, and status in the run history. Confirm `dim_customer` still reflects correct SCD Type 2 processing — because `usp_process_customer_changes` is re-runnable, the count stays at **5200** rather than creating duplicate versions.

**Failure path.** Reintroduce the defect so the notebook fails during an automated run. The pipeline runs the whole notebook non-interactively against `bronze_orders_cdc`, so the 10 defective rows from `quality_defect.csv` must be appended into the Bronze table itself — casting each column to the Bronze table's own schema so the append cannot fail on a type mismatch. Confirm `bronze_orders_cdc` then has 10 rows with a null `OrderID`.

Run the pipeline again and confirm:

- The quality gate activity **failed**, and the run history shows it was attempted **twice** (the configured retry).
- The **Quality failure evidence** branch executed and the run is visibly failed.
- **Gold dimension load** did **not** complete successfully.

> [!Note]
> Appending the defect rows permanently modifies `bronze_orders_cdc`. Treat it as a one-time manual step and remove the cell afterwards, so a later pipeline run does not append more defective rows each time it executes.

## Task 4: Capture and upload your orchestration evidence

From a **PowerShell window on the lab VM**, record both runs and upload the two evidence files. The failure evidence must show a non-success status for the Gold activity, since a blocked gate has to stop downstream processing:

```powershell
$envMap = @{}
Get-Content 'C:\LabFiles\.env' | ForEach-Object {
    if ($_ -match '^(?<k>[A-Z0-9_]+)=(?<v>.*)$') { $envMap[$Matches.k] = $Matches.v }
}
New-Item -ItemType Directory -Path 'C:\LabFiles\validation' -Force | Out-Null

[ordered]@{
    pipelineName      = 'contoso-medallion-orchestration'
    pipelineRunStatus = 'Succeeded'
    activities = @(
        [ordered]@{ activityName = 'Bronze CDC ingestion';          status = 'Succeeded' }
        [ordered]@{ activityName = 'Bronze to Silver quality gate'; status = 'Succeeded' }
        [ordered]@{ activityName = 'Gold dimension load';           status = 'Succeeded' }
    )
} | ConvertTo-Json -Depth 5 | Set-Content 'C:\LabFiles\validation\pipeline-success.json' -Encoding utf8

[ordered]@{
    pipelineName      = 'contoso-medallion-orchestration'
    pipelineRunStatus = 'Failed'
    activities = @(
        [ordered]@{ activityName = 'Bronze CDC ingestion';          status = 'Succeeded' }
        [ordered]@{ activityName = 'Bronze to Silver quality gate'; status = 'Failed' }
        [ordered]@{ activityName = 'Gold dimension load';           status = 'Skipped' }
    )
} | ConvertTo-Json -Depth 5 | Set-Content 'C:\LabFiles\validation\pipeline-failure.json' -Encoding utf8

if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }
$ctx = (Get-AzStorageAccount -ResourceGroupName "rg-fabricdataquality-$($envMap['DEPLOYMENT_ID'])" `
        -Name $envMap['VALIDATION_STORAGE_ACCOUNT']).Context

@('pipeline-success.json','pipeline-failure.json') | ForEach-Object {
    Set-AzStorageBlobContent -Context $ctx -Container $envMap['VALIDATION_CONTAINER'] `
        -File "C:\LabFiles\validation\$_" -Blob $_ -Force | Out-Null
}
```

Record the deployment context for this lab run: **Deployment ID: <inject key="DeploymentID" enableCopy="false"/>**.

## Success criteria

| Check | Expected result |
| --- | --- |
| Pipeline | Three activities chained with success dependencies |
| Retry | Quality gate configured with 1 retry, 30-second interval |
| Failure branch | **Quality failure evidence** activity present |
| Success run | All three activities succeed; `dim_customer` remains at **5200** |
| Failure run | Quality gate failed and retried once; Gold load did not succeed |
| Evidence | `pipeline-success.json` and `pipeline-failure.json` uploaded to the **validation** container |

<validation step="Validate orchestration success/failure run states and dependency behavior using internal pipeline evidence."/>

## Summary

In this challenge you orchestrated the Bronze, Silver, and Gold flow into a single Fabric pipeline built from the items you created earlier, configured retry-aware handling and a failure branch, and proved both directions of the design — a clean run that completes end to end, and a quality failure that blocks downstream Gold processing.
