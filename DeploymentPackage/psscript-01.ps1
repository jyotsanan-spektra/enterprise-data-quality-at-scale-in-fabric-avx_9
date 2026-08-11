Param(
    [Parameter(Mandatory = $true)]
    [string]$AzureUserName,

    [Parameter(Mandatory = $true)]
    [string]$AzurePassword,

    [Parameter(Mandatory = $true)]
    [string]$AzureTenantID,

    [Parameter(Mandatory = $true)]
    [string]$AzureSubscriptionID,

    [Parameter(Mandatory = $true)]
    [string]$ODLID,

    [Parameter(Mandatory = $true)]
    [string]$InstallCloudLabsShadow,

    [Parameter(Mandatory = $true)]
    [string]$DeploymentID,

    [Parameter(Mandatory = $true)]
    [string]$vmAdminUsername,

    [Parameter(Mandatory = $true)]
    [string]$vmAdminPassword,

    [Parameter(Mandatory = $true)]
    [string]$trainerUserName,

    [Parameter(Mandatory = $true)]
    [string]$trainerUserPassword
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$LabFilesPath = 'C:\LabFiles'
$PublicDesktop = 'C:\Users\Public\Desktop'
$CloudLabsCommonBase = 'https://experienceazure.blob.core.windows.net/templates/cloudlabs-common'
$LabRoot = 'C:\LabFiles\FabricChallengeLab'
$SamplesRoot = Join-Path $LabRoot 'Samples'
$ScriptsRoot = Join-Path $LabRoot 'Scripts'
$DocsRoot = Join-Path $LabRoot 'Docs'
$LogsRoot = Join-Path $LabRoot 'Logs'
$RepoRoot = Join-Path $LabRoot 'Starter'
$DesktopShortcutsPath = Join-Path $PublicDesktop 'Fabric Lab Files'
$EnvPaths = @(
    (Join-Path $LabFilesPath '.env'),
    (Join-Path $RepoRoot '.env')
)

Start-Transcript -Path 'C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt' -Append

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    function Write-Log {
        param([string]$Message)
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] $Message"
    }

    function Ensure-Directory {
        param([string]$Path)
        if (-not (Test-Path -Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }
    }

    function CreateCredFile {
        Write-Log 'Downloading CloudLabs common credential assets.'
        Ensure-Directory -Path $LabFilesPath
        Ensure-Directory -Path $PublicDesktop

        $azureCredsTxt = Join-Path $env:TEMP 'AzureCreds.txt'
        $azureCredsPs1 = Join-Path $env:TEMP 'AzureCreds.ps1'

        Invoke-WebRequest -Uri "$CloudLabsCommonBase/AzureCreds.txt" -OutFile $azureCredsTxt
        Invoke-WebRequest -Uri "$CloudLabsCommonBase/AzureCreds.ps1" -OutFile $azureCredsPs1

        $credsContent = Get-Content -Path $azureCredsTxt -Raw
        $credsContent = $credsContent.Replace('AzureUserNameValue', $AzureUserName)
        $credsContent = $credsContent.Replace('AzurePasswordValue', $AzurePassword)
        $credsContent = $credsContent.Replace('AzureTenantIDValue', $AzureTenantID)
        $credsContent = $credsContent.Replace('AzureSubscriptionIDValue', $AzureSubscriptionID)
        $credsContent = $credsContent.Replace('ODLIDValue', $ODLID)
        $credsContent = $credsContent.Replace('DeploymentIDValue', $DeploymentID)

        Set-Content -Path (Join-Path $LabFilesPath 'AzureCreds.txt') -Value $credsContent -Force
        Copy-Item -Path $azureCredsPs1 -Destination (Join-Path $LabFilesPath 'AzureCreds.ps1') -Force
        Copy-Item -Path (Join-Path $LabFilesPath 'AzureCreds.txt') -Destination (Join-Path $PublicDesktop 'AzureCreds.txt') -Force
        Copy-Item -Path (Join-Path $LabFilesPath 'AzureCreds.ps1') -Destination (Join-Path $PublicDesktop 'AzureCreds.ps1') -Force
    }

    function Ensure-TrainerAccount {
        if ($InstallCloudLabsShadow -eq 'false' -or $InstallCloudLabsShadow -eq 'False') {
            Write-Log 'InstallCloudLabsShadow is false. Skipping trainer account creation.'
            return
        }

        Write-Log 'Ensuring trainer account exists for VM Shadow.'
        $securePassword = ConvertTo-SecureString $trainerUserPassword -AsPlainText -Force
        $existingUser = Get-LocalUser -Name $trainerUserName -ErrorAction SilentlyContinue

        if (-not $existingUser) {
            New-LocalUser -Name $trainerUserName -Password $securePassword -PasswordNeverExpires -AccountNeverExpires | Out-Null
        }

        try {
            Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $trainerUserName -ErrorAction Stop
        }
        catch {
            Write-Log 'Trainer account is already a member of Remote Desktop Users or could not be added again.'
        }

        try {
            Add-LocalGroupMember -Group 'Administrators' -Member $trainerUserName -ErrorAction Stop
        }
        catch {
            Write-Log 'Trainer account is already a member of Administrators or could not be added again.'
        }
    }

    function Install-ChocolateyIfNeeded {
        if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
            Write-Log 'Installing Chocolatey.'
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        }
        else {
            Write-Log 'Chocolatey is already installed.'
        }
    }

    function Install-LabTools {
        Install-ChocolateyIfNeeded

        $packages = @(
            'git',
            'python',
            'vscode',
            'azure-cli',
            'azcopy10',
            'sql-server-management-studio',
            'microsoft-edge',
            'notepadplusplus',
            '7zip',
            'powerbi'
        )

        foreach ($package in $packages) {
            Write-Log "Installing package: $package"
            choco install $package -y --no-progress --ignore-checksums
        }

        $azCmd = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
        if (Test-Path $azCmd) {
            Write-Log 'Upgrading Azure CLI to ensure latest command surface.'
            & $azCmd upgrade --yes
            & $azCmd extension add --name ml --yes 2>$null
            & $azCmd extension update --name ml 2>$null
        }

        Write-Log 'Installing VS Code extensions for Fabric authoring.'
        $codeCmd = 'C:\Program Files\Microsoft VS Code\bin\code.cmd'
        if (Test-Path $codeCmd) {
            & $codeCmd --install-extension ms-python.python --force
            & $codeCmd --install-extension ms-toolsai.jupyter --force
            & $codeCmd --install-extension ms-azuretools.vscode-azurecli --force
            & $codeCmd --install-extension ms-mssql.mssql --force
        }

        Write-Log 'Installing Python helper packages.'
        & python -m pip install --upgrade pip
        & python -m pip install pandas pyarrow deltalake notebook jupyterlab fabric-cicd python-dotenv azure-identity openai
    }

    function Initialize-LabContent {
        Write-Log 'Creating lab content structure.'
        foreach ($path in @($LabFilesPath, $LabRoot, $SamplesRoot, $ScriptsRoot, $DocsRoot, $LogsRoot, $RepoRoot)) {
            Ensure-Directory -Path $path
        }

        $readme = @'
# Enterprise Data Quality at Scale in Fabric

This workstation is preconfigured for the Fabric challenge lab.

Included assets:
- Azure credential helper files on the desktop and in C:\LabFiles
- Sample SQL, notebook, and prompt input assets under C:\LabFiles\FabricChallengeLab
- Validation and evidence folders for CDC, SCD Type 2, quality gates, recovery, and orchestration
- Browser shortcuts for Microsoft Fabric, Microsoft Learn, Azure portal, and Azure AI Foundry

Authoring references captured from Microsoft Learn:
- Fabric notebooks and PySpark: https://learn.microsoft.com/fabric/data-science/python-guide/python-overview
- Fabric notebook kernel guidance: https://learn.microsoft.com/fabric/data-engineering/fabric-notebook-selection-guide
- Copy job CDC: https://learn.microsoft.com/fabric/data-factory/cdc-copy-job
- Azure SQL CDC with Copy job: https://learn.microsoft.com/fabric/data-factory/cdc-copy-job-azure-sql-database
- SCD Type 2 in Fabric Data Factory: https://learn.microsoft.com/fabric/data-factory/slowly-changing-dimension-type-two
- Warehouse dimension modeling: https://learn.microsoft.com/fabric/data-warehouse/dimensional-modeling-dimension-tables
- Delta Lake time travel: https://learn.microsoft.com/fabric/data-engineering/delta-lake-time-travel
- Delta Lake restore: https://learn.microsoft.com/fabric/data-engineering/delta-lake-restore
- Delta Lake clone: https://learn.microsoft.com/fabric/data-engineering/delta-lake-clone
- Azure OpenAI resource endpoint and key retrieval: https://learn.microsoft.com/azure/ai-foundry/openai/how-to/create-resource#retrieve-information-about-the-resource
- Foundry project CLI show: https://learn.microsoft.com/azure/foundry/how-to/create-projects#create-multiple-projects-on-the-same-resource
- Foundry/AI SDK token acquisition guidance: https://learn.microsoft.com/azure/foundry/how-to/develop/sdk-overview
- Blob upload-batch with auth-mode login: https://learn.microsoft.com/azure/storage/blobs/storage-quickstart-blobs-cli#upload-a-blob
'@
        Set-Content -Path (Join-Path $LabRoot 'README.md') -Value $readme -Force

        $envContent = @"
FABRIC_PORTAL_URL=https://app.fabric.microsoft.com
AI_FOUNDRY_PORTAL_URL=https://ai.azure.com
FABRIC_WORKSPACE_NAME=contoso-fabric-$DeploymentID
FABRIC_LAKEHOUSE_NAME=ContosoOperationsLakehouse
FABRIC_WAREHOUSE_NAME=ContosoOperationsWarehouse
BRONZE_TABLE_NAME=bronze_orders_cdc
SILVER_TABLE_NAME=silver_orders
GOLD_DIMENSION_NAME=dim_customer
SOURCE_SYSTEM_NAME=Contoso_Operations
SOURCE_TABLE_ORDERS=Orders
SOURCE_TABLE_CUSTOMERS=Customers
SOURCE_TABLE_PRODUCTS=Products
CDC_EXPECTED_MODE=CopyJobCDC
NOTEBOOK_LANGUAGE=PySpark
DELTA_RECOVERY_PATTERN=TIME_TRAVEL_RESTORE_CLONE
AZURE_TENANT_ID=$AzureTenantID
AZURE_SUBSCRIPTION_ID=$AzureSubscriptionID
AZURE_USERNAME=$AzureUserName
ODL_ID=$ODLID
DEPLOYMENT_ID=$DeploymentID
LABFILES_ROOT=$LabRoot
EVIDENCE_ROOT=$LogsRoot
AZURE_OPENAI_ENDPOINT=__TO_BE_DISCOVERED__
AZURE_OPENAI_API_KEY=__TO_BE_DISCOVERED__
AZURE_OPENAI_DEPLOYMENT=__TO_BE_DISCOVERED__
AZURE_OPENAI_RESOURCE_NAME=__TO_BE_DISCOVERED__
AZURE_OPENAI_RESOURCE_GROUP=__TO_BE_DISCOVERED__
AI_FOUNDRY_PROJECT_NAME=__TO_BE_DISCOVERED__
AI_FOUNDRY_PROJECT_ID=__TO_BE_DISCOVERED__
AI_FOUNDRY_PROJECT_ENDPOINT=__TO_BE_DISCOVERED__
AI_FOUNDRY_ACCOUNT_NAME=__TO_BE_DISCOVERED__
AI_FOUNDRY_TOKEN=__TO_BE_DISCOVERED__
STORAGE_ACCOUNT_NAME=__TO_BE_DISCOVERED__
STORAGE_CONTAINER=__TO_BE_DISCOVERED__
STORAGE_BLOB_ENDPOINT=__TO_BE_DISCOVERED__
SAMPLE_DOCUMENTS_PATH=$SamplesRoot\Documents
"@
        foreach ($envPath in $EnvPaths) {
            Ensure-Directory -Path (Split-Path -Path $envPath -Parent)
            Set-Content -Path $envPath -Value $envContent -Force
        }

        $ordersCsv = @'
OrderID,CustomerID,ProductID,OrderDate,Quantity,UnitPrice,OrderStatus,ModifiedDate
1001,C100,P10,2024-01-10,3,45.50,Submitted,2024-01-10T09:00:00Z
1002,C101,P11,2024-01-11,2,15.00,Submitted,2024-01-11T10:30:00Z
1003,C102,P12,2024-01-12,1,99.99,Shipped,2024-01-12T14:00:00Z
1004,C100,P13,2024-01-12,5,9.99,Submitted,2024-01-12T15:15:00Z
'@
        Set-Content -Path (Join-Path $SamplesRoot 'orders_baseline.csv') -Value $ordersCsv -Force

        $ordersDeltaCsv = @'
OrderID,CustomerID,ProductID,OrderDate,Quantity,UnitPrice,OrderStatus,ModifiedDate,Operation
1002,C101,P11,2024-01-11,4,15.00,Shipped,2024-01-13T10:15:00Z,UPDATE
1005,C103,P14,2024-01-13,2,22.50,Submitted,2024-01-13T11:00:00Z,INSERT
1006,C100,P15,2024-01-13,1,250.00,Submitted,2024-01-13T11:05:00Z,INSERT
'@
        Set-Content -Path (Join-Path $SamplesRoot 'orders_incremental.csv') -Value $ordersDeltaCsv -Force

        $customersCsv = @'
CustomerID,CustomerName,Region,Email,IsPreferred,ModifiedDate
C100,Alpine Ski House,Northwest,alpine@example.com,true,2024-01-10T09:00:00Z
C101,Blue Yonder Airlines,Southwest,blueyonder@example.com,false,2024-01-10T09:00:00Z
C102,Contoso Retail,Central,contoso@example.com,true,2024-01-10T09:00:00Z
C103,Fabrikam Services,Northeast,fabrikam@example.com,false,2024-01-10T09:00:00Z
'@
        Set-Content -Path (Join-Path $SamplesRoot 'customers_baseline.csv') -Value $customersCsv -Force

        $customersDeltaCsv = @'
CustomerID,CustomerName,Region,Email,IsPreferred,ModifiedDate,ExpectedSCDAction
C101,Blue Yonder Airlines,Mountain,blueyonder@example.com,false,2024-01-14T08:15:00Z,EXPIRE_AND_INSERT
C103,Fabrikam Services,Northeast,enterprise-support@fabrikam.example,false,2024-01-14T08:30:00Z,EXPIRE_AND_INSERT
'@
        Set-Content -Path (Join-Path $SamplesRoot 'customers_changes.csv') -Value $customersDeltaCsv -Force

        $qualityDefectCsv = @'
OrderID,CustomerID,ProductID,OrderDate,Quantity,UnitPrice,OrderStatus,ModifiedDate,DefectType
1007,,P17,2024-01-14,-2,45.00,Submitted,2024-01-14T10:00:00Z,NULL_CUSTOMER_AND_NEGATIVE_QUANTITY
'@
        Set-Content -Path (Join-Path $SamplesRoot 'quality_defect.csv') -Value $qualityDefectCsv -Force

        $documentsRoot = Join-Path $SamplesRoot 'Documents'
        Ensure-Directory -Path $documentsRoot
        Set-Content -Path (Join-Path $documentsRoot 'contoso-order-brief-01.txt') -Value 'Contoso Operations order brief 01. Use this sample document for AI-assisted exploration and storage upload validation.' -Force
        Set-Content -Path (Join-Path $documentsRoot 'contoso-order-brief-02.txt') -Value 'Contoso Operations order brief 02. This file validates that bootstrap uploaded starter documents into blob storage.' -Force
        Set-Content -Path (Join-Path $documentsRoot 'customer-history-note.txt') -Value 'Customer history note. Use as sample prompt/document input for Foundry project exercises.' -Force

        $bronzeToSilverNotebook = @'
# Fabric notebook starter - Bronze to Silver quality gate
from pyspark.sql import functions as F

BRONZE_TABLE = "bronze_orders_cdc"
SILVER_TABLE = "silver_orders"
QUALITY_LOG_TABLE = "silver_quality_log"

bronze_df = spark.table(BRONZE_TABLE)

checks = {
    "null_customer": bronze_df.filter(F.col("CustomerID").isNull()).count(),
    "negative_quantity": bronze_df.filter(F.col("Quantity") <= 0).count(),
    "invalid_price": bronze_df.filter(F.col("UnitPrice") <= 0).count(),
    "missing_status": bronze_df.filter(F.col("OrderStatus").isNull()).count(),
    "stale_modifieddate": bronze_df.filter(F.col("ModifiedDate").isNull()).count()
}

failed_checks = [name for name, count in checks.items() if count > 0]

if failed_checks:
    raise Exception(f"Quality gate failed: {failed_checks}")
else:
    bronze_df.write.mode("overwrite").format("delta").saveAsTable(SILVER_TABLE)
'@
        Set-Content -Path (Join-Path $ScriptsRoot 'quality-gate-notebook.py') -Value $bronzeToSilverNotebook -Force

        $warehouseSql = @'
-- Customer dimension starter for SCD Type 2
CREATE TABLE dbo.dim_customer
(
    CustomerSK BIGINT NOT NULL,
    CustomerID VARCHAR(50) NOT NULL,
    CustomerName VARCHAR(200) NOT NULL,
    Region VARCHAR(100) NULL,
    Email VARCHAR(200) NULL,
    IsPreferred BIT NULL,
    EffectiveFrom DATETIME2 NOT NULL,
    EffectiveTo DATETIME2 NULL,
    IsCurrent BIT NOT NULL
);
'@
        Set-Content -Path (Join-Path $ScriptsRoot 'create-dim-customer.sql') -Value $warehouseSql -Force

        $recoverySql = @'
-- Delta Lake investigation helpers
DESCRIBE HISTORY silver_orders;
-- Example restore command to use after identifying a valid version:
-- RESTORE TABLE silver_orders TO VERSION AS OF 1;
-- Example shallow clone pattern:
-- CREATE TABLE silver_orders_backup SHALLOW CLONE silver_orders VERSION AS OF 1;
'@
        Set-Content -Path (Join-Path $ScriptsRoot 'delta-recovery.sql') -Value $recoverySql -Force

        Set-Content -Path (Join-Path $PublicDesktop 'Microsoft Fabric.url') -Value "[InternetShortcut]`r`nURL=https://app.fabric.microsoft.com`r`n" -Force
        Set-Content -Path (Join-Path $PublicDesktop 'Microsoft Learn - Fabric.url') -Value "[InternetShortcut]`r`nURL=https://learn.microsoft.com/fabric/`r`n" -Force
        Set-Content -Path (Join-Path $PublicDesktop 'Azure Portal.url') -Value "[InternetShortcut]`r`nURL=https://portal.azure.com`r`n" -Force
        Set-Content -Path (Join-Path $PublicDesktop 'Azure AI Foundry.url') -Value "[InternetShortcut]`r`nURL=https://ai.azure.com`r`n" -Force

        if (-not (Test-Path $DesktopShortcutsPath)) {
            New-Item -Path $DesktopShortcutsPath -ItemType Junction -Value $LabRoot | Out-Null
        }
    }

    function Get-AzCliPath {
        $cmd = (Get-Command az.cmd -ErrorAction SilentlyContinue).Source
        if (-not $cmd) {
            $cmd = (Get-Command az -ErrorAction SilentlyContinue).Source
        }
        if (-not $cmd) {
            throw 'Azure CLI was not found after installation.'
        }
        return $cmd
    }

    function Invoke-AzJson {
        param(
            [Parameter(Mandatory = $true)]
            [string[]]$Arguments,
            [switch]$AllowFailure
        )

        $azCmd = Get-AzCliPath
        $output = & $azCmd @Arguments 2>&1
        if ($LASTEXITCODE -ne 0) {
            if ($AllowFailure) {
                return $null
            }
            throw "Azure CLI command failed: az $($Arguments -join ' ')`n$output"
        }

        if (-not $output) {
            return $null
        }

        $text = ($output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            return $null
        }

        return $text | ConvertFrom-Json
    }

    function Connect-AzureForLab {
        Write-Log 'Authenticating Azure CLI with CloudLabs user credentials.'
        $azCmd = Get-AzCliPath

        & $azCmd login --service-principal -u $AzureUserName -p $AzurePassword --tenant $AzureTenantID 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Log 'Service principal login failed. Trying user-based login.'
            & $azCmd login -u $AzureUserName -p $AzurePassword --tenant $AzureTenantID
            if ($LASTEXITCODE -ne 0) {
                throw 'Azure CLI login failed for both service principal and user auth flows.'
            }
        }

        & $azCmd account set --subscription $AzureSubscriptionID
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to set Azure subscription context.'
        }
    }

    function Get-ResourceGroupForDeployment {
        Write-Log 'Discovering deployment resource group from deployment identifier tags.'
        $groups = Invoke-AzJson -Arguments @('group', 'list', '--query', "[?tags.DeploymentID=='$DeploymentID' || tags.deploymentId=='$DeploymentID' || tags.ODLID=='$ODLID' || tags.odlid=='$ODLID'].{name:name,id:id}") -AllowFailure
        if ($groups -and $groups.Count -gt 0) {
            return $groups[0].name
        }

        $vmName = $env:COMPUTERNAME
        $vm = Invoke-AzJson -Arguments @('vm', 'list', '--query', "[?name=='$vmName'].{resourceGroup:resourceGroup,name:name}") -AllowFailure
        if ($vm -and $vm.Count -gt 0) {
            return $vm[0].resourceGroup
        }

        $allGroups = Invoke-AzJson -Arguments @('group', 'list')
        if ($allGroups.Count -eq 1) {
            return $allGroups[0].name
        }

        throw 'Unable to determine the Azure resource group for this lab deployment.'
    }

    function Get-AzureOpenAiDetails {
        param([string]$ResourceGroupName)

        Write-Log "Discovering Azure OpenAI account in resource group $ResourceGroupName."
        $accounts = Invoke-AzJson -Arguments @('cognitiveservices', 'account', 'list', '--resource-group', $ResourceGroupName)
        $openAiAccount = $accounts | Where-Object { $_.kind -eq 'OpenAI' } | Select-Object -First 1
        if (-not $openAiAccount) {
            throw "No Azure OpenAI account was found in resource group $ResourceGroupName."
        }

        $accountShow = Invoke-AzJson -Arguments @('cognitiveservices', 'account', 'show', '--name', $openAiAccount.name, '--resource-group', $ResourceGroupName)
        $keys = Invoke-AzJson -Arguments @('cognitiveservices', 'account', 'keys', 'list', '--name', $openAiAccount.name, '--resource-group', $ResourceGroupName)
        $deployments = Invoke-AzJson -Arguments @('cognitiveservices', 'account', 'deployment', 'list', '--name', $openAiAccount.name, '--resource-group', $ResourceGroupName) -AllowFailure

        $deploymentName = $null
        if ($deployments) {
            $selectedDeployment = $deployments | Select-Object -First 1
            if ($selectedDeployment -and $selectedDeployment.name) {
                $deploymentName = $selectedDeployment.name
            }
        }

        if (-not $deploymentName) {
            $resourceDeployments = Invoke-AzJson -Arguments @('resource', 'list', '--resource-group', $ResourceGroupName, '--resource-type', 'Microsoft.CognitiveServices/accounts/deployments') -AllowFailure
            if ($resourceDeployments) {
                $matching = $resourceDeployments | Where-Object { $_.id -like "*/accounts/$($openAiAccount.name)/deployments/*" } | Select-Object -First 1
                if ($matching) {
                    $deploymentName = ($matching.name -split '/')[-1]
                }
            }
        }

        if (-not $deploymentName) {
            throw "No model deployment was found under Azure OpenAI account $($openAiAccount.name)."
        }

        return [ordered]@{
            ResourceName = $openAiAccount.name
            ResourceGroup = $ResourceGroupName
            Endpoint = $accountShow.properties.endpoint
            ApiKey = $keys.key1
            DeploymentName = $deploymentName
            ResourceId = $openAiAccount.id
            Location = $openAiAccount.location
        }
    }

    function Get-AiFoundryProjectDetails {
        param([string]$ResourceGroupName)

        Write-Log "Discovering Azure AI Foundry project/workspace in resource group $ResourceGroupName."
        $project = $null
        $projectSource = $null

        $accountProjects = Invoke-AzJson -Arguments @('resource', 'list', '--resource-group', $ResourceGroupName, '--resource-type', 'Microsoft.CognitiveServices/accounts/projects') -AllowFailure
        if ($accountProjects) {
            $project = $accountProjects | Select-Object -First 1
            $projectSource = 'CognitiveServicesProject'
        }

        if (-not $project) {
            $mlProjects = Invoke-AzJson -Arguments @('resource', 'list', '--resource-group', $ResourceGroupName, '--resource-type', 'Microsoft.MachineLearningServices/workspaces') -AllowFailure
            if ($mlProjects) {
                $project = ($mlProjects | Where-Object { $_.kind -eq 'Project' } | Select-Object -First 1)
                if (-not $project) {
                    $project = ($mlProjects | Where-Object { $_.kind -eq 'Hub' } | Select-Object -First 1)
                }
                if (-not $project) {
                    $project = $mlProjects | Select-Object -First 1
                }
                $projectSource = 'MachineLearningWorkspace'
            }
        }

        if (-not $project) {
            throw "No Azure AI Foundry project or workspace was found in resource group $ResourceGroupName."
        }

        $projectName = ($project.name -split '/')[-1]
        $parentAccountName = $null
        $projectEndpoint = $null
        $projectKind = $project.kind

        if ($projectSource -eq 'CognitiveServicesProject') {
            $nameParts = $project.name -split '/'
            if ($nameParts.Count -ge 2) {
                $parentAccountName = $nameParts[0]
            }
            if ($parentAccountName) {
                $projectShow = Invoke-AzJson -Arguments @('cognitiveservices', 'account', 'project', 'show', '--name', $parentAccountName, '--resource-group', $ResourceGroupName, '--project-name', $projectName) -AllowFailure
                if ($projectShow) {
                    if ($projectShow.properties.endpoint) {
                        $projectEndpoint = $projectShow.properties.endpoint
                    }
                    elseif ($projectShow.endpoint) {
                        $projectEndpoint = $projectShow.endpoint
                    }
                }
            }
        }

        if (-not $projectEndpoint -and $project.properties -and $project.properties.endpoint) {
            $projectEndpoint = $project.properties.endpoint
        }

        if (-not $projectEndpoint -and $project.properties -and $project.properties.discoveryUrl) {
            $projectEndpoint = $project.properties.discoveryUrl
        }

        if (-not $projectEndpoint -and $parentAccountName) {
            $parentAccount = Invoke-AzJson -Arguments @('cognitiveservices', 'account', 'show', '--name', $parentAccountName, '--resource-group', $ResourceGroupName) -AllowFailure
            if ($parentAccount -and $parentAccount.properties.endpoint) {
                $projectEndpoint = $parentAccount.properties.endpoint
            }
        }

        if (-not $projectEndpoint -and $projectSource -eq 'MachineLearningWorkspace') {
            $workspaceShow = Invoke-AzJson -Arguments @('resource', 'show', '--ids', $project.id) -AllowFailure
            if ($workspaceShow -and $workspaceShow.properties -and $workspaceShow.properties.discoveryUrl) {
                $projectEndpoint = $workspaceShow.properties.discoveryUrl
            }
        }

        return [ordered]@{
            ProjectName = $projectName
            ParentAccountName = $parentAccountName
            ResourceGroup = $ResourceGroupName
            ResourceId = $project.id
            Endpoint = $projectEndpoint
            Kind = $projectKind
            Source = $projectSource
        }
    }

    function Get-FoundryAccessToken {
        Write-Log 'Requesting Azure AI Foundry access token via Azure CLI.'
        $token = Invoke-AzJson -Arguments @('account', 'get-access-token', '--resource', 'https://ai.azure.com') -AllowFailure
        if ($token -and $token.accessToken) {
            return $token.accessToken
        }

        $tokenMgmt = Invoke-AzJson -Arguments @('account', 'get-access-token', '--resource-type', 'arm') -AllowFailure
        if ($tokenMgmt -and $tokenMgmt.accessToken) {
            return $tokenMgmt.accessToken
        }

        throw 'Unable to acquire a usable Azure AI Foundry access token.'
    }

    function Get-StorageUploadTarget {
        param([string]$ResourceGroupName)

        Write-Log "Discovering storage account and upload container in resource group $ResourceGroupName."
        $accounts = Invoke-AzJson -Arguments @('storage', 'account', 'list', '--resource-group', $ResourceGroupName) -AllowFailure
        if (-not $accounts -or $accounts.Count -eq 0) {
            Write-Log 'No storage account was found in the lab resource group. Sample upload will be skipped.'
            return $null
        }

        $storage = $accounts | Select-Object -First 1
        $containers = Invoke-AzJson -Arguments @('storage', 'container', 'list', '--account-name', $storage.name, '--auth-mode', 'login') -AllowFailure
        $targetContainer = $null

        if ($containers -and $containers.Count -gt 0) {
            $preferredNames = @('documents', 'samples', 'input', 'inputs', 'data', 'labdocs')
            foreach ($preferredName in $preferredNames) {
                $targetContainer = $containers | Where-Object { $_.name -eq $preferredName } | Select-Object -First 1
                if ($targetContainer) {
                    break
                }
            }

            if (-not $targetContainer) {
                $targetContainer = $containers | Select-Object -First 1
            }
        }
        else {
            $targetContainerName = 'documents'
            $null = Invoke-AzJson -Arguments @('storage', 'container', 'create', '--account-name', $storage.name, '--name', $targetContainerName, '--auth-mode', 'login') -AllowFailure
            $targetContainer = [pscustomobject]@{ name = $targetContainerName }
        }

        if (-not $targetContainer) {
            return $null
        }

        $storageDetails = Invoke-AzJson -Arguments @('storage', 'account', 'show', '--name', $storage.name, '--resource-group', $ResourceGroupName)
        return [ordered]@{
            AccountName = $storage.name
            ContainerName = $targetContainer.name
            BlobEndpoint = $storageDetails.primaryEndpoints.blob
            ResourceId = $storage.id
        }
    }

    function Upload-SampleDocuments {
        param([hashtable]$StorageTarget)

        if (-not $StorageTarget) {
            return
        }

        $documentsRoot = Join-Path $SamplesRoot 'Documents'
        if (-not (Test-Path $documentsRoot)) {
            Write-Log 'No sample documents directory exists. Skipping blob upload.'
            return
        }

        Write-Log "Uploading sample documents from $documentsRoot to container $($StorageTarget.ContainerName) in account $($StorageTarget.AccountName)."
        $azCmd = Get-AzCliPath
        & $azCmd storage blob upload-batch --destination $StorageTarget.ContainerName --source $documentsRoot --account-name $StorageTarget.AccountName --auth-mode login --overwrite true --no-progress
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to upload sample documents to blob storage.'
        }
    }

    function Set-EnvValue {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path,
            [Parameter(Mandatory = $true)]
            [string]$Key,
            [AllowEmptyString()]
            [string]$Value
        )

        $content = @()
        if (Test-Path $Path) {
            $content = Get-Content -Path $Path
        }

        $escapedKey = [Regex]::Escape($Key)
        $newLine = "$Key=$Value"
        $matched = $false
        $updated = foreach ($line in $content) {
            if ($line -match "^$escapedKey=") {
                $matched = $true
                $newLine
            }
            else {
                $line
            }
        }

        if (-not $matched) {
            $updated += $newLine
        }

        Set-Content -Path $Path -Value $updated -Force
    }

    function Update-LabEnvFiles {
        param(
            [hashtable]$OpenAi,
            [hashtable]$Foundry,
            [string]$FoundryToken,
            [hashtable]$StorageTarget,
            [string]$ResourceGroupName
        )

        foreach ($envPath in $EnvPaths) {
            Ensure-Directory -Path (Split-Path -Path $envPath -Parent)
            if (-not (Test-Path $envPath)) {
                New-Item -Path $envPath -ItemType File -Force | Out-Null
            }

            Set-EnvValue -Path $envPath -Key 'AZURE_OPENAI_ENDPOINT' -Value $OpenAi.Endpoint
            Set-EnvValue -Path $envPath -Key 'AZURE_OPENAI_API_KEY' -Value $OpenAi.ApiKey
            Set-EnvValue -Path $envPath -Key 'AZURE_OPENAI_DEPLOYMENT' -Value $OpenAi.DeploymentName
            Set-EnvValue -Path $envPath -Key 'AZURE_OPENAI_RESOURCE_NAME' -Value $OpenAi.ResourceName
            Set-EnvValue -Path $envPath -Key 'AZURE_OPENAI_RESOURCE_GROUP' -Value $OpenAi.ResourceGroup
            Set-EnvValue -Path $envPath -Key 'AI_FOUNDRY_PROJECT_NAME' -Value $Foundry.ProjectName
            Set-EnvValue -Path $envPath -Key 'AI_FOUNDRY_PROJECT_ID' -Value $Foundry.ResourceId
            Set-EnvValue -Path $envPath -Key 'AI_FOUNDRY_PROJECT_ENDPOINT' -Value $Foundry.Endpoint
            Set-EnvValue -Path $envPath -Key 'AI_FOUNDRY_ACCOUNT_NAME' -Value $Foundry.ParentAccountName
            Set-EnvValue -Path $envPath -Key 'AI_FOUNDRY_TOKEN' -Value $FoundryToken
            Set-EnvValue -Path $envPath -Key 'AZURE_RESOURCE_GROUP' -Value $ResourceGroupName

            if ($StorageTarget) {
                Set-EnvValue -Path $envPath -Key 'STORAGE_ACCOUNT_NAME' -Value $StorageTarget.AccountName
                Set-EnvValue -Path $envPath -Key 'STORAGE_CONTAINER' -Value $StorageTarget.ContainerName
                Set-EnvValue -Path $envPath -Key 'STORAGE_BLOB_ENDPOINT' -Value $StorageTarget.BlobEndpoint
            }
        }
    }

    function Write-LabStateSummary {
        param(
            [string]$ResourceGroupName,
            [hashtable]$OpenAi,
            [hashtable]$Foundry,
            [hashtable]$StorageTarget
        )

        $summary = [ordered]@{
            DeploymentId = $DeploymentID
            ODLId = $ODLID
            AzureUserName = $AzureUserName
            AzureTenantId = $AzureTenantID
            AzureSubscriptionId = $AzureSubscriptionID
            AzureResourceGroup = $ResourceGroupName
            FabricPortal = 'https://app.fabric.microsoft.com'
            WorkspaceNameHint = "contoso-fabric-$DeploymentID"
            LakehouseName = 'ContosoOperationsLakehouse'
            WarehouseName = 'ContosoOperationsWarehouse'
            BronzeTable = 'bronze_orders_cdc'
            SilverTable = 'silver_orders'
            GoldDimension = 'dim_customer'
            LabRoot = $LabRoot
            AzureOpenAI = $OpenAi
            AIFoundry = $Foundry
            StorageUploadTarget = $StorageTarget
            SourcesValidatedAgainst = @(
                'https://learn.microsoft.com/fabric/data-science/python-guide/python-overview',
                'https://learn.microsoft.com/fabric/data-engineering/fabric-notebook-selection-guide',
                'https://learn.microsoft.com/fabric/data-factory/cdc-copy-job',
                'https://learn.microsoft.com/fabric/data-factory/cdc-copy-job-azure-sql-database',
                'https://learn.microsoft.com/fabric/data-factory/slowly-changing-dimension-type-two',
                'https://learn.microsoft.com/fabric/data-warehouse/dimensional-modeling-dimension-tables',
                'https://learn.microsoft.com/fabric/data-engineering/delta-lake-time-travel',
                'https://learn.microsoft.com/fabric/data-engineering/delta-lake-restore',
                'https://learn.microsoft.com/fabric/data-engineering/delta-lake-clone',
                'https://learn.microsoft.com/azure/ai-foundry/openai/how-to/create-resource#retrieve-information-about-the-resource',
                'https://learn.microsoft.com/azure/foundry/how-to/create-projects#create-multiple-projects-on-the-same-resource',
                'https://learn.microsoft.com/azure/foundry/how-to/develop/sdk-overview',
                'https://learn.microsoft.com/azure/storage/blobs/storage-quickstart-blobs-cli#upload-a-blob'
            )
        }

        $summary | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $LabRoot 'lab-state.json') -Force
    }

    CreateCredFile
    Ensure-TrainerAccount
    Install-LabTools
    Initialize-LabContent
    Connect-AzureForLab

    $resourceGroupName = Get-ResourceGroupForDeployment
    $openAiDetails = Get-AzureOpenAiDetails -ResourceGroupName $resourceGroupName
    $foundryDetails = Get-AiFoundryProjectDetails -ResourceGroupName $resourceGroupName
    $foundryToken = Get-FoundryAccessToken
    $storageTarget = Get-StorageUploadTarget -ResourceGroupName $resourceGroupName
    Upload-SampleDocuments -StorageTarget $storageTarget
    Update-LabEnvFiles -OpenAi $openAiDetails -Foundry $foundryDetails -FoundryToken $foundryToken -StorageTarget $storageTarget -ResourceGroupName $resourceGroupName
    Write-LabStateSummary -ResourceGroupName $resourceGroupName -OpenAi $openAiDetails -Foundry $foundryDetails -StorageTarget $storageTarget

    Write-Log 'Stage 1 Fabric challenge lab VM bootstrap completed successfully.'
}
catch {
    Write-Error $_.Exception.Message
    throw
}
finally {
    Stop-Transcript
}
