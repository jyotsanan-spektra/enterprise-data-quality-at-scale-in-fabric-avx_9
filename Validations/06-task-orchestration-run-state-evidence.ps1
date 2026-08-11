using namespace System.Net

# Note: $sub (subscription id) and $DID (deployment id) are injected by the platform.
$rg = "rg-fabricdataquality-$DID"
$count = 0
$found = $false

function Get-ValidationBlobContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$BlobName
    )

    $storageAccount = Get-AzStorageAccount -ResourceGroupName $rg -Name $StorageAccountName -ErrorAction Stop
    $ctx = $storageAccount.Context
    $blob = Get-AzStorageBlob -Context $ctx -Container $ContainerName -Blob $BlobName -ErrorAction SilentlyContinue

    if (-not $blob) {
        return $null
    }

    $tempFile = Join-Path -Path $env:TEMP -ChildPath ([System.Guid]::NewGuid().ToString() + '.json')
    Get-AzStorageBlobContent -Context $ctx -Container $ContainerName -Blob $BlobName -Destination $tempFile -Force -ErrorAction Stop | Out-Null
    $content = Get-Content -Path $tempFile -Raw -ErrorAction Stop
    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    return $content
}

do {
    $count = $count + 1
    try {
        Set-AzContext -Subscription $sub -ErrorAction Stop

        $storage = Get-AzStorageAccount -ResourceGroupName $rg -Name ("stfabricval" + $DID.Replace('-', '').Substring(0, 12)) -ErrorAction SilentlyContinue
        if (-not $storage) {
            $storage = Get-AzStorageAccount -ResourceGroupName $rg -ErrorAction SilentlyContinue |
                Where-Object { $_.StorageAccountName -like 'stfabricval*' } |
                Select-Object -First 1
        }

        if ($storage) {
            $successBlobContent = Get-ValidationBlobContent -StorageAccountName $storage.StorageAccountName -ContainerName 'validation' -BlobName 'pipeline-success.json'
            $failureBlobContent = Get-ValidationBlobContent -StorageAccountName $storage.StorageAccountName -ContainerName 'validation' -BlobName 'pipeline-failure.json'

            if ($successBlobContent -and $failureBlobContent) {
                $successEvidence = $successBlobContent | ConvertFrom-Json -ErrorAction Stop
                $failureEvidence = $failureBlobContent | ConvertFrom-Json -ErrorAction Stop

                $hasSuccessStatus = $successEvidence.pipelineRunStatus -match 'Completed|Succeeded|Success'
                $hasFailureStatus = $failureEvidence.pipelineRunStatus -match 'Failed|Failure'
                $successActivities = @($successEvidence.activities)
                $failureActivities = @($failureEvidence.activities)

                $qualityActivitySuccess = $successActivities | Where-Object {
                    $_.activityName -match 'quality|notebook' -and $_.status -match 'Completed|Succeeded|Success'
                } | Select-Object -First 1

                $downstreamGoldSuccess = $successActivities | Where-Object {
                    $_.activityName -match 'gold|dimension|warehouse|scd' -and $_.status -match 'Completed|Succeeded|Success'
                } | Select-Object -First 1

                $qualityActivityFailure = $failureActivities | Where-Object {
                    $_.activityName -match 'quality|notebook' -and $_.status -match 'Failed|Failure'
                } | Select-Object -First 1

                $downstreamBlocked = -not ($failureActivities | Where-Object {
                    $_.activityName -match 'gold|dimension|warehouse|scd' -and $_.status -match 'Completed|Succeeded|Success'
                })

                if ($hasSuccessStatus -and $hasFailureStatus -and $qualityActivitySuccess -and $downstreamGoldSuccess -and $qualityActivityFailure -and $downstreamBlocked) {
                    $found = $true
                    $message = @{
                        Status  = 'Succeeded'
                        Message = "Validated pipeline evidence in storage account '$($storage.StorageAccountName)' within RG '$rg'. Success run status '$($successEvidence.pipelineRunStatus)' shows quality activity '$($qualityActivitySuccess.activityName)' completed and downstream activity '$($downstreamGoldSuccess.activityName)' ran. Failure run status '$($failureEvidence.pipelineRunStatus)' shows quality activity '$($qualityActivityFailure.activityName)' failed and downstream Gold processing was blocked."
                    } | ConvertTo-Json
                } else {
                    $message = @{
                        Status  = 'Failed'
                        Message = "Pipeline evidence blobs were found in storage account '$($storage.StorageAccountName)', but they do not yet prove both required orchestration paths. Ensure pipeline-success.json shows a successful orchestration with completed quality and downstream Gold activities, and pipeline-failure.json shows a failed quality-gate run where downstream Gold processing did not succeed."
                    } | ConvertTo-Json
                }
            } else {
                $message = @{
                    Status  = 'Failed'
                    Message = "Validation evidence is incomplete in RG '$rg'. Upload both internal pipeline evidence files 'pipeline-success.json' and 'pipeline-failure.json' to container 'validation' in storage account '$($storage.StorageAccountName)' after capturing success and failure run outputs."
                } | ConvertTo-Json
            }
        } else {
            $message = @{
                Status  = 'Failed'
                Message = "No validation storage account starting with 'stfabricval' was found in RG '$rg'. The learner must use the lab-provided validation storage location for internal pipeline evidence."
            } | ConvertTo-Json
        }

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $message
        })
    }
    catch {
        $message = @{
            Status  = 'Failed'
            Message = "Error during check. Attempt $count of 3. Error: $($_.Exception.Message)"
        } | ConvertTo-Json
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $message
        })
        Start-Sleep -Seconds 10
    }
} while ($count -lt 3 -and -not $found)

# Post-loop: if every attempt failed, emit a final failure JSON so CloudLabs
# always sees a structured result.
if (-not $found) {
    $message = @{
        Status  = 'Failed'
        Message = "Orchestration run-state validation evidence was not found or did not meet requirements in RG '$rg' after 3 attempts."
    } | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $message
    })
}
