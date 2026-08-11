using namespace System.Net

# Note: $sub (subscription id) and $DID (deployment id) are injected by the platform.
$rg = "rg-fabric-$DID"
$count = 0
$found = $false

function Get-TableRowCount {
    param(
        [object[]]$Rows,
        [string[]]$CandidateColumns,
        [scriptblock]$Predicate
    )

    foreach ($column in $CandidateColumns) {
        if ($Rows.Count -gt 0 -and ($Rows[0].PSObject.Properties.Name -contains $column)) {
            return @($Rows | Where-Object { & $Predicate $_.$column }).Count
        }
    }

    return $null
}

do {
    $count = $count + 1
    try {
        Set-AzContext -Subscription $sub -ErrorAction Stop

        $storageAccount = Get-AzStorageAccount -ResourceGroupName $rg -ErrorAction Stop |
            Where-Object { $_.StorageAccountName -like 'stfabric*' -or $_.StorageAccountName -like 'fabric*' } |
            Select-Object -First 1

        if (-not $storageAccount) {
            throw "No storage account containing Fabric validation evidence was found in resource group '$rg'."
        }

        $ctx = $storageAccount.Context
        $containerName = 'fabricvalidation'
        $blobName = 'gold/customer_dimension_scd_type2.json'

        $blob = Get-AzStorageBlob -Container $containerName -Context $ctx -Blob $blobName -ErrorAction SilentlyContinue
        if (-not $blob) {
            throw "Validation evidence blob '$blobName' was not found in container '$containerName' in storage account '$($storageAccount.StorageAccountName)'."
        }

        $tempFile = Join-Path -Path $env:TEMP -ChildPath ("customer-dimension-scd-{0}.json" -f ([guid]::NewGuid().ToString()))
        Get-AzStorageBlobContent -Container $containerName -Context $ctx -Blob $blobName -Destination $tempFile -Force | Out-Null

        $content = Get-Content -Path $tempFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) {
            throw "Evidence blob '$blobName' is empty."
        }

        $evidence = $content | ConvertFrom-Json -Depth 20 -ErrorAction Stop

        if (-not $evidence.dimensionTableName) {
            throw "Evidence blob '$blobName' does not include 'dimensionTableName'."
        }

        if (-not $evidence.rows) {
            throw "Evidence blob '$blobName' does not include a 'rows' collection for validation."
        }

        $rows = @($evidence.rows)
        if ($rows.Count -lt 2) {
            throw "Evidence blob '$blobName' contains fewer than 2 rows, which is insufficient to prove SCD Type 2 versioning."
        }

        $currentCount = Get-TableRowCount -Rows $rows -CandidateColumns @('IsCurrent','isCurrent','CurrentRowIndicator','currentRowIndicator','RecIsCurrent') -Predicate { param($v) $v -eq $true -or $v -eq 1 -or $v -eq '1' -or $v -eq 'true' -or $v -eq 'TRUE' }
        $expiredCount = Get-TableRowCount -Rows $rows -CandidateColumns @('IsCurrent','isCurrent','CurrentRowIndicator','currentRowIndicator','RecIsCurrent') -Predicate { param($v) $v -eq $false -or $v -eq 0 -or $v -eq '0' -or $v -eq 'false' -or $v -eq 'FALSE' }

        $effectiveDatePresent = ($rows[0].PSObject.Properties.Name -contains 'EffectiveDate') -or
                               ($rows[0].PSObject.Properties.Name -contains 'effectiveDate') -or
                               ($rows[0].PSObject.Properties.Name -contains 'StartDate') -or
                               ($rows[0].PSObject.Properties.Name -contains 'startDate') -or
                               ($rows[0].PSObject.Properties.Name -contains 'RecValidFromKey')

        $expiryDatePresent = ($rows[0].PSObject.Properties.Name -contains 'ExpiryDate') -or
                            ($rows[0].PSObject.Properties.Name -contains 'expiryDate') -or
                            ($rows[0].PSObject.Properties.Name -contains 'EndDate') -or
                            ($rows[0].PSObject.Properties.Name -contains 'endDate') -or
                            ($rows[0].PSObject.Properties.Name -contains 'RecValidToKey')

        $surrogateKeyPresent = ($rows[0].PSObject.Properties.Name -contains 'CustomerSK') -or
                              ($rows[0].PSObject.Properties.Name -contains 'customerSK') -or
                              ($rows[0].PSObject.Properties.Name -contains 'CustomerKey') -or
                              ($rows[0].PSObject.Properties.Name -contains 'customerKey') -or
                              ($rows[0].PSObject.Properties.Name -contains 'SurrogateKey') -or
                              ($rows[0].PSObject.Properties.Name -contains 'surrogateKey')

        $naturalKeyColumn = @('CustomerID','customerID','CustomerId','customerId','CustomerNK','customerNK','NaturalKey','naturalKey') |
            Where-Object { $rows[0].PSObject.Properties.Name -contains $_ } |
            Select-Object -First 1

        $versionedCustomerCount = 0
        if ($naturalKeyColumn) {
            $versionedCustomerCount = @($rows | Group-Object -Property $naturalKeyColumn | Where-Object { $_.Count -gt 1 }).Count
        }

        if ($currentCount -ge 1 -and $expiredCount -ge 1 -and $effectiveDatePresent -and $expiryDatePresent -and $surrogateKeyPresent -and $versionedCustomerCount -ge 1) {
            $found = $true
            $message = @{
                Status  = 'Succeeded'
                Message = "SCD Type 2 validation passed for table '$($evidence.dimensionTableName)' in RG '$rg'. Found $currentCount current row(s), $expiredCount expired row(s), and $versionedCustomerCount customer key(s) with multiple versions in evidence blob '$blobName'."
            } | ConvertTo-Json
        } else {
            $missingParts = @()
            if ($currentCount -lt 1) { $missingParts += 'at least one current row indicator' }
            if ($expiredCount -lt 1) { $missingParts += 'at least one expired row indicator' }
            if (-not $effectiveDatePresent) { $missingParts += 'effective/start date column' }
            if (-not $expiryDatePresent) { $missingParts += 'expiry/end date column' }
            if (-not $surrogateKeyPresent) { $missingParts += 'surrogate key column' }
            if ($versionedCustomerCount -lt 1) { $missingParts += 'a repeated natural key proving multiple versions for a changed customer' }

            $message = @{
                Status  = 'Failed'
                Message = "SCD Type 2 validation failed for table '$($evidence.dimensionTableName)' in RG '$rg'. Missing or invalid evidence: $($missingParts -join ', ')."
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
        Message = "Customer dimension SCD Type 2 evidence not found in RG '$rg' after 3 attempts."
    } | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $message
    })
}
