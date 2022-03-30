# Microsoft Sentinel KQL Validator

## Introduction

This is a PowerShell port of the validation pipeline used by Microsoft in their [Sentinel repository](https://github.com/Azure/Azure-Sentinel/). It allows you to easily check if new queries you commit are valid by using this project in your DevOps pipeline. It uses the **`Kusto.Language`** NuGet package, so you will need to install that.

## Install the Kusto.Language package

Add the NuGet repository:

```powershell
Register-PackageSource -Name Nuget -Location https://api.nuget.org/v3/index.json -ProviderName NuGet
```

Install the package into the [**`ModulesPackages`**](Modules/Packages/) directory:

```powershell
Install-Package Microsoft.Azure.Kusto.Language -Force -Destination "Modules/Packages"
```

Copy the DLL to the module folder:

```
cp Modules/Packages/Microsoft.Azure.Kusto.Language.*/lib/netcoreapp2.1/Kusto.Language.dll Modules/Kusto.Language.dll
```

## Basic usage example

```powershell
# Import the module
Install-Package Microsoft.Azure.Kusto.Language -Force -Destination "Modules/Packages"

# Create the GlobalState object
$GlobalState = Get-GlobalState -TableFolder "./Manifests/Tables/" -FunctionFolder "./Manifests/Functions/"

# Run the query you want to test
$TestResult = Test-KqlQuery -Query "SecurityAlert | where AlertSeverity == 'Medium'" -Globalstate $GlobalState

# If GetDiagnostics() returns an empty object the query is valid
$TestResult.GetDiagnostics()

# Here is an example of an invalid query
$TestResult = Test-KqlQuery -Query "SecurityAlert | where ColumnDoesNotExist == true" -Globalstate $GlobalState
$TestResult.GetDiagnostics()

Code        : KS142
Category    : General
Severity    : Error
Description : The name 'ColumnDoesNotExist' does not refer to any known column, table, variable or function.
Message     : The name 'ColumnDoesNotExist' does not refer to any known column, table, variable or function.
HasLocation : True
Start       : 22
Length      : 18
End         : 40

# If your query uses Custom Tables or functions be sure to specify the folder containing them
$GlobalState = Get-GlobalState -TableFolder "./Manifests/Tables/","CustomTables" -FunctionFolder "./Manifests/Functions/"
$TestResult = Test-KqlQuery -Query "eset_CL | where event_type_s == 'Threat_Event'" -Globalstate $GlobalState
$TestResult.GetDiagnostics()
```

You can also try the [**`example script`**](example.ps1):

```powershell
./example.ps1
```

## Add custom tables

Custom tables for Microsoft Sentinel can be found [here](https://github.com/Azure/Azure-Sentinel/tree/46b6220e5d4d8947085e52352389f2b006733670/.script/tests/KqlvalidationsTests/CustomTables). Add them to the [**`CustomTables`**](CustomTables/) folder.

## [OPTIONAL] Extracting sentinel nupkg

This part explains how to extract the sentinel table manifests from the KustoServices nupkg file found in the [sentinel github repository](https://github.com/Azure/Azure-Sentinel/tree/master/.script/tests/KqlvalidationsTests).

Get the nupkg file from [this](https://github.com/Azure/Azure-Sentinel/tree/master/.script/tests/KqlvalidationsTests) repository. At the time of writing the latest version is [4.0.0](https://github.com/Azure/Azure-Sentinel/raw/master/.script/tests/KqlvalidationsTests/Microsoft.Azure.Sentinel.KustoServices.4.0.0.nupkg):

```shell
wget https://github.com/Azure/Azure-Sentinel/raw/master/.script/tests/KqlvalidationsTests/Microsoft.Azure.Sentinel.KustoServices.4.0.0.nupkg
```

Extract it to a folder:

```shell
unzip -d KustoServices Microsoft.Azure.Sentinel.KustoServices.*.nupkg
```

Run the [**`Get-Manifests.ps1`**](Scripts/Get-Manifests.ps1) script from the [**`Scripts`**](Scripts/) directory:

```powershell
./Scripts/Get-Manifests.ps1
```

The manifests will be placed in the [**`Manifests`**](Manifests/) folder.
