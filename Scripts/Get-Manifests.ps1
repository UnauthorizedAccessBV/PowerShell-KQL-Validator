# Define parameters
param (
    [String][Parameter(Mandatory = $false)]$Dll = (Join-Path -Path $(Get-Location) -ChildPath "KustoServices" `
            -AdditionalChildPath "lib", "netcoreapp2.1", "Microsoft.Azure.Sentinel.KustoServices.dll"),
    [String][Parameter(Mandatory = $false)]$OutputFolder = (Join-Path -Path $(Get-Location) -ChildPath "Manifests")
)

$DllFullPath = Resolve-Path -Path $Dll
$ResourceAssembly = [Reflection.Assembly]::LoadFile($DllFullPath)
$ResourceNames = $ResourceAssembly.GetManifestResourceNames()

$ResourceNames | ForEach-Object {
    if ($_.EndsWith(".json")) {
        $Reader = New-Object -TypeName System.IO.StreamReader -ArgumentList $ResourceAssembly.GetManifestResourceStream($_)
        $PathParts = $_.Split(".")
        $Filename = $PathParts[5..$($PathParts.Count)] -join "."
        $ParentFolder = $PathParts[4]

        $ManifestFolder = Join-Path -Path $OutputFolder -ChildPath $ParentFolder
        $ManifestPath = Join-Path -Path $ManifestFolder -ChildPath $Filename
        
        if (-not(Test-Path -Path $ManifestFolder)) {
            New-Item -Path $ManifestFolder -ItemType Directory -Force | Out-Null
        }

        $Reader.ReadToEnd() | Out-File -FilePath $ManifestPath
    }
}