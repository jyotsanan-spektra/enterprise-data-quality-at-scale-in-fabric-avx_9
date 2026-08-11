using namespace System.Net

# Note: $sub (subscription id) and $DID (deployment id) are injected by the platform.
$rg = "rg-fabric-$DID"
$count = 0
$found = $false

function Get-FabricAccessToken {
    $tokenResponse = Get-AzAccessToken -ResourceUrl "https://api.fabric.microsoft.com" -ErrorAction Stop
    if (-not $tokenResponse -or -not $tokenResponse.Token) {
        throw "Unable to acquire Microsoft Fabric access token."
    }

    return $tokenResponse.Token
}

function Invoke-FabricGet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter(Mandatory = $true)]
        [string]$Token
    )

    Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $Token" } -ErrorAction Stop
}

do {
    $count = $count + 1
    try {
        Set-AzContext -Subscription $sub -ErrorAction Stop

        $rgObj = Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue
        if (-not $rgObj) {
            throw "Resource group '$rg' was not found."
        }

        $vm = Get-AzVM -ResourceGroupName $rg -Status -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $vm) {
            throw "No lab VM was found in resource group '$rg'."
        }

        $storageAccounts = @(Get-AzStorageAccount -ResourceGroupName $rg -ErrorAction SilentlyContinue)
        $sqlServers = @(Get-AzSqlServer -ResourceGroupName $rg -ErrorAction SilentlyContinue)

        if ($storageAccounts.Count -eq 0) {
            throw "No Azure Storage account was found in resource group '$rg'."
        }

        if ($sqlServers.Count -eq 0) {
            throw "No Azure SQL logical server was found in resource group '$rg'."
        }

        $fabricToken = Get-FabricAccessToken
        $workspaceResponse = Invoke-FabricGet -Uri "https://api.fabric.microsoft.com/v1/workspaces" -Token $fabricToken
        $workspaces = @($workspaceResponse.value)

        if (-not $workspaces -or $workspaces.Count -eq 0) {
            throw "No Microsoft Fabric workspaces were returned for the signed-in lab identity."
        }

        $candidateWorkspace = $workspaces |
            Where-Object { $_.displayName -match 'Contoso|Operations|Medallion|Fabric' } |
            Select-Object -First 1

        if (-not $candidateWorkspace) {
            $candidateWorkspace = $workspaces | Select-Object -First 1
        }

        $workspaceId = $candidateWorkspace.id
        $workspaceName = $candidateWorkspace.displayName

        if (-not $workspaceId) {
            throw "A Microsoft Fabric workspace was found, but its id was not returned by the API."
        }

        $itemsResponse = Invoke-FabricGet -Uri "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/items" -Token $fabricToken
        $items = @($itemsResponse.value)

        $lakehouse = $items | Where-Object { $_.type -eq 'Lakehouse' } | Select-Object -First 1
        $warehouse = $items | Where-Object { $_.type -eq 'Warehouse' } | Select-Object -First 1

        if ($lakehouse -and $warehouse) {
            $found = $true
            $message = @{
                Status  = "Succeeded"
                Message = "Prerequisite environment is ready. Azure-side readiness was confirmed in resource group '$rg' with lab VM '$($vm.Name)', storage account '$($storageAccounts[0].StorageAccountName)', and SQL server '$($sqlServers[0].ServerName)'. Learner-created Fabric baseline items were also confirmed in workspace '$workspaceName' ($workspaceId): lakehouse '$($lakehouse.displayName)' and warehouse '$($warehouse.displayName)'."
            } | ConvertTo-Json
        }
        else {
            $missing = @()
            if (-not $lakehouse) { $missing += 'Lakehouse' }
            if (-not $warehouse) { $missing += 'Warehouse' }

            $message = @{
                Status  = "Failed"
                Message = "Azure-side readiness is confirmed in resource group '$rg' with VM '$($vm.Name)', storage account '$($storageAccounts[0].StorageAccountName)', and SQL server '$($sqlServers[0].ServerName)', but the learner has not yet created all required baseline Fabric items in workspace '$workspaceName'. Missing item types: $($missing -join ', ')."
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
        Message = "Prerequisite environment readiness validation not satisfied in RG '$rg' after 3 attempts."
    } | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $message
    })
}
