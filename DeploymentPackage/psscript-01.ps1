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

    [Parameter(Mandatory = $false)]
    [string]$InstallCloudLabsShadow = 'true',

    [Parameter(Mandatory = $true)]
    [string]$DeploymentID,

    [Parameter(Mandatory = $true)]
    [string]$vmAdminUsername,

    [Parameter(Mandatory = $true)]
    [string]$vmAdminPassword,

    [Parameter(Mandatory = $true)]
    [string]$trainerUserName,

    [Parameter(Mandatory = $true)]
    [string]$trainerUserPassword,

    [Parameter(Mandatory = $true)]
    [string]$SqlServerFqdn,

    [Parameter(Mandatory = $true)]
    [string]$SqlDatabaseName,

    [Parameter(Mandatory = $true)]
    [string]$SqlAdminUsername,

    [Parameter(Mandatory = $true)]
    [string]$SqlAdminPassword
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
$ValidationRoot = Join-Path $LabFilesPath 'validation'
$EnvPath = Join-Path $LabFilesPath '.env'

# The deployment-time deterministic name for the validation storage account.
# This MUST stay in lockstep with Exercise-01.md, Exercise-05.md/06.md, and every
# Validations/*.ps1 script - all four derive the same name from DeploymentID.
$deploymentIdNoHyphens = $DeploymentID.Replace('-', '').ToLower()
$ValidationStorageAccountName = 'stfabricval' + $deploymentIdNoHyphens.Substring(0, [Math]::Min(12, $deploymentIdNoHyphens.Length))
$ValidationContainerName = 'validation'

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

        # Convenience tooling only. None of it is required to complete the lab, so a failure here
        # must never abort the bootstrap - the SQL provisioning that the whole lab depends on runs
        # after this function, and $ErrorActionPreference = 'Stop' would otherwise kill it.
        foreach ($package in $packages) {
            try {
                Write-Log "Installing package: $package"
                choco install $package -y --no-progress --ignore-checksums
            }
            catch {
                Write-Log "Non-fatal: could not install '$package' ($($_.Exception.Message)). Continuing."
            }
        }

        try {
            $azCmd = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
            if (Test-Path $azCmd) {
                Write-Log 'Upgrading Azure CLI to ensure latest command surface.'
                & $azCmd upgrade --yes
            }
        }
        catch {
            Write-Log "Non-fatal: Azure CLI upgrade failed ($($_.Exception.Message)). Continuing."
        }

        try {
            $codeCmd = 'C:\Program Files\Microsoft VS Code\bin\code.cmd'
            if (Test-Path $codeCmd) {
                Write-Log 'Installing VS Code extensions for Fabric authoring.'
                foreach ($ext in @('ms-python.python', 'ms-toolsai.jupyter', 'ms-azuretools.vscode-azurecli', 'ms-mssql.mssql')) {
                    & $codeCmd --install-extension $ext --force
                }
            }
        }
        catch {
            Write-Log "Non-fatal: VS Code extension install failed ($($_.Exception.Message)). Continuing."
        }

        # python may not be on PATH yet in this session immediately after choco installs it.
        try {
            if (Get-Command python -ErrorAction SilentlyContinue) {
                Write-Log 'Installing Python helper packages.'
                & python -m pip install --upgrade pip
                & python -m pip install pandas pyarrow deltalake python-dotenv
            }
            else {
                Write-Log 'Non-fatal: python is not on PATH in this session. Skipping Python helper packages.'
            }
        }
        catch {
            Write-Log "Non-fatal: Python package install failed ($($_.Exception.Message)). Continuing."
        }

        # Everything below IS required. Failures here should abort the bootstrap.
        Write-Log 'Installing PowerShell modules required by the bootstrap and by the lab exercises.'
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue

        # SqlServer: used below to provision Contoso_Operations.
        if (-not (Get-Module -ListAvailable -Name SqlServer)) {
            Install-Module -Name SqlServer -Force -AllowClobber -Scope AllUsers -ErrorAction Stop
        }
        Import-Module SqlServer -ErrorAction Stop

        # Az.Accounts / Az.Storage: used by the learner in Challenges 2-6 to upload validation
        # evidence (Connect-AzAccount, Get-AzStorageAccount, Set-AzStorageBlobContent). Do not
        # assume the base image ships these - the evidence upload steps fail without them.
        foreach ($module in @('Az.Accounts', 'Az.Storage')) {
            if (-not (Get-Module -ListAvailable -Name $module)) {
                Write-Log "Installing PowerShell module: $module"
                Install-Module -Name $module -Force -AllowClobber -Scope AllUsers -ErrorAction Stop
            }
        }
    }

    function Initialize-LabFolders {
        foreach ($path in @($LabFilesPath, $LabRoot, $SamplesRoot, $ScriptsRoot, $DocsRoot, $LogsRoot, $ValidationRoot)) {
            Ensure-Directory -Path $path
        }
    }

    function Write-LabReadme {
        $readme = @'
# Enterprise Data Quality at Scale in Fabric

This workstation is preconfigured for the Fabric challenge lab.

Included assets:
- Azure credential helper files on the desktop and in C:\LabFiles
- Sample data files for the Warehouse/dimension exercises under C:\LabFiles\FabricChallengeLab\Samples
- The Contoso_Operations order-change simulation script under C:\LabFiles\FabricChallengeLab\Scripts
- C:\LabFiles\validation, used throughout the lab to stage evidence files before they are uploaded to the validation storage account
- Browser shortcuts for Microsoft Fabric, Microsoft Learn, and the Azure portal

Source system:
- The Contoso_Operations Azure SQL database (Orders, Customers, Products) is pre-provisioned with CDC enabled on
  dbo.Orders. Connection details are in C:\LabFiles\.env.

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

IMPORTANT: Fabric notebooks run on remote Spark compute, not on this VM. Any lab step that saves a
validation evidence file to C:\LabFiles\validation must be run from a local PowerShell window on this
VM, using literal values you copied from Fabric (row counts, version numbers, statuses) - never from
inside a notebook cell, which cannot see this VM's file system.
'@
        Set-Content -Path (Join-Path $LabRoot 'README.md') -Value $readme -Force
    }

    function Write-LabEnvFile {
        $envContent = @"
FABRIC_PORTAL_URL=https://app.fabric.microsoft.com
FABRIC_WORKSPACE_NAME_HINT=contoso-fabric-$DeploymentID
FABRIC_LAKEHOUSE_NAME=contoso_medallion_lh
FABRIC_WAREHOUSE_NAME=contoso_gold_wh
FABRIC_COPYJOB_NAME=orders-to-bronze-cdc
FABRIC_PIPELINE_NAME=contoso-medallion-orchestration
FABRIC_NOTEBOOK_NAME=nb_data_quality_gate
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
VALIDATION_ROOT=$ValidationRoot
SQL_SERVER_FQDN=$SqlServerFqdn
SQL_DATABASE_NAME=$SqlDatabaseName
SQL_ADMIN_USERNAME=$SqlAdminUsername
SQL_ADMIN_PASSWORD=$SqlAdminPassword
VALIDATION_STORAGE_ACCOUNT=$ValidationStorageAccountName
VALIDATION_CONTAINER=$ValidationContainerName
"@
        Set-Content -Path $EnvPath -Value $envContent -Force
    }

    function New-CustomerRows {
        $segments = @('Enterprise', 'SMB', 'Consumer', 'Public Sector', 'Education')
        $countries = @('United States', 'Canada', 'United Kingdom', 'Germany', 'France', 'Australia', 'India', 'Japan', 'Brazil', 'Mexico')

        $rows = New-Object System.Collections.Generic.List[object]
        for ($i = 1; $i -le 5000; $i++) {
            $rows.Add([pscustomobject]@{
                CustomerID   = $i
                CustomerName = "Contoso Customer $i"
                Segment      = $segments[$i % $segments.Count]
                Country      = $countries[$i % $countries.Count]
            })
        }

        return [pscustomobject]@{
            Rows      = $rows
            Segments  = $segments
            Countries = $countries
        }
    }

    function Write-CustomerSamples {
        param($CustomerData)

        $rows = $CustomerData.Rows
        $segments = $CustomerData.Segments
        $countries = $CustomerData.Countries

        $rows | Export-Csv -Path (Join-Path $SamplesRoot 'customers_baseline.csv') -NoTypeInformation -Force

        $changeRows = New-Object System.Collections.Generic.List[object]
        for ($i = 1; $i -le 200; $i++) {
            $customerId = $i * 25
            $baseline = $rows[$customerId - 1]
            $newSegment = $segments[($segments.IndexOf($baseline.Segment) + 1) % $segments.Count]
            $newCountry = $countries[($countries.IndexOf($baseline.Country) + 1) % $countries.Count]

            $changeRows.Add([pscustomobject]@{
                CustomerID   = $customerId
                CustomerName = $baseline.CustomerName
                Segment      = $newSegment
                Country      = $newCountry
            })
        }
        $changeRows | Export-Csv -Path (Join-Path $SamplesRoot 'customers_changes.csv') -NoTypeInformation -Force

        return $changeRows
    }

    function Write-QualityDefectSample {
        param($Countries)

        $rows = New-Object System.Collections.Generic.List[object]
        for ($i = 1; $i -le 100; $i++) {
            $orderId = if ($i -le 10) { '' } else { 900000 + $i }
            $unitPrice = [math]::Round((($i % 50) + 10) * 1.5, 2)
            $quantity = ($i % 10) + 1

            $rows.Add([pscustomobject]@{
                OrderID         = $orderId
                CustomerID      = ($i % 5000) + 1
                OrderDate       = (Get-Date).AddDays(-$i).ToString('yyyy-MM-dd')
                ShipDate        = (Get-Date).AddDays(-$i + 3).ToString('yyyy-MM-dd')
                OrderStatus     = 'Submitted'
                ProductID       = ($i % 500) + 1
                Quantity        = $quantity
                UnitPrice       = $unitPrice
                Discount        = 0
                Revenue         = [math]::Round($unitPrice * $quantity, 2)
                ShippingCountry = $Countries[$i % $Countries.Count]
                PaymentMethod   = 'CreditCard'
            })
        }

        $rows | Export-Csv -Path (Join-Path $SamplesRoot 'quality_defect.csv') -NoTypeInformation -Force
    }

    function Write-ProvisioningSqlScript {
        $sql = @'
IF OBJECT_ID('dbo.Orders','U') IS NOT NULL DROP TABLE dbo.Orders;
CREATE TABLE dbo.Orders (
    OrderID         INT NOT NULL PRIMARY KEY,
    CustomerID      INT NOT NULL,
    OrderDate       DATE NOT NULL,
    ShipDate        DATE NULL,
    OrderStatus     VARCHAR(20) NOT NULL,
    ProductID       INT NOT NULL,
    Quantity        INT NOT NULL,
    UnitPrice       DECIMAL(10,2) NOT NULL,
    Discount        DECIMAL(5,2) NOT NULL,
    Revenue         DECIMAL(12,2) NOT NULL,
    ShippingCountry VARCHAR(50) NOT NULL,
    PaymentMethod   VARCHAR(30) NOT NULL
);

IF OBJECT_ID('dbo.Customers','U') IS NOT NULL DROP TABLE dbo.Customers;
CREATE TABLE dbo.Customers (
    CustomerID   INT NOT NULL PRIMARY KEY,
    CustomerName VARCHAR(200) NOT NULL,
    Segment      VARCHAR(50) NOT NULL,
    Country      VARCHAR(50) NOT NULL
);

IF OBJECT_ID('dbo.Products','U') IS NOT NULL DROP TABLE dbo.Products;
CREATE TABLE dbo.Products (
    ProductID   INT NOT NULL PRIMARY KEY,
    ProductName VARCHAR(200) NOT NULL,
    Category    VARCHAR(100) NOT NULL
);

;WITH Tally AS (
    SELECT TOP (1000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM sys.all_objects
)
INSERT INTO dbo.Products (ProductID, ProductName, Category)
SELECT rn, CONCAT('Product ', rn),
    CASE (rn % 5)
        WHEN 0 THEN 'Hardware' WHEN 1 THEN 'Software' WHEN 2 THEN 'Services'
        WHEN 3 THEN 'Accessories' ELSE 'Support'
    END
FROM Tally;

;WITH Tally AS (
    SELECT TOP (100000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.Orders (OrderID, CustomerID, OrderDate, ShipDate, OrderStatus, ProductID, Quantity, UnitPrice, Discount, Revenue, ShippingCountry, PaymentMethod)
SELECT
    rn AS OrderID,
    ((rn - 1) % 5000) + 1 AS CustomerID,
    DATEADD(DAY, -(rn % 400), CAST(GETDATE() AS DATE)) AS OrderDate,
    DATEADD(DAY, -(rn % 400) + 3, CAST(GETDATE() AS DATE)) AS ShipDate,
    CASE (rn % 4) WHEN 0 THEN 'Submitted' WHEN 1 THEN 'Shipped' WHEN 2 THEN 'Delivered' ELSE 'Cancelled' END,
    ((rn - 1) % 1000) + 1 AS ProductID,
    ((rn % 10) + 1) AS Quantity,
    CAST((((rn % 50) + 10) * 1.25) AS DECIMAL(10,2)) AS UnitPrice,
    CAST((rn % 5) AS DECIMAL(5,2)) AS Discount,
    CAST(((((rn % 50) + 10) * 1.25) * ((rn % 10) + 1)) AS DECIMAL(12,2)) AS Revenue,
    CASE (rn % 10)
        WHEN 0 THEN 'United States' WHEN 1 THEN 'Canada' WHEN 2 THEN 'United Kingdom'
        WHEN 3 THEN 'Germany' WHEN 4 THEN 'France' WHEN 5 THEN 'Australia'
        WHEN 6 THEN 'India' WHEN 7 THEN 'Japan' WHEN 8 THEN 'Brazil' ELSE 'Mexico'
    END,
    CASE (rn % 3) WHEN 0 THEN 'CreditCard' WHEN 1 THEN 'PayPal' ELSE 'BankTransfer' END
FROM Tally;

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = DB_NAME() AND is_cdc_enabled = 1)
BEGIN
    EXEC sys.sp_cdc_enable_db;
END

IF NOT EXISTS (SELECT 1 FROM cdc.change_tables WHERE capture_instance = 'dbo_Orders')
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name   = N'Orders',
        @role_name     = NULL,
        @supports_net_changes = 1;
END
'@
        $sqlPath = Join-Path $ScriptsRoot 'provision-contoso-operations.sql'
        Set-Content -Path $sqlPath -Value $sql -Force
        return $sqlPath
    }

    function Write-CustomerSeedSqlScript {
        param($Rows)

        $builder = New-Object System.Text.StringBuilder
        $batchSize = 500
        for ($start = 0; $start -lt $Rows.Count; $start += $batchSize) {
            $batch = $Rows[$start..([Math]::Min($start + $batchSize - 1, $Rows.Count - 1))]
            $valueLines = foreach ($row in $batch) {
                $name = $row.CustomerName.Replace("'", "''")
                "($($row.CustomerID), N'$name', N'$($row.Segment)', N'$($row.Country)')"
            }
            [void]$builder.AppendLine("INSERT INTO dbo.Customers (CustomerID, CustomerName, Segment, Country) VALUES")
            [void]$builder.AppendLine(($valueLines -join ",`r`n"))
            [void]$builder.AppendLine(";")
        }

        $sqlPath = Join-Path $ScriptsRoot 'seed-customers.sql'
        Set-Content -Path $sqlPath -Value $builder.ToString() -Force
        return $sqlPath
    }

    function Write-OrderChangeSimulationAssets {
        $sql = @'
-- Simulates the incremental Contoso_Operations.Orders change set used in Challenge 2, Task 4.
-- Safe to run only once per deployment: the INSERT block is skipped if it already ran.
IF NOT EXISTS (SELECT 1 FROM dbo.Orders WHERE OrderID = 100001)
BEGIN
    ;WITH Tally AS (
        SELECT TOP (350) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
        FROM sys.all_objects
    )
    INSERT INTO dbo.Orders (OrderID, CustomerID, OrderDate, ShipDate, OrderStatus, ProductID, Quantity, UnitPrice, Discount, Revenue, ShippingCountry, PaymentMethod)
    SELECT
        100000 + rn,
        ((rn - 1) % 5000) + 1,
        CAST(GETDATE() AS DATE),
        DATEADD(DAY, 3, CAST(GETDATE() AS DATE)),
        'Submitted',
        ((rn - 1) % 1000) + 1,
        ((rn % 10) + 1),
        CAST((((rn % 50) + 10) * 1.25) AS DECIMAL(10,2)),
        CAST((rn % 5) AS DECIMAL(5,2)),
        CAST(((((rn % 50) + 10) * 1.25) * ((rn % 10) + 1)) AS DECIMAL(12,2)),
        'United States',
        'CreditCard'
    FROM Tally;
END

UPDATE TOP (150) dbo.Orders
SET OrderStatus = 'Shipped',
    ShipDate = CAST(GETDATE() AS DATE)
WHERE OrderID BETWEEN 1 AND 150;
'@
        Set-Content -Path (Join-Path $ScriptsRoot 'apply-order-changes.sql') -Value $sql -Force

        $wrapper = @'
# Applies ~500 changed/new rows to Contoso_Operations.Orders (350 inserts + 150 updates).
# Run this ONCE, after the Copy job's baseline load has succeeded (Challenge 2, Task 3),
# then rerun the orders-to-bronze-cdc Copy job to capture the change set.
$ErrorActionPreference = 'Stop'
$envPath = 'C:\LabFiles\.env'
if (-not (Test-Path $envPath)) {
    throw "Cannot find $envPath. Re-run the lab VM bootstrap or contact support."
}

$envMap = @{}
Get-Content $envPath | ForEach-Object {
    if ($_ -match '^(?<k>[A-Z0-9_]+)=(?<v>.*)$') { $envMap[$Matches.k] = $Matches.v }
}

Import-Module SqlServer -ErrorAction Stop
Invoke-Sqlcmd -ServerInstance $envMap['SQL_SERVER_FQDN'] `
    -Database $envMap['SQL_DATABASE_NAME'] `
    -Username $envMap['SQL_ADMIN_USERNAME'] `
    -Password $envMap['SQL_ADMIN_PASSWORD'] `
    -InputFile (Join-Path $PSScriptRoot 'apply-order-changes.sql') `
    -TrustServerCertificate

Write-Host 'Applied the Contoso_Operations order change set (approximately 500 rows). Now rerun the orders-to-bronze-cdc Copy job in Fabric.'
'@
        Set-Content -Path (Join-Path $ScriptsRoot 'Apply-OrderChanges.ps1') -Value $wrapper -Force

        $readme = @'
# FabricChallengeLab\Scripts

Apply-OrderChanges.ps1
  Run this from a local PowerShell window on this VM (not from a Fabric notebook) after the Copy
  job's first (baseline) run has succeeded. It inserts ~350 new Orders rows and updates ~150
  existing rows, giving you the ~500-row change set that Challenge 2, Task 4 asks you to capture
  with a second Copy job run. Safe to run only once per deployment.

provision-contoso-operations.sql / seed-customers.sql
  Used by the lab bootstrap to create and seed the Contoso_Operations database. You do not need
  to run these yourself.
'@
        Set-Content -Path (Join-Path $ScriptsRoot 'README.txt') -Value $readme -Force
    }

    function Write-DesktopShortcuts {
        Set-Content -Path (Join-Path $PublicDesktop 'Microsoft Fabric.url') -Value "[InternetShortcut]`r`nURL=https://app.fabric.microsoft.com`r`n" -Force
        Set-Content -Path (Join-Path $PublicDesktop 'Microsoft Learn - Fabric.url') -Value "[InternetShortcut]`r`nURL=https://learn.microsoft.com/fabric/`r`n" -Force
        Set-Content -Path (Join-Path $PublicDesktop 'Azure Portal.url') -Value "[InternetShortcut]`r`nURL=https://portal.azure.com`r`n" -Force

        $desktopShortcutsPath = Join-Path $PublicDesktop 'Fabric Lab Files'
        if (-not (Test-Path $desktopShortcutsPath)) {
            New-Item -Path $desktopShortcutsPath -ItemType Junction -Value $LabRoot | Out-Null
        }
    }

    function Deploy-ContosoOperationsDatabase {
        Write-Log "Provisioning schema, sample data, and CDC on $SqlDatabaseName ($SqlServerFqdn)."

        $customerData = New-CustomerRows
        Write-CustomerSamples -CustomerData $customerData | Out-Null
        Write-QualityDefectSample -Countries $customerData.Countries

        $schemaScriptPath = Write-ProvisioningSqlScript
        $customerSeedPath = Write-CustomerSeedSqlScript -Rows $customerData.Rows
        Write-OrderChangeSimulationAssets

        $sqlParams = @{
            ServerInstance         = $SqlServerFqdn
            Database               = $SqlDatabaseName
            Username               = $SqlAdminUsername
            Password               = $SqlAdminPassword
            TrustServerCertificate = $true
            QueryTimeout           = 600
        }

        Write-Log 'Creating Orders/Customers/Products tables, seeding Orders and Products, and enabling CDC on dbo.Orders.'
        Invoke-Sqlcmd @sqlParams -InputFile $schemaScriptPath

        Write-Log 'Seeding the Customers table (must match customers_baseline.csv exactly).'
        Invoke-Sqlcmd @sqlParams -InputFile $customerSeedPath

        Write-Log 'Contoso_Operations provisioning complete.'
    }

    function Register-FabricSqlConnection {
        # Best-effort: pre-create a Fabric shareable cloud connection to Contoso_Operations so
        # Exercise 2 has a ready-made connection to select. This uses the Fabric REST API "Create
        # connection" surface, which has changed shape over time - if it fails, Exercise 2's own
        # instructions already cover creating the connection manually in the Fabric UI, so this
        # is never treated as fatal to the overall bootstrap.
        try {
            Write-Log 'Attempting to pre-create a Fabric connection for Contoso_Operations (best effort).'
            $azCmd = (Get-Command az.cmd -ErrorAction SilentlyContinue).Source
            if (-not $azCmd) { $azCmd = (Get-Command az -ErrorAction SilentlyContinue).Source }
            if (-not $azCmd) { throw 'Azure CLI was not found.' }

            $tokenJson = & $azCmd account get-access-token --resource 'https://api.fabric.microsoft.com' 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $tokenJson) { throw 'Unable to acquire a Fabric access token for connection pre-creation.' }
            $token = ($tokenJson | ConvertFrom-Json).accessToken

            $body = @{
                connectivityType  = 'ShareableCloud'
                displayName       = 'Contoso_Operations'
                connectionDetails = @{
                    type           = 'SQL'
                    creationMethod = 'SQL'
                    parameters     = @(
                        @{ dataType = 'Text'; name = 'server'; value = $SqlServerFqdn }
                        @{ dataType = 'Text'; name = 'database'; value = $SqlDatabaseName }
                    )
                }
                privacyLevel      = 'Organizational'
                credentialDetails = @{
                    credentials = @{
                        credentialType = 'Basic'
                        username       = $SqlAdminUsername
                        password       = $SqlAdminPassword
                    }
                }
            } | ConvertTo-Json -Depth 10

            Invoke-RestMethod -Method Post -Uri 'https://api.fabric.microsoft.com/v1/connections' `
                -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } `
                -Body $body -ErrorAction Stop | Out-Null

            Write-Log 'Fabric connection for Contoso_Operations created successfully.'
        }
        catch {
            Write-Log "Could not pre-create the Fabric connection automatically ($($_.Exception.Message)). This is non-fatal - Exercise 2 creates the connection manually if needed."
        }
    }

    function Write-LabStateSummary {
        $summary = [ordered]@{
            DeploymentId                = $DeploymentID
            ODLId                       = $ODLID
            AzureUserName               = $AzureUserName
            AzureTenantId               = $AzureTenantID
            AzureSubscriptionId         = $AzureSubscriptionID
            FabricPortal                = 'https://app.fabric.microsoft.com'
            WorkspaceNameHint           = "contoso-fabric-$DeploymentID"
            LakehouseName               = 'contoso_medallion_lh'
            WarehouseName               = 'contoso_gold_wh'
            CopyJobName                 = 'orders-to-bronze-cdc'
            PipelineName                = 'contoso-medallion-orchestration'
            NotebookName                = 'nb_data_quality_gate'
            BronzeTable                 = 'bronze_orders_cdc'
            SilverTable                 = 'silver_orders'
            GoldDimension               = 'dim_customer'
            SqlServerFqdn               = $SqlServerFqdn
            SqlDatabaseName             = $SqlDatabaseName
            ValidationStorageAccount    = $ValidationStorageAccountName
            ValidationContainer         = $ValidationContainerName
            LabRoot                     = $LabRoot
            SourcesValidatedAgainst     = @(
                'https://learn.microsoft.com/fabric/data-science/python-guide/python-overview',
                'https://learn.microsoft.com/fabric/data-engineering/fabric-notebook-selection-guide',
                'https://learn.microsoft.com/fabric/data-factory/cdc-copy-job',
                'https://learn.microsoft.com/fabric/data-factory/cdc-copy-job-azure-sql-database',
                'https://learn.microsoft.com/fabric/data-factory/slowly-changing-dimension-type-two',
                'https://learn.microsoft.com/fabric/data-warehouse/dimensional-modeling-dimension-tables',
                'https://learn.microsoft.com/fabric/data-engineering/delta-lake-time-travel',
                'https://learn.microsoft.com/fabric/data-engineering/delta-lake-restore',
                'https://learn.microsoft.com/fabric/data-engineering/delta-lake-clone'
            )
        }

        $summary | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $LabRoot 'lab-state.json') -Force
    }

    function Connect-AzureForLab {
        Write-Log 'Authenticating Azure CLI with CloudLabs user credentials.'
        $azCmd = (Get-Command az.cmd -ErrorAction SilentlyContinue).Source
        if (-not $azCmd) { $azCmd = (Get-Command az -ErrorAction SilentlyContinue).Source }
        if (-not $azCmd) { throw 'Azure CLI was not found after installation.' }

        & $azCmd login -u $AzureUserName -p $AzurePassword --tenant $AzureTenantID | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Azure CLI login failed.'
        }

        & $azCmd account set --subscription $AzureSubscriptionID
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to set Azure subscription context.'
        }
    }

    CreateCredFile
    Ensure-TrainerAccount
    Install-LabTools
    Initialize-LabFolders
    Write-LabReadme
    Write-LabEnvFile
    Deploy-ContosoOperationsDatabase
    Write-DesktopShortcuts

    # Everything essential to the lab (credentials, lab files, .env, and the Contoso_Operations
    # database with CDC) is complete by this point. The Azure CLI sign-in and the Fabric connection
    # pre-creation are conveniences, so do not let them fail the bootstrap.
    try {
        Connect-AzureForLab
        Register-FabricSqlConnection
    }
    catch {
        Write-Log "Non-fatal: Azure sign-in or Fabric connection pre-creation failed ($($_.Exception.Message)). The learner can sign in and create the connection manually."
    }

    Write-LabStateSummary

    Write-Log 'Fabric challenge lab VM bootstrap completed successfully.'
}
catch {
    Write-Error $_.Exception.Message
    throw
}
finally {
    Stop-Transcript
}
