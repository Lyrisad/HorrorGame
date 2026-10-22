# Prepare un PC pour travailler sur le projet apres un "git clone" :
#  1. Godot 4.7.2 (editeur + exe console des tests) dans tools\godot
#  2. modeles d'export Windows 4.7.2 dans %APPDATA%\Godot\export_templates
#  3. (option -Blender) Blender 4.5.9 portable dans tools\blender (seulement pour refaire personnages / modeles)
#  4. premier import des ressources (cree le dossier .godot)
# Usage, depuis la racine du projet :
#   powershell -ExecutionPolicy Bypass -File tools\setup_pc.ps1 [-Blender]
param([switch]$Blender)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # sinon Invoke-WebRequest est tres lent
$root = Split-Path -Parent $PSScriptRoot
$ver = "4.7.2-stable"
$base = "https://github.com/godotengine/godot/releases/download/$ver"
$tmp = Join-Path $env:TEMP "horrorgame_setup"
New-Item -ItemType Directory -Force $tmp | Out-Null

$godotDir = Join-Path $root "tools\godot"
$console = Join-Path $godotDir "Godot_v$($ver)_win64_console.exe"
if (-not (Test-Path $console)) {
    Write-Host "Telechargement de Godot $ver..."
    $zip = Join-Path $tmp "godot.zip"
    Invoke-WebRequest "$base/Godot_v$($ver)_win64.exe.zip" -OutFile $zip
    New-Item -ItemType Directory -Force $godotDir | Out-Null
    Expand-Archive $zip -DestinationPath $godotDir -Force
    Remove-Item $zip
} else {
    Write-Host "Godot deja present."
}

$tplDir = Join-Path $env:APPDATA "Godot\export_templates\4.7.2.stable"
if (-not (Test-Path (Join-Path $tplDir "windows_release_x86_64.exe"))) {
    Write-Host "Telechargement des modeles d'export (environ 1,2 Go, une seule fois)..."
    $tpz = Join-Path $tmp "templates.tpz"
    Invoke-WebRequest "$base/Godot_v$($ver)_export_templates.tpz" -OutFile $tpz
    New-Item -ItemType Directory -Force $tplDir | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [System.IO.Compression.ZipFile]::OpenRead($tpz)
    try {
        foreach ($e in $z.Entries) {
            if ($e.Name -in @("windows_release_x86_64.exe", "windows_debug_x86_64.exe", "version.txt")) {
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $tplDir $e.Name), $true)
            }
        }
    } finally {
        $z.Dispose()
    }
    Remove-Item $tpz
} else {
    Write-Host "Modeles d'export deja installes."
}

if ($Blender) {
    $bDir = Join-Path $root "tools\blender"
    if (-not (Test-Path (Join-Path $bDir "blender-4.5.9-windows-x64\blender.exe"))) {
        Write-Host "Telechargement de Blender 4.5.9..."
        $bzip = Join-Path $tmp "blender.zip"
        Invoke-WebRequest "https://download.blender.org/release/Blender4.5/blender-4.5.9-windows-x64.zip" -OutFile $bzip
        New-Item -ItemType Directory -Force $bDir | Out-Null
        Expand-Archive $bzip -DestinationPath $bDir -Force
        Remove-Item $bzip
    } else {
        Write-Host "Blender deja present."
    }
}

Write-Host "Import des ressources (plusieurs minutes la premiere fois)..."
& $console --headless --path $root --import
Write-Host ""
Write-Host "Pret. Editeur : tools\godot\Godot_v$($ver)_win64.exe (ouvrir project.godot)"
