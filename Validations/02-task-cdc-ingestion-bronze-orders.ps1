using namespace System.Net

# Note: $sub (subscription id) and $DID (deployment id) are injected by the platform.
$rg = "rg-fabric-$DID"
$count = 0
$found = $false

function Get-FabricAccessToken {
    $token = Get-AzAccessToken -ResourceUrl "https://api.fabric.microsoft.com" -ErrorAction Stop
    if (-not $token.Token) {
        throw "Unable to acquire Microsoft Fabric access token."
    }
    return $token.Token
}

function Invoke-FabricGet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter(Mandatory = $true)]
        [string]$AccessToken
    )

    return Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $AccessToken" } -ErrorAction Stop
}

do {
    $count = $count + 1
    try {
        Set-AzContext -Subscription $sub -ErrorAction Stop

        $storageAccount = Get-AzStorageAccount -ResourceGroupName $rg -ErrorAction Stop |
            Where-Object { $_.StorageAccountName -like 'fabricval*' -or $_.StorageAccountName -like 'clfabric*' } |
            Select-Object -First 1

        if (-not $storageAccount) {
            $storageAccount = Get-AzStorageAccount -ResourceGroupName $rg -ErrorAction Stop | Select-Object -First 1
        }

        if (-not $storageAccount) {
            throw "No storage account was found in resource group '$rg' for validation evidence lookup."
        }

        $ctx = $storageAccount.Context
        $containerName = "fabric-validation"
        $blobName = "cdc-validation.json"
        $blob = Get-AzStorageBlob -Container $containerName -Blob $blobName -Context $ctx -ErrorAction SilentlyContinue

        if (-not $blob) {
            $message = @{
                Status  = "Failed"
                Message = "Validation evidence blob '$blobName' was not found in container '$containerName' in storage account '$($storageAccount.StorageAccountName)'."
            } | ConvertTo-Json
        }
        else {
            $tempFile = Join-Path $env:TEMP ("cdc-validation-{0}.json" -f [guid]::NewGuid().ToString())
            Get-AzStorageBlobContent -Container $containerName -Blob $blobName -Destination $tempFile -Context $ctx -Force -ErrorAction Stop | Out-Null
            $evidence = Get-Content -Path $tempFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue

            $workspaceId = [string]$evidence.workspaceId
            $lakehouseId = [string]$evidence.lakehouseId
            $tableName = [string]$evidence.tableName
            $baselineRowCount = [int]$evidence.baselineRowCount
            $postIncrementalRowCount = [int]$evidence.postIncrementalRowCount
            $incrementalRowsCaptured = [int]$evidence.incrementalRowsCaptured

            if ([string]::IsNullOrWhiteSpace($workspaceId) -or [string]::IsNullOrWhiteSpace($lakehouseId) -or [string]::IsNullOrWhiteSpace($tableName)) {
                throw "Validation evidence is missing workspaceId, lakehouseId, or tableName."
            }

            $fabricToken = Get-FabricAccessToken
            $tablesResponse = Invoke-FabricGet -Uri ("https://api.fabric.microsoft.com/v1/workspaces/{0}/lakehouses/{1}/tables" -f $workspaceId, $lakehouseId) -AccessToken $fabricToken
            $table = $tablesResponse.data | Where-Object { $_.name -eq $tableName }

            if (-not $table) {
                $message = @{
                    Status  = "Failed"
                    Message = "Lakehouse table '$tableName' was not found in Fabric lakehouse '$lakehouseId' for workspace '$workspaceId'."
                } | ConvertTo-Json
            }
            elseif ($table.format -ne 'delta') {
                $message = @{
                    Status  = "Failed"
                    Message = "Lakehouse table '$tableName' exists, but its format is '$($table.format)' instead of 'delta'."
                } | ConvertTo-Json
            }
            elseif ($tableName -ne 'bronze_orders_cdc') {
                $message = @{
                    Status  = "Failed"
                    Message = "Validation evidence points to table '$tableName', but the required Bronze CDC table is 'bronze_orders_cdc'."
                } | ConvertTo-Json
            }
            elseif ($baselineRowCount -le 0) {
                $message = @{
                    Status  = "Failed"
                    Message = "Evidence for 'bronze_orders_cdc' shows a nonpositive baseline row count of $baselineRowCount."
                } | ConvertTo-Json
            }
            elseif ($postIncrementalRowCount -le $baselineRowCount) {
                $message = @{
                    Status  = "Failed"
                    Message = "Evidence for 'bronze_orders_cdc' does not prove incremental CDC ingestion. Baseline rows: $baselineRowCount. Post-incremental rows: $postIncrementalRowCount."
                } | ConvertTo-Json
            }
            elseif ($incrementalRowsCaptured -le 0) {
                $message = @{
                    Status  = "Failed"
                    Message = "Evidence for 'bronze_orders_cdc' reports incrementalRowsCaptured=$incrementalRowsCaptured, which does not prove row-change capture."
                } | ConvertTo-Json
            }
            elseif (($postIncrementalRowCount - $baselineRowCount) -lt $incrementalRowsCaptured) {
                $message = @{
                    Status  = "Failed"
                    Message = "Evidence for 'bronze_orders_cdc' is inconsistent. Baseline rows: $baselineRowCount, post-incremental rows: $postIncrementalRowCount, incrementalRowsCaptured: $incrementalRowsCaptured."
                } | ConvertTo-Json
            }
            else {
                $found = $true
                $message = @{
                    Status  = "Succeeded"
                    Message = "Fabric lakehouse table 'bronze_orders_cdc' exists in workspace '$workspaceId' and lakehouse '$lakehouseId' as a Delta table. Validation evidence proves CDC ingestion with baseline rows $baselineRowCount, post-incremental rows $postIncrementalRowCount, and incremental rows captured $incrementalRowsCaptured."
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
