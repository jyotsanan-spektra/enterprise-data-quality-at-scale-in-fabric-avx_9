using namespace System.Net

# Note: $sub (subscription id) and $DID (deployment id) are injected by the platform.
$rg = "rg-fabricdataquality-$DID"
$count = 0
$found = $false

function Get-ValidationStorageAccount {
    $expectedName = "stfabricval" + $DID.Replace('-', '').ToLower()
    if ($expectedName.Length -gt 23) {
        $expectedName = $expectedName.Substring(0, 23)
    }

    $storage = Get-AzStorageAccount -ResourceGroupName $rg -Name $expectedName -ErrorAction SilentlyContinue
    if (-not $storage) {
        $storage = Get-AzStorageAccount -ResourceGroupName $rg -ErrorAction SilentlyContinue |
            Where-Object { $_.StorageAccountName -like 'stfabricval*' } |
            Select-Object -First 1
    }

    return $storage
}

function Get-ValidationBlobContent {
    param(
        [Parameter(Mandatory = $true)]
        $StorageAccount,

        [Parameter(Mandatory = $true)]
        [string]$BlobName
    )

    $ctx = $StorageAccount.Context
    $blob = Get-AzStorageBlob -Context $ctx -Container 'validation' -Blob $BlobName -ErrorAction SilentlyContinue
    if (-not $blob) {
        return $null
    }

    $tempFile = Join-Path -Path $env:TEMP -ChildPath ([System.Guid]::NewGuid().ToString() + '.json')
    Get-AzStorageBlobContent -Context $ctx -Container 'validation' -Blob $BlobName -Destination $tempFile -Force -ErrorAction Stop | Out-Null
    $content = Get-Content -Path $tempFile -Raw -ErrorAction Stop
    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    return $content
}

do {
    $count = $count + 1
    try {
        Set-AzContext -Subscription $sub -ErrorAction Stop

        $storage = Get-ValidationStorageAccount
        if (-not $storage) {
            throw "No validation storage account starting with 'stfabricval' was found in resource group '$rg'."
        }

        $content = Get-ValidationBlobContent -StorageAccount $storage -BlobName 'cdc-ingestion.json'

        if (-not $content) {
            $message = @{
                Status  = "Failed"
                Message = "Validation evidence blob 'cdc-ingestion.json' was not found in container 'validation' in storage account '$($storage.StorageAccountName)'. Complete Challenge 2 and upload the evidence file described in Task 4."
            } | ConvertTo-Json
        }
        else {
            $evidence = $content | ConvertFrom-Json -ErrorAction Stop

            $tableName = [string]$evidence.tableName
            $baselineRowCount = [int]$evidence.baselineRowCount
            $postIncrementalRowCount = [int]$evidence.postIncrementalRowCount
            $incrementalRowsWritten = [int]$evidence.incrementalRowsWritten
            $copyMode = [string]$evidence.copyMode

            if ($tableName -ne 'bronze_orders_cdc') {
                $message = @{
                    Status  = "Failed"
                    Message = "Evidence reports tableName '$tableName', but the required Bronze CDC table is 'bronze_orders_cdc'."
                } | ConvertTo-Json
            }
            elseif ($copyMode -notmatch 'incremental|cdc') {
                $message = @{
                    Status  = "Failed"
                    Message = "Evidence reports copyMode '$copyMode'. The Copy job must use a CDC-aware incremental copy mode, not a full copy."
                } | ConvertTo-Json
            }
            elseif ($baselineRowCount -lt 90000) {
                $message = @{
                    Status  = "Failed"
                    Message = "Evidence reports a baseline row count of $baselineRowCount for 'bronze_orders_cdc'. The prepared Orders source contains approximately 100,000 rows, so the baseline load does not look complete."
                } | ConvertTo-Json
            }
            elseif ($postIncrementalRowCount -le $baselineRowCount) {
                $message = @{
                    Status  = "Failed"
                    Message = "Evidence does not prove incremental CDC ingestion. Baseline rows: $baselineRowCount. Post-incremental rows: $postIncrementalRowCount. The second Copy job run should have added rows."
                } | ConvertTo-Json
            }
            elseif ($incrementalRowsWritten -le 0 -or $incrementalRowsWritten -ge $baselineRowCount) {
                $message = @{
                    Status  = "Failed"
                    Message = "Evidence reports incrementalRowsWritten=$incrementalRowsWritten against a baseline of $baselineRowCount. An incremental CDC run should write a small change set (approximately 500 rows), not zero and not a full reload."
                } | ConvertTo-Json
            }
            else {
                $found = $true
                $message = @{
                    Status  = "Succeeded"
                    Message = "CDC ingestion validated for 'bronze_orders_cdc' in storage account '$($storage.StorageAccountName)'. Copy mode '$copyMode' produced a baseline of $baselineRowCount rows, then captured $incrementalRowsWritten incremental rows for a post-incremental total of $postIncrementalRowCount."
                } | ConvertTo-Json
            }
        }

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $message
        })
    }
    catch {
        $message = @{
            Status  = "Failed"
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
        Status  = "Failed"
        Message = "bronze_orders_cdc CDC validation evidence not found or did not prove baseline plus incremental ingestion in RG '$rg' after 3 attempts."
    } | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $message
    })
}
