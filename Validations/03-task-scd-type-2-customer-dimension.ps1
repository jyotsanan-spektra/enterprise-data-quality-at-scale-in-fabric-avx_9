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

        $content = Get-ValidationBlobContent -StorageAccount $storage -BlobName 'scd-type2.json'

        if (-not $content) {
            $message = @{
                Status  = 'Failed'
                Message = "Validation evidence blob 'scd-type2.json' was not found in container 'validation' in storage account '$($storage.StorageAccountName)'. Complete Challenge 3 and upload the evidence file described in Task 3."
            } | ConvertTo-Json
        }
        else {
            $evidence = $content | ConvertFrom-Json -ErrorAction Stop

            $tableName = [string]$evidence.dimensionTableName
            $totalRowCount = [int]$evidence.totalRowCount
            $currentRowCount = [int]$evidence.currentRowCount
            $expiredRowCount = [int]$evidence.expiredRowCount
            $versionedCustomerCount = [int]$evidence.versionedCustomerCount

            if ($tableName -ne 'dim_customer') {
                $message = @{
                    Status  = 'Failed'
                    Message = "Evidence reports dimensionTableName '$tableName', but the required Gold dimension is 'dim_customer'."
                } | ConvertTo-Json
            }
            elseif ($currentRowCount -le 0 -or $expiredRowCount -le 0) {
                $message = @{
                    Status  = 'Failed'
                    Message = "Evidence reports currentRowCount=$currentRowCount and expiredRowCount=$expiredRowCount. SCD Type 2 requires both current and expired versions to exist after change processing."
                } | ConvertTo-Json
            }
            elseif ($versionedCustomerCount -le 0) {
                $message = @{
                    Status  = 'Failed'
                    Message = "Evidence reports versionedCustomerCount=$versionedCustomerCount. At least one customer must have both an expired and a current row to prove Type 2 versioning rather than an in-place overwrite."
                } | ConvertTo-Json
            }
            elseif ($expiredRowCount -ne $versionedCustomerCount) {
                $message = @{
                    Status  = 'Failed'
                    Message = "Evidence is inconsistent: expiredRowCount=$expiredRowCount but versionedCustomerCount=$versionedCustomerCount. Each changed customer should have exactly one expired row and one current row."
                } | ConvertTo-Json
            }
            elseif ($totalRowCount -ne ($currentRowCount + $expiredRowCount)) {
                $message = @{
                    Status  = 'Failed'
                    Message = "Evidence is inconsistent: totalRowCount=$totalRowCount does not equal currentRowCount ($currentRowCount) plus expiredRowCount ($expiredRowCount)."
                } | ConvertTo-Json
            }
            else {
                $found = $true
                $message = @{
                    Status  = 'Succeeded'
                    Message = "SCD Type 2 validation passed for 'dim_customer' in storage account '$($storage.StorageAccountName)'. Found $totalRowCount total rows: $currentRowCount current, $expiredRowCount expired, with $versionedCustomerCount customer(s) carrying both a historical and a current version."
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
        Message = "Customer dimension SCD Type 2 evidence not found in RG '$rg' after 3 attempts."
    } | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $message
    })
}
