<#
.SYNOPSIS
  Sets up the Blackwood mods (Infinite Cash / God Mode / Infinite Ammo) on a Steam install of Blackwood.

.DESCRIPTION
  BepInEx 6 (be.788) can't read Blackwood's IL2CPP metadata (v107) by itself, so it can't generate the
  game-specific "interop" assemblies that plugins are built against. This script does that step for it, on YOUR
  machine from YOUR copy of the game (those files are derived from the game's code, so they can't be shipped):

    1. tells BepInEx not to try (UpdateInteropAssemblies = false, UnityLogListening = false)
    2. downloads BepInEx's Unity base libraries for the game's Unity version (if not already there)
    3. Cpp2IL       GameAssembly.dll + global-metadata.dat  ->  dummy assemblies
    4. Il2CppInterop CLI  dummy assemblies                  ->  BepInEx\interop\*.dll
    5. installs them, writes BepInEx's assembly-hash.txt, and copies the plugin DLLs into BepInEx\plugins

  Run it again after every Blackwood update, with the game closed - an update makes the interop stale.
  Prerequisite: BepInEx 6 be.788 (Unity IL2CPP, x64) already extracted into the game folder (see README.md).

.PARAMETER GameDir
  The Blackwood folder. Found automatically through Steam if omitted.

.PARAMETER InteropOnly
  Only regenerate the interop assemblies (e.g. after a game update); leave the plugins alone.

.PARAMETER UnityLibsZip
  Path or URL of a BepInEx Unity-libraries zip to use instead of the default download (offline installs).
#>
[CmdletBinding()]
param(
    [string]$GameDir,
    [switch]$InteropOnly,
    [string]$UnityLibsZip
)

$ErrorActionPreference = 'Stop'
$Root  = $PSScriptRoot
$Tools = Join-Path $Root 'tools'
$Work  = Join-Path $env:TEMP 'blackwood_setup'
$BepInExUrl = 'https://builds.bepinex.dev/projects/bepinex_be/788/BepInEx-Unity.IL2CPP-win-x64-6.0.0-be.788%2B5b766a3.zip'

function Write-Step([string]$text) { Write-Host ''; Write-Host $text -ForegroundColor Cyan }

function Test-GameDir([string]$dir) {
    if (-not $dir) { return $false }
    return (Test-Path -LiteralPath (Join-Path $dir 'Blackwood.exe')) -and
           (Test-Path -LiteralPath (Join-Path $dir 'GameAssembly.dll'))
}

function Find-GameDir {
    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add($Root)                                   # zip extracted straight into the game folder
    $parent = Split-Path $Root -Parent
    if ($parent) { $candidates.Add($parent) }
    $steam = $null
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        try {
            $props = Get-ItemProperty -Path $key -ErrorAction Stop
            foreach ($name in @('SteamPath', 'InstallPath')) { if (-not $steam -and $props.$name) { $steam = $props.$name } }
        } catch { }
    }
    if ($steam) {
        $steam = $steam -replace '/', '\'
        $candidates.Add((Join-Path $steam 'steamapps\common\BLACKWOOD'))
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
                $lib = $m.Groups[1].Value -replace '\\\\', '\'
                $candidates.Add((Join-Path $lib 'steamapps\common\BLACKWOOD'))
            }
        }
    }
    $candidates.Add('C:\Program Files (x86)\Steam\steamapps\common\BLACKWOOD')
    $candidates.Add('C:\Program Files\Steam\steamapps\common\BLACKWOOD')
    foreach ($c in $candidates) { if (Test-GameDir $c) { return $c } }
    return $null
}

