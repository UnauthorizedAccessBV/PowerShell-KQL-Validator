# Define parameters
param (
    [String][Parameter(Mandatory = $false)]$TableFolder = $(Join-Path -Path $PSScriptRoot -ChildPath "Manifests" -AdditionalChildPath "Tables"),
    [String][Parameter(Mandatory = $false)]$CustomTableFolder = $(Join-Path -Path $PSScriptRoot -ChildPath "CustomTables"),
    [String][Parameter(Mandatory = $false)]$FunctionFolder = $(Join-Path -Path $PSScriptRoot -ChildPath "Manifests" -AdditionalChildPath "Functions"),
    [String][Parameter(Mandatory = $false)]$QueryFolder = $(Join-Path -Path $PSScriptRoot -ChildPath "Queries")
)

# Load KqlValidation module
Import-Module "$PSScriptRoot/Modules/KqlValidation"

# Get GlobalState
$TableFolders = $($TableFolder, $CustomTableFolder)
$GlobalState = Get-GlobalState -TableFolder $TableFolders -FunctionFolder $FunctionFolder

# Set failed param
$Failed = $false

# Test all queries in query folder
Get-ChildItem $QueryFolder -Filter "*.kql" | ForEach-Object {
    $Query = Get-Content -Path $_.FullName
    $TestResult = Test-KqlQuery -Query $Query -Globalstate $GlobalState
    $TestFailed = $TestResult.GetDiagnostics()

    if ([string]::IsNullOrEmpty($TestFailed)) {
        Write-Host "Query $($_.BaseName) is valid"
    }
    else {
        $TestFailed | Format-Table
        Write-Error "Query $($_.BaseName) is invalid"
    }
}
