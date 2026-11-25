param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("dev", "prod")]
    [string]$Environment,

    [switch]$ExecuteDeployment
)

$ErrorActionPreference = "Stop"

# Resolve project directories
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$TemplateDirectory = Join-Path $ProjectRoot "infrastructure/cloudformation"
$EnvironmentDirectory = Join-Path $ProjectRoot "infrastructure/environments"

Write-Host "======================================"
Write-Host " Coditude Infrastructure Deployment"
Write-Host " Environment: $Environment"
Write-Host "======================================"

# Verify required directories
if (-not (Test-Path $TemplateDirectory)) {
    throw "CloudFormation template directory not found: $TemplateDirectory"
}

if (-not (Test-Path $EnvironmentDirectory)) {
    throw "Environment configuration directory not found: $EnvironmentDirectory"
}

# Verify AWS CLI availability
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    throw "AWS CLI is not installed or not available in PATH."
}

Write-Host "Environment validation completed successfully."


# Load environment-specific configuration
$EnvironmentConfigFile = Join-Path $EnvironmentDirectory "$Environment.json"

if (-not (Test-Path $EnvironmentConfigFile)) {
    throw "Environment configuration not found: $EnvironmentConfigFile"
}

$EnvironmentConfig = Get-Content $EnvironmentConfigFile -Raw |
    ConvertFrom-Json

# Convert parameter JSON into a PowerShell hashtable
$EnvironmentParameters = @{}

foreach ($Parameter in $EnvironmentConfig) {
    $EnvironmentParameters[$Parameter.ParameterKey] =
        $Parameter.ParameterValue
}

# Define CloudFormation deployment order
$StackPlan = @(
    [PSCustomObject]@{
        Name = "network"
        DependsOn = "None"
    },
    [PSCustomObject]@{
        Name = "security-groups"
        DependsOn = "network"
    },
    [PSCustomObject]@{
        Name = "database"
        DependsOn = "network, security-groups"
    },
    [PSCustomObject]@{
        Name = "load-balancer"
        DependsOn = "network, security-groups"
    },
    [PSCustomObject]@{
        Name = "compute"
        DependsOn = "network, security-groups, database, load-balancer"
    },
    [PSCustomObject]@{
        Name = "codedeploy"
        DependsOn = "compute"
    }
)


# Verify all CloudFormation templates exist
foreach ($Stack in $StackPlan) {
    $TemplateFile = Join-Path $TemplateDirectory "$($Stack.Name).yaml"

    if (-not (Test-Path $TemplateFile)) {
        throw "Template not found: $TemplateFile"
    }
}

Write-Host ""
Write-Host "Environment configuration loaded successfully."
Write-Host "Environment: $Environment"
Write-Host ""

Write-Host "CloudFormation deployment order:"
$StackPlan | Format-Table Name, DependsOn -AutoSize

Write-Host "Environment parameters:"
$EnvironmentParameters.GetEnumerator() |
    Sort-Object Name |
    Format-Table Name, Value -AutoSize

Write-Host "Deployment plan validation completed successfully."
Write-Host "No AWS deployment has been performed."



# Define parameters accepted by each CloudFormation stack
$StackParameterMap = @{
    "network" = @(
        "EnvironmentName"
    )

    "security-groups" = @(
        "EnvironmentName",
        "VpcId"
    )

    "database" = @(
        "EnvironmentName",
        "DBInstanceClass"
    )

    "load-balancer" = @(
        "EnvironmentName",
        "VpcId"
    )

    "compute" = @(
        "EnvironmentName",
        "InstanceType",
        "MinSize",
        "DesiredCapacity",
        "MaxSize"
    )

        "codedeploy" = @(
        "EnvironmentName"
    )
}

Write-Host ""
Write-Host "Stack-specific parameter mapping:"

foreach ($Stack in $StackPlan) {
    Write-Host ""
    Write-Host "Stack: $($Stack.Name)"

    foreach ($ParameterName in $StackParameterMap[$Stack.Name]) {
        if ($ParameterName -eq "VpcId") {
            Write-Host "  VpcId = Retrieved from Network stack export"
        }
        else {
            $Value = $EnvironmentParameters[$ParameterName]
            Write-Host "  ${ParameterName} = $Value"
        }
    }
}

Write-Host ""
Write-Host "Stack parameter mapping validation completed."


# Validate stack parameter mappings
Write-Host ""
Write-Host "Validating stack parameters..."

foreach ($Stack in $StackPlan) {

    $StackName = $Stack.Name
    $Parameters = $StackParameterMap[$StackName]

    if ($null -eq $Parameters) {
        throw "Parameter mapping missing for stack: $StackName"
    }

    foreach ($ParameterName in $Parameters) {

        if ($ParameterName -eq "VpcId") {
            continue
        }

        if (-not $EnvironmentParameters.ContainsKey($ParameterName)) {
            throw "Missing environment parameter: $ParameterName for stack: $StackName"
        }

        if ([string]::IsNullOrWhiteSpace(
            [string]$EnvironmentParameters[$ParameterName]
        )) {
            throw "Empty parameter value: $ParameterName for stack: $StackName"
        }
    }

    Write-Host "Validated: $StackName"
}

Write-Host ""
Write-Host "All stack parameter mappings are valid."
Write-Host "Infrastructure deployment preparation completed."
Write-Host "No AWS deployment has been performed."


# Generate stack-specific CloudFormation parameter files
$ParameterOutputDirectory = Join-Path $ProjectRoot "deployment/parameters/$Environment"

New-Item -ItemType Directory -Force -Path $ParameterOutputDirectory |
    Out-Null

Write-Host ""
Write-Host "Generating CloudFormation parameter files..."

foreach ($Stack in $StackPlan) {

    $StackName = $Stack.Name
    $ParameterList = @()

    foreach ($ParameterName in $StackParameterMap[$StackName]) {

        # VpcId will be resolved from the Network stack during deployment.
        if ($ParameterName -eq "VpcId") {
            continue
        }

        $ParameterList += [PSCustomObject]@{
            ParameterKey = $ParameterName
            ParameterValue = [string]$EnvironmentParameters[$ParameterName]
        }
    }

    $ParameterFile = Join-Path $ParameterOutputDirectory "$StackName.json"

    $ParameterJson = ConvertTo-Json -InputObject @($ParameterList) -Depth 5
    Set-Content -Path $ParameterFile -Value $ParameterJson -Encoding utf8

    Write-Host "Generated: $StackName.json"
}

Write-Host ""
Write-Host "Parameter file generation completed."
Write-Host "No AWS deployment has been performed."



# --------------------------------------------------
# AWS CloudFormation Deployment
# --------------------------------------------------

if (-not $ExecuteDeployment) {
    Write-Host ""
    Write-Host "Execution flag not provided."
    Write-Host "Preparation mode completed. No AWS resources were deployed."
    return
}

Write-Host ""
Write-Host "Starting AWS CloudFormation deployment..."

# Resolve AWS region
$AwsRegion = $env:AWS_REGION

if ([string]::IsNullOrWhiteSpace($AwsRegion)) {
    $AwsRegion = $env:AWS_DEFAULT_REGION
}

if ([string]::IsNullOrWhiteSpace($AwsRegion)) {
    $AwsRegion = (& aws configure get region).Trim()
}

if ([string]::IsNullOrWhiteSpace($AwsRegion)) {
    throw "AWS region is not configured. Set AWS_REGION or configure the AWS CLI."
}

Write-Host "AWS Region: $AwsRegion"

# Verify AWS identity before deployment
& aws sts get-caller-identity --region $AwsRegion

if ($LASTEXITCODE -ne 0) {
    throw "AWS identity verification failed."
}

foreach ($Stack in $StackPlan) {

    $StackName = $Stack.Name
    $CloudFormationStackName = "$Environment-$StackName"
    $TemplateFile = Join-Path $TemplateDirectory "$StackName.yaml"

    Write-Host ""
    Write-Host "Deploying stack: $CloudFormationStackName"

    $ParameterOverrides = @()

    foreach ($ParameterName in $StackParameterMap[$StackName]) {

        if ($ParameterName -eq "VpcId") {

            $VpcId = & aws cloudformation describe-stacks `
                --stack-name "$Environment-network" `
                --query "Stacks[0].Outputs[?OutputKey=='VpcId'].OutputValue | [0]" `
                --output text `
                --region $AwsRegion

            if ($LASTEXITCODE -ne 0 -or
                [string]::IsNullOrWhiteSpace($VpcId) -or
                $VpcId -eq "None") {
                throw "Could not retrieve VpcId from the Network stack."
            }

            $ParameterOverrides += "VpcId=$VpcId"
        }
        else {
            $ParameterValue = [string]$EnvironmentParameters[$ParameterName]
            $ParameterOverrides += "$ParameterName=$ParameterValue"
        }
    }

    $DeployArguments = @(
        "cloudformation", "deploy",
        "--template-file", $TemplateFile,
        "--stack-name", $CloudFormationStackName,
        "--parameter-overrides"
    )

    $DeployArguments += $ParameterOverrides

    $DeployArguments += @(
        "--capabilities", "CAPABILITY_NAMED_IAM",
        "--no-fail-on-empty-changeset",
        "--region", $AwsRegion
    )

    & aws @DeployArguments

    if ($LASTEXITCODE -ne 0) {
        throw "Deployment failed for stack: $CloudFormationStackName"
    }

    Write-Host "Successfully deployed: $CloudFormationStackName"
}

Write-Host ""
Write-Host "All CloudFormation stacks deployed successfully."
