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

        $content = Get-ValidationBlobContent -StorageAccount $storage -BlobName 'quality-gate.json'

        if (-not $content) {
            $message = @{
                Status  = "Failed"
                Message = "Validation evidence blob 'quality-gate.json' was not found in container 'validation' in storage account '$($storage.StorageAccountName)'. Complete Challenge 4 and upload the evidence file described in Task 3."
            } | ConvertTo-Json
        }
        else {
            $evidence = $content | ConvertFrom-Json -ErrorAction Stop

            $passStatus = [string]$evidence.passRunOverallStatus
            $failStatus = [string]$evidence.failRunOverallStatus
            $failedRule = [string]$evidence.failRunFailedRule
            $silverBefore = [int]$evidence.silverRowCountAfterPassRun
            $silverAfter = [int]$evidence.silverRowCountAfterFailRun
            $silverTable = [string]$evidence.silverTableName

            if ($silverTable -ne 'silver_orders') {
                $message = @{
                    Status  = "Failed"
                    Message = "Evidence reports silverTableName '$silverTable', but the required Silver table is 'silver_orders'."
                } | ConvertTo-Json
            }
            elseif ($passStatus -notmatch 'Passed|Succeeded|Success') {
                $message = @{
                    Status  = "Failed"
                    Message = "Evidence reports passRunOverallStatus '$passStatus'. The clean-data run must pass all blocking quality checks before Silver promotion."
                } | ConvertTo-Json
            }
            elseif ($failStatus -notmatch 'Failed|Failure') {
                $message = @{
                    Status  = "Failed"
                    Message = "Evidence reports failRunOverallStatus '$failStatus'. The defect run must fail the gate so that Silver promotion is blocked."
                } | ConvertTo-Json
            }
            elseif ([string]::IsNullOrWhiteSpace($failedRule)) {
                $message = @{
                    Status  = "Failed"
                    Message = "Evidence does not name the quality rule that failed during the defect run. Record the failing rule (for example 'null_check') in failRunFailedRule."
                } | ConvertTo-Json
            }
            elseif ($silverBefore -le 0) {
                $message = @{
                    Status  = "Failed"
                    Message = "Evidence reports silverRowCountAfterPassRun=$silverBefore. The passing run should have written rows into 'silver_orders'."
                } | ConvertTo-Json
            }
            elseif ($silverAfter -ne $silverBefore) {
                $message = @{
                    Status  = "Failed"
                    Message = "Evidence reports that 'silver_orders' changed from $silverBefore rows to $silverAfter rows across the failed run. A blocked quality gate must leave the Silver table untouched."
                } | ConvertTo-Json
            }
            else {
                $found = $true
                $message = @{
                    Status  = "Succeeded"
                    Message = "Spark quality gate validated in storage account '$($storage.StorageAccountName)'. The clean run passed and wrote $silverBefore rows to 'silver_orders'; the defect run failed on rule '$failedRule' and left 'silver_orders' unchanged at $silverAfter rows."
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
        Message = "Spark quality gate evidence not found in RG '$rg' after 3 attempts."
    } | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $message
    })
}
