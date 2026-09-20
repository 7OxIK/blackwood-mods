<#
  Builds the three plugins in Release mode and assembles the GitHub release files into dist\:

    BlackwoodMods-<version>.zip               full package: Setup.bat/Setup.ps1 + plugins + tools\ (for everyone)
    BlackwoodMods-<version>-plugins-only.zip  just BepInEx\plugins\*.dll (for people who already have working interop)
    SHA256SUMS.txt

  Needs the (git-ignored) tools\ folder: cpp2il_cli, interop_cli, dotnet10 - see THIRD-PARTY.md - and a game
  folder with BepInEx + generated interop to compile against.
#>
param(
    [string]$Version = '1.0.0',
    [string]$GameDir = 'C:\Program Files\Steam\steamapps\common\BLACKWOOD'
)
$ErrorActionPreference = 'Stop'
$root    = $PSScriptRoot
$plugins = @('BlackwoodInfiniteCash', 'BlackwoodGodMode', 'BlackwoodInfiniteAmmo')

foreach ($t in @('cpp2il_cli\Cpp2IL.exe', 'interop_cli\Il2CppInterop.CLI.dll', 'dotnet10\dotnet.exe')) {
    if (-not (Test-Path (Join-Path $root "tools\$t"))) { throw "tools\$t is missing - the full package can't be assembled." }
}

# The version users see in BepInEx's log must match the release being cut.
foreach ($p in $plugins) {
    $src = Get-Content (Join-Path $root "$p\Plugin.cs") -Raw
    if ($src -notmatch 'BepInPlugin\(PluginGuid, "[^"]+", "([^"]+)"\)') { throw "$p\Plugin.cs: no BepInPlugin attribute found." }
    if ($Matches[1] -ne $Version) { throw "$p\Plugin.cs says version $($Matches[1]) but the release is $Version." }
}

foreach ($p in $plugins) {
    Write-Host "Building $p (Release)" -ForegroundColor Cyan
    & dotnet build (Join-Path $root "$p\$p.csproj") -c Release -p:InstallToGame=false "-p:GameDir=$GameDir" --nologo -v:q
    if ($LASTEXITCODE) { throw "Build of $p failed." }
}

$dist  = Join-Path $root 'dist'
$name  = "BlackwoodMods-$Version"
$stage = Join-Path $dist $name
if (Test-Path $dist) { [IO.Directory]::Delete($dist, $true) }
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'plugins') | Out-Null

foreach ($p in $plugins) { Copy-Item (Join-Path $root "out\$p\$p.dll") (Join-Path $stage 'plugins') }
foreach ($f in @('Setup.ps1', 'Setup.bat', 'README.md', 'THIRD-PARTY.md', 'LICENSE')) {
    if (Test-Path (Join-Path $root $f)) { Copy-Item (Join-Path $root $f) $stage }
}
Copy-Item (Join-Path $root 'licenses') $stage -Recurse
Copy-Item (Join-Path $root 'tools') $stage -Recurse

# .NET Framework's ZipFile.CreateFromDirectory writes backslashes in entry names (against the zip spec), so
# build the archives by hand with forward slashes.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
function New-Zip([string]$SourceDir, [string]$ZipPath, [string]$Prefix) {
    $base = (Resolve-Path $SourceDir).Path.TrimEnd('\') + '\'
    $zip = [IO.Compression.ZipFile]::Open($ZipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in Get-ChildItem -LiteralPath $SourceDir -Recurse -File) {
            $entry = $f.FullName.Substring($base.Length).Replace('\', '/')
            if ($Prefix) { $entry = "$Prefix/$entry" }
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $entry, [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $zip.Dispose() }
}
$full = Join-Path $dist "$name.zip"
New-Zip $stage $full $name

# plugins-only: laid out so it can be extracted straight into the game folder
$po = Join-Path $dist 'plugins-only'
New-Item -ItemType Directory -Force -Path (Join-Path $po 'BepInEx\plugins') | Out-Null
foreach ($p in $plugins) { Copy-Item (Join-Path $root "out\$p\$p.dll") (Join-Path $po 'BepInEx\plugins') }
$only = Join-Path $dist "$name-plugins-only.zip"
New-Zip $po $only ''

[IO.Directory]::Delete($po, $true)
[IO.Directory]::Delete($stage, $true)

$sums = Get-ChildItem $dist -Filter *.zip | ForEach-Object { '{0}  {1}' -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name }
Set-Content -Path (Join-Path $dist 'SHA256SUMS.txt') -Value $sums -Encoding ASCII
Write-Host ''
Get-ChildItem $dist | ForEach-Object { '{0,10:N1} MB  {1}' -f ($_.Length / 1MB), $_.Name }
Write-Host 'Done.' -ForegroundColor Green
