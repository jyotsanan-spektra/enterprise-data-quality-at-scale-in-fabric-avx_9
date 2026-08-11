using namespace System.Net

# Note: $sub (subscription id) and $DID (deployment id) are injected by the platform.
$rg = "rg-fabric-challenge-$DID"
$count = 0
$found = $false

function Get-StorageContextFromRg {
    param(
        [string]$ResourceGroupName
    )

    $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -ErrorAction Stop |
        Sort-Object StorageAccountName |
        Select-Object -First 1

    if (-not $storageAccount) {
        throw "No storage account was found in resource group '$ResourceGroupName'."
    }

    $ctx = $storageAccount.Context
    if (-not $ctx) {
        $key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $storageAccount.StorageAccountName -ErrorAction Stop |
            Select-Object -First 1).Value
        $ctx = New-AzStorageContext -StorageAccountName $storageAccount.StorageAccountName -StorageAccountKey $key
    }

    return @{
        Account = $storageAccount
        Context = $ctx
    }
}

do {
    $count = $count + 1
    try {
        Set-AzContext -Subscription $sub -ErrorAction Stop

        $storage = Get-StorageContextFromRg -ResourceGroupName $rg
        $accountName = $storage.Account.StorageAccountName
        $ctx = $storage.Context

        $requiredContainerNames = @('fabricvalidation', 'validation', 'evidence')
        $container = $null
        foreach ($containerName in $requiredContainerNames) {
            $candidate = Get-AzStorageContainer -Name $containerName -Context $ctx -ErrorAction SilentlyContinue
            if ($candidate) {
                $container = $candidate
                break
            }
        }

        if (-not $container) {
            throw "No evidence container was found. Expected one of: $($requiredContainerNames -join ', ')."
        }

        $blobs = Get-AzStorageBlob -Container $container.Name -Context $ctx -ErrorAction Stop

        $silverSuccessBlob = $blobs | Where-Object {
            $_.Name -match 'silver_orders' -and $_.Name -match '(success|pass|promot)'
        } | Sort-Object LastModified -Descending | Select-Object -First 1

        $failureLogBlob = $blobs | Where-Object {
            $_.Name -match '(quality|dq|data[-_]?quality)' -and $_.Name -match '(fail|error|log)'
        } | Sort-Object LastModified -Descending | Select-Object -First 1

        $silverBlockBlob = $blobs | Where-Object {
            $_.Name -match 'silver_orders' -and $_.Name -match '(blocked|prevented|skipped|notwritten)'
        } | Sort-Object LastModified -Descending | Select-Object -First 1

        if ($silverSuccessBlob -and $failureLogBlob) {
            $found = $true
            $detailParts = @(
                "success evidence '$($silverSuccessBlob.Name)'",
                "failure log '$($failureLogBlob.Name)'"
            )

            if ($silverBlockBlob) {
                $detailParts += "blocked Silver evidence '$($silverBlockBlob.Name)'"
            }

            $message = @{
                Status  = "Succeeded"
                Message = "Spark quality gate evidence validated in storage account '$accountName', container '$($container.Name)': $($detailParts -join '; ')."
            } | ConvertTo-Json
        } else {
            $missing = @()
            if (-not $silverSuccessBlob) {
                $missing += "Silver success evidence for silver_orders"
            }
            if (-not $failureLogBlob) {
                $missing += "quality failure log evidence"
            }

            $message = @{
                Status  = "Failed"
                Message = "Spark quality gate validation is incomplete in storage account '$accountName', container '$($container.Name)'. Missing: $($missing -join '; ')."
            } | ConvertTo-Json
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