# The same MD5 BepInEx computes over GameAssembly.dll + unity-libs + its generator versions
# (Il2CppInteropManager.ComputeHash). Writing it to interop\assembly-hash.txt is what stops BepInEx logging
# "Interop assemblies are possibly out of date" - and makes that warning meaningful after a game update.
function Get-InteropHash([string]$dir) {
    $core = Join-Path $dir 'BepInEx\core'
    foreach ($n in @('Il2CppInterop.Generator.dll', 'Cpp2IL.Core.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $core $n))) { return $null }
    }
    $md5 = [Security.Cryptography.MD5]::Create()
    $add = { param([byte[]]$bytes) [void]$md5.TransformBlock($bytes, 0, $bytes.Length, $null, 0) }
    & $add ([IO.File]::ReadAllBytes((Join-Path $dir 'GameAssembly.dll')))
    $libs = Join-Path $dir 'BepInEx\unity-libs'
    if (Test-Path -LiteralPath $libs) {
        foreach ($f in [IO.Directory]::EnumerateFiles($libs, '*.dll', [IO.SearchOption]::TopDirectoryOnly)) {
            & $add ([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFileName($f)))
            & $add ([IO.File]::ReadAllBytes($f))
        }
    }
    $map = Join-Path $dir 'BepInEx\DeobfuscationMap.csv.gz'
    if (Test-Path -LiteralPath $map) { & $add ([IO.File]::ReadAllBytes($map)) }
    foreach ($n in @('Il2CppInterop.Generator.dll', 'Cpp2IL.Core.dll')) {
        $ver = [Reflection.AssemblyName]::GetAssemblyName((Join-Path $core $n)).Version.ToString()
        & $add ([Text.Encoding]::UTF8.GetBytes($ver))
    }
    [void]$md5.TransformFinalBlock([byte[]]::new(0), 0, 0)
    return (($md5.Hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

# BepInEx's own interop generation fails on this game, and its Unity log listener needs class injection, which
# doesn't work on this Unity version - so both are switched off. Creates the config if BepInEx hasn't run yet.
function Set-BepInExConfig([string]$path) {
    $utf8 = New-Object Text.UTF8Encoding($false)
    $wanted = @(
        @{ Section = 'IL2CPP';  Key = 'UpdateInteropAssemblies'; Value = 'false' },
        @{ Section = 'Logging'; Key = 'UnityLogListening';       Value = 'false' }
    )
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
        $text = "[IL2CPP]`r`n`r`nUpdateInteropAssemblies = false`r`n`r`n[Logging]`r`n`r`nUnityLogListening = false`r`n"
        [IO.File]::WriteAllText($path, $text, $utf8)
        Write-Host "Created $path"
        return
    }
    $text = [IO.File]::ReadAllText($path)
    foreach ($w in $wanted) {
        $pattern = '(?m)^([ \t]*' + [regex]::Escape($w.Key) + '[ \t]*=[ \t]*)[^\r\n]*'   # [^\r\n]: keep CRLF line endings intact
        if ([regex]::IsMatch($text, $pattern)) {
            $text = [regex]::Replace($text, $pattern, ('${1}' + $w.Value))
        } else {
            $text = $text.TrimEnd() + "`r`n`r`n[" + $w.Section + "]`r`n`r`n" + $w.Key + ' = ' + $w.Value + "`r`n"
        }
    }
    [IO.File]::WriteAllText($path, $text, $utf8)
    Write-Host "Updated $path"
}

function Install-UnityLibs([string]$dir, [string]$zipSource) {
    $libs = Join-Path $dir 'BepInEx\unity-libs'
    if (Test-Path -LiteralPath (Join-Path $libs 'UnityEngine.CoreModule.dll')) {
        Write-Host 'Unity libraries already present.'
        return
    }
    $fileVersion = (Get-Item -LiteralPath (Join-Path $dir 'Blackwood.exe')).VersionInfo.FileVersion
    if ($fileVersion -notmatch '^(\d+)\.(\d+)\.(\d+)') { throw "Couldn't read the Unity version from Blackwood.exe ('$fileVersion')." }
    $unityVersion = '{0}.{1}.{2}' -f $Matches[1], $Matches[2], $Matches[3]   # BepInEx's {VERSION}: no "f1" suffix
    if (-not $zipSource) { $zipSource = "https://unity.bepinex.dev/libraries/$unityVersion.zip" }
    $zip = Join-Path $Work "unity-libs-$unityVersion.zip"
    if ($zipSource -match '^https?://') {
        Write-Host "Downloading the Unity $unityVersion base libraries from $zipSource"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $zipSource -OutFile $zip -UseBasicParsing
    } else {
        Copy-Item -LiteralPath $zipSource -Destination $zip -Force
    }
    $extracted = Join-Path $Work 'unity-libs'
    Expand-Archive -LiteralPath $zip -DestinationPath $extracted -Force
    New-Item -ItemType Directory -Force -Path $libs | Out-Null
    Get-ChildItem -LiteralPath $extracted -Recurse -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $libs -Force }
    if (-not (Test-Path -LiteralPath (Join-Path $libs 'UnityEngine.CoreModule.dll'))) {
        throw 'The Unity libraries zip did not contain UnityEngine.CoreModule.dll.'
    }
}

# Runs a tool to completion with its output going to a log file; prints a dot every few seconds so it's clear
# the (minutes-long) step is alive, and shows the tail of the log if the tool fails.
function Invoke-Tool([string]$Exe, [string[]]$Arguments, [string]$LogFile) {
    $argLine = ($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' '
    $p = Start-Process -FilePath $Exe -ArgumentList $argLine -NoNewWindow -PassThru `
        -RedirectStandardOutput $LogFile -RedirectStandardError ($LogFile + '.err')
    $null = $p.Handle                            # Windows PowerShell 5.1: without this, ExitCode comes back empty
    while (-not $p.HasExited) { Write-Host -NoNewline '.'; Start-Sleep -Seconds 4 }
    $p.WaitForExit()
    Write-Host ''
    if ($p.ExitCode -ne 0) {
        Write-Host "--- end of $([IO.Path]::GetFileName($LogFile)) ---" -ForegroundColor Yellow
        Get-Content -LiteralPath $LogFile, ($LogFile + '.err') -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
        throw "$([IO.Path]::GetFileName($Exe)) failed (exit code $($p.ExitCode))."
    }
}

try {
    Write-Host 'Blackwood mods - setup' -ForegroundColor Green

    # ---- find the game and check the prerequisites -------------------------------------------------------
    if (-not $GameDir) { $GameDir = Find-GameDir }
    if (-not $GameDir) {
        Write-Host "Couldn't find Blackwood automatically." -ForegroundColor Yellow
        $GameDir = (Read-Host 'Paste the Blackwood folder (Steam > Blackwood > Manage > Browse local files)').Trim(' ', '"')
    }
    $GameDir = [IO.Path]::GetFullPath($GameDir).TrimEnd('\')
    if (-not (Test-GameDir $GameDir)) { throw "'$GameDir' doesn't look like the Blackwood folder (no Blackwood.exe / GameAssembly.dll)." }
    Write-Host "Game folder: $GameDir"

    if (Get-Process -Name 'Blackwood' -ErrorAction SilentlyContinue) { throw 'Blackwood is running. Close it and run this again.' }

    foreach ($t in @('cpp2il_cli\Cpp2IL.exe', 'interop_cli\Il2CppInterop.CLI.dll', 'dotnet10\dotnet.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Tools $t))) {
            throw "tools\$t is missing. Use the full release zip (BlackwoodMods-x.y.z.zip), not GitHub's 'Source code' download."
        }
    }

    $bep  = Join-Path $GameDir 'BepInEx'
    $core = Join-Path $bep 'core'
    if (-not ((Test-Path -LiteralPath (Join-Path $GameDir 'winhttp.dll')) -and
              (Test-Path -LiteralPath (Join-Path $core 'BepInEx.Unity.IL2CPP.dll')))) {
        throw ("BepInEx isn't installed in the game folder yet.`r`n" +
               "  1. Download BepInEx 6.0.0-be.788 (Unity IL2CPP, win-x64):`r`n     $BepInExUrl`r`n" +
               "  2. Extract it into '$GameDir' (winhttp.dll must end up next to Blackwood.exe).`r`n" +
               "  3. Run this script again.")
    }
    $bepVersion = (Get-Item -LiteralPath (Join-Path $core 'BepInEx.Unity.IL2CPP.dll')).VersionInfo.ProductVersion
    if ($bepVersion -notmatch 'be\.788') {
        Write-Warning "Found BepInEx $bepVersion. These mods were tested with 6.0.0-be.788; continuing anyway."
    }

    if (Test-Path -LiteralPath $Work) { [IO.Directory]::Delete($Work, $true) }
    New-Item -ItemType Directory -Force -Path $Work | Out-Null
    Get-ChildItem -LiteralPath $Tools -Recurse -File | Unblock-File -ErrorAction SilentlyContinue   # downloaded-zip flag

    # ---- 1. BepInEx config --------------------------------------------------------------------------------
    Write-Step '1/5  Configuring BepInEx for Blackwood'
    Set-BepInExConfig (Join-Path $bep 'config\BepInEx.cfg')

    # ---- 2. Unity base libraries --------------------------------------------------------------------------
    Write-Step '2/5  Unity base libraries'
    Install-UnityLibs $GameDir $UnityLibsZip

    # ---- 3. Cpp2IL ----------------------------------------------------------------------------------------
    Write-Step '3/5  Reading the game with Cpp2IL (a minute or two; briefly uses about 3 GB of memory)'
    $env:DOTNET_ROOT = Join-Path $Tools 'dotnet10'
    $env:DOTNET_MULTILEVEL_LOOKUP = '0'
    $env:DOTNET_NOLOGO = '1'
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
    $env:NO_COLOR = '1'
    Invoke-Tool (Join-Path $Tools 'cpp2il_cli\Cpp2IL.exe') @(
        '--game-path', $GameDir, '--exe-name', 'Blackwood', '--use-processor', 'attributeinjector',
        '--output-as', 'dll_default', '--output-to', (Join-Path $Work 'dummy')) (Join-Path $Work 'cpp2il.log')

    # ---- 4. Il2CppInterop ---------------------------------------------------------------------------------
    Write-Step '4/5  Generating the interop assemblies with Il2CppInterop (a minute or two)'
    $env:DOTNET_ROLL_FORWARD = 'Major'          # the CLI targets .NET 6; run it on the bundled .NET 10 runtime
    Invoke-Tool (Join-Path $Tools 'dotnet10\dotnet.exe') @(
        (Join-Path $Tools 'interop_cli\Il2CppInterop.CLI.dll'), 'generate',
        '--input', (Join-Path $Work 'dummy'), '--output', (Join-Path $Work 'interop'),
        '--unity', (Join-Path $bep 'unity-libs'), '--game-assembly', (Join-Path $GameDir 'GameAssembly.dll')) (Join-Path $Work 'interop.log')
    Remove-Item Env:\DOTNET_ROLL_FORWARD -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath (Join-Path $Work 'interop\Assembly-CSharp.dll'))) {
        throw 'Il2CppInterop finished but produced no Assembly-CSharp.dll.'
    }

    # ---- 5. Install ---------------------------------------------------------------------------------------
    Write-Step '5/5  Installing'
    $interop = Join-Path $bep 'interop'
    New-Item -ItemType Directory -Force -Path $interop | Out-Null
    Get-ChildItem -LiteralPath $interop -File | ForEach-Object { [IO.File]::Delete($_.FullName) }   # incl. stale caches
    Copy-Item -Path (Join-Path $Work 'interop\*') -Destination $interop -Recurse -Force
    Write-Host "Interop assemblies installed ($((Get-ChildItem -LiteralPath $interop -Filter *.dll).Count) files)."
    $hash = Get-InteropHash $GameDir
    if ($hash) { [IO.File]::WriteAllText((Join-Path $interop 'assembly-hash.txt'), $hash) }
    else { Write-Warning "Couldn't compute BepInEx's assembly hash; BepInEx will log a harmless 'possibly out of date' warning." }

    if ($InteropOnly) {
        Write-Host 'Plugins left untouched (-InteropOnly).'
    } else {
        $dlls = @(Get-ChildItem -LiteralPath (Join-Path $Root 'plugins') -Filter *.dll -ErrorAction SilentlyContinue)
        if ($dlls.Count -eq 0) {
            Write-Warning "No plugin DLLs found next to this script (plugins\*.dll) - nothing to install."
        } else {
            $pluginDir = Join-Path $bep 'plugins'
            New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null
            foreach ($d in $dlls) {
                Copy-Item -LiteralPath $d.FullName -Destination $pluginDir -Force
                Write-Host "Installed $($d.Name)"
            }
        }
    }

    Write-Host ''
    Write-Host 'Done. Start Blackwood from Steam.' -ForegroundColor Green
    Write-Host '  In game (window focused):  F6 infinite cash   F7 god mode   F8 infinite ammo'
    Write-Host '  After a Blackwood update, run this again (BepInEx warns "Interop assemblies are possibly out of date").'
    exit 0
}
catch {
    Write-Host ''
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path -LiteralPath $Work) { try { [IO.Directory]::Delete($Work, $true) } catch { } }
}
