Function Invoke-UpdateColumnsToDynamic ($Schema, $Columns) {
    $Columns | ForEach-Object {
        $ColumnName = $_
        $Schema.Properties | ForEach-Object {
            if ($ColumnName -eq $_.Name) {
                $_.Type = "Dynamic"
            }
        }
    }
}

Function Invoke-UpdateHardCodedDynamicColumnsUponLogAConfig ($Schema) {
    switch ($Schema.Name) {
        "WindowsEvent" {
            Invoke-UpdateColumnsToDynamic -Schema $Schema -Columns @("Data")
        }

        "SigninLogs" {
            Invoke-UpdateColumnsToDynamic -Schema $Schema -Columns @("ConditionalAccessPolicies", "DeviceDetail", "LocationDetails", "MfaDetail", "Status")
        }

        "AuditLogs" {
            Invoke-UpdateColumnsToDynamic -Schema $Schema -Columns @("AdditionalDetails", "InitiatedBy", "TargetResources")
        }
    }
}

Function Invoke-AddResourceIdColumn ($Schema) {
    if ($false -eq [System.Convert]::ToBoolean($Schema.IsResourceCentric)) {
        return
    }

    $Schema.Properties | ForEach-Object {
        if ("_ResourceId" -eq $_.Name) {
            return
        }
    }

    $Schema.Properties += [PSCustomObject]@{
        Name = "_ResourceId"
        Type = "String"
    }

}

Function Invoke-AddCommonColumns ($Schema) {
    $Schema.Properties += [PSCustomObject]@{
        Name = "Type"
        Type = "String"
    }
    Invoke-AddResourceIdColumn($Schema)
    Invoke-UpdateHardCodedDynamicColumnsUponLogAConfig($Schema)
}

Function Invoke-LoadTable ($SchemaFile) {
    $Schema = Get-Content -Path $SchemaFile -Raw | ConvertFrom-Json
    Invoke-AddCommonColumns -Schema $Schema
    return [PSCustomObject]@{
        Name       = $Schema.Name
        Properties = $Schema.Properties
    }
}

Function Invoke-ToColumnSymbol ($Column) {
    $ScalarType = [Kusto.Language.Symbols.ScalarSymbol][Kusto.Language.Symbols.ScalarTypes]::GetSymbol(
        $Column.Type.ToLowerInvariant().Replace('bigint', 'long').Replace('uri', 'string').Replace(' ', '')
    )

    if ($null -eq $ScalarType) {
        $ScalarType = [Kusto.Language.Symbols.ScalarTypes]::Unknown
    }

    return [Kusto.Language.Symbols.ColumnSymbol]::new(
        $Column.Name,
        [Kusto.Language.Symbols.TypeSymbol][object]$ScalarType,
        $Column.description
    )
}

Function Invoke-CreateTableSymbol ($TableSchema) {
    [Kusto.Language.Symbols.ColumnSymbol[]] $TableColumnList = @()

    $TableSchema.Properties | ForEach-Object {
        $TableColumnList += Invoke-ToColumnSymbol -Column $_
    }

    return [Kusto.Language.Symbols.TableSymbol]::new(
        $TableSchema.Name,
        $TableColumnList,
        $TableSchema.description
    )
}

Function Invoke-CreateFunctionSymbol($Schema) {
    $ParameterList = [System.Collections.Generic.List[Kusto.Language.Symbols.Parameter]]::new()
    $ColumnSymbolList = [System.Collections.Generic.List[Kusto.Language.Symbols.ColumnSymbol]]::new()

    $Schema.FunctionParameters | ForEach-Object {
        $ScalarType = [Kusto.Language.Symbols.ScalarTypes]::GetSymbol($_.Type.ToLowerInvariant())

        if ($null -eq $ScalarType) {
            $ScalarType = [Kusto.Language.Symbols.ScalarTypes]::Unknown
        }
        $ParameterList.Add(
            [Kusto.Language.Symbols.Parameter]::new(
                $_.Name,
                [Kusto.Language.Symbols.TypeSymbol][object]$ScalarType,
                [Kusto.Language.Symbols.ArgumentKind]0,
                [System.Collections.Generic.IReadOnlyList[object]]$null,
                [System.Collections.Generic.IReadOnlyList[string]]$null,
                $false,
                $null,
                [int]$_.IsRequired,
                [System.Linq.Expressions.Expression]$null,
                $_.description
            )
        )
    }

    if (([string]::IsNullOrEmpty($Schema.FunctionResultColumns)) -and (-not ([string]::IsNullOrEmpty($Schema.Query)))) {
        return [Kusto.Language.Symbols.FunctionSymbol]::new(
            $Schema.FunctionName,
            [string]$Schema.Query,
            [System.Collections.Generic.IReadOnlyList[Kusto.Language.Symbols.Parameter]]$ParameterList,
            $null
        )
    }

    $Schema.FunctionResultColumns | ForEach-Object {
        $ColumnSymbolList.Add(
            $(Invoke-ToColumnSymbol -Column $_)
        )
    }

    return [Kusto.Language.Symbols.FunctionSymbol]::new(
        $Schema.FunctionName,
        [Kusto.Language.Symbols.TableSymbol]::new($ColumnSymbolList),
        [System.Collections.Generic.IReadOnlyList[Kusto.Language.Symbols.Parameter]]$ParameterList,
        $null
    )
}

Function Invoke-LoadFunction ($SchemaFile) {
    $Schema = Get-Content -Path $SchemaFile -Raw | ConvertFrom-Json
    return $Schema
}

Function Get-GlobalState ($TableFolder, $FunctionFolder) {
    $TableSchemaList = [System.Collections.Generic.List[object]]::new()
    $FunctionSchemaList = [System.Collections.Generic.List[object]]::new()

    # Load table schemas
    Get-ChildItem -Path $TableFolder -Filter "*.json" |
    ForEach-Object {
        $TableSchemaList.Add(
            $(Invoke-LoadTable -SchemaFile $_.FullName)
        )
    }

    if (-not([string]::IsNullOrEmpty($FunctionFolder))) {
        # Create function symbols
        Get-ChildItem -Path $FunctionFolder -Filter "*.json" |
        ForEach-Object {
            $FunctionSchemaList.Add(
                $(Invoke-LoadFunction -SchemaFile $_.FullName)
            )
        }
    }
    return $(Get-GlobalStateFromLists -TableSchemaList $TableSchemaList -FunctionSchemaList $FunctionSchemaList)
}

Function Get-GlobalStateFromLists ($TableSchemaList, $FunctionSchemaList) {

    # Set up empty lists
    $SymbolList = [System.Collections.Generic.List[Kusto.Language.Symbols.Symbol]]::new()

    # Create table symbols
    $TableSchemaList | ForEach-Object {
        $Symbollist.Add(
            [Kusto.Language.Symbols.Symbol][object]$(Invoke-CreateTableSymbol -TableSchema $_)
        )
    }

    $FunctionSchemaList | ForEach-Object {
        $Symbollist.Add(
            [Kusto.Language.Symbols.Symbol][object]$(Invoke-CreateFunctionSymbol -Schema $_)
        )
    }

    # Create database
    $DatabaseSymbol = [Kusto.Language.Symbols.DatabaseSymbol]::new(
        "default",
        $SymbolList
    )

    return [Kusto.Language.GlobalState]::Default.WithDatabase($DatabaseSymbol)
}

# Test if query is valid against current globalstate
Function Test-KqlQuery ($Query, $Globalstate) {

    $Query = $Query.Replace('.[', '[')
    return [Kusto.Language.KustoCode]::ParseAndAnalyze($Query, $GlobalState)
}
