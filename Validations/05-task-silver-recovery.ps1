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

function Test-RequiredFields {
    param(
        [Parameter(Mandatory = $true)]
        $Object,

        [Parameter(Mandatory = $true)]
        [string[]]$Fields
    )

    foreach ($field in $Fields) {
        if (-not $Object.PSObject.Properties.Name.Contains($field)) {
            return $false
        }

        if ($null -eq $Object.$field -or [string]::IsNullOrWhiteSpace([string]$Object.$field)) {
            return $false
        }
    }

    return $true
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
            $historyBlobContent = Get-ValidationBlobContent -StorageAccountName $storage.StorageAccountName -ContainerName 'validation' -BlobName 'silver-recovery-history.json'
            $restoreBlobContent = Get-ValidationBlobContent -StorageAccountName $storage.StorageAccountName -ContainerName 'validation' -BlobName 'silver-recovery-restore.json'
            $cloneBlobContent = Get-ValidationBlobContent -StorageAccountName $storage.StorageAccountName -ContainerName 'validation' -BlobName 'silver-recovery-clone.json'

            if ($historyBlobContent -and $restoreBlobContent -and $cloneBlobContent) {
                $historyEvidence = $historyBlobContent | ConvertFrom-Json -ErrorAction Stop
                $restoreEvidence = $restoreBlobContent | ConvertFrom-Json -ErrorAction Stop
                $cloneEvidence = $cloneBlobContent | ConvertFrom-Json -ErrorAction Stop

                $historyValid = Test-RequiredFields -Object $historyEvidence -Fields @('tableName', 'corruptedVersion', 'lastKnownGoodVersion')
                $restoreValid = Test-RequiredFields -Object $restoreEvidence -Fields @('tableName', 'restoredToVersion', 'restoredRowCount')
                $cloneValid = Test-RequiredFields -Object $cloneEvidence -Fields @('sourceTable', 'cloneTable', 'cloneType')

                $sameTable = $historyEvidence.tableName -eq 'silver_orders' -and $restoreEvidence.tableName -eq 'silver_orders' -and $cloneEvidence.sourceTable -eq 'silver_orders'
                $versionProgression = [int]$historyEvidence.lastKnownGoodVersion -le [int]$restoreEvidence.restoredToVersion
                $rowCountValid = [int]$restoreEvidence.restoredRowCount -gt 0
                $cloneNameValid = $cloneEvidence.cloneTable -like 'silver_orders_backup*'
                $cloneTypeValid = $cloneEvidence.cloneType -match 'deep|shallow'

                if ($historyValid -and $restoreValid -and $cloneValid -and $sameTable -and $versionProgression -and $rowCountValid -and $cloneNameValid -and $cloneTypeValid) {
                    $found = $true
                    $message = @{
                        Status  = 'Succeeded'
                        Message = "Validated Silver recovery evidence in storage account '$($storage.StorageAccountName)' within RG '$rg'. Table 'silver_orders' shows corruption at version '$($historyEvidence.corruptedVersion)', last known good version '$($historyEvidence.lastKnownGoodVersion)', restore target '$($restoreEvidence.restoredToVersion)' with row count '$($restoreEvidence.restoredRowCount)', and backup clone '$($cloneEvidence.cloneTable)' of type '$($cloneEvidence.cloneType)'."
                    } | ConvertTo-Json
                } else {
                    $message = @{
                        Status  = 'Failed'
                        Message = "Silver recovery evidence blobs were found in storage account '$($storage.StorageAccountName)', but they do not yet prove a valid Delta audit and restore workflow for 'silver_orders'. Ensure the history, restore, and clone JSON files contain the required fields and expected values."
                    } | ConvertTo-Json
                }
            } else {
                $message = @{
                    Status  = 'Failed'
                    Message = "Validation evidence is incomplete in RG '$rg'. Upload 'silver-recovery-history.json', 'silver-recovery-restore.json', and 'silver-recovery-clone.json' to container 'validation' in storage account '$($storage.StorageAccountName)' after completing the Silver recovery scenario."
                } | ConvertTo-Json
            }
        } else {
            $message = @{
                Status  = 'Failed'
                Message = "No validation storage account starting with 'stfabricval' was found in RG '$rg'. The learner must use the lab-provided validation storage location for Silver recovery evidence."
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
        Message = "Silver recovery validation evidence was not found or did not meet requirements in RG '$rg' after 3 attempts."
    } | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $message
    })
}
