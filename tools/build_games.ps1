# Exporta cada juego de games/<id>/ a dist/games/<id>.pck (preset "pck" de cada proyecto).
# Uso: .\tools\build_games.ps1 [-Godot <ruta al ejecutable>]
param([string]$Godot = (Join-Path (Split-Path -Parent $PSScriptRoot) "Godot_v4.7.2-stable_win64.exe"))
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root "dist/games"
New-Item -ItemType Directory -Force $dist | Out-Null
foreach ($dir in Get-ChildItem (Join-Path $root "games") -Directory) {
    $id = $dir.Name
    & $Godot --headless --path $dir.FullName --import --quit | Out-Null
    & $Godot --headless --path $dir.FullName --export-pack "pck" (Join-Path $dist "$id.pck") | Out-Null
    if (Test-Path (Join-Path $dist "$id.pck")) { Write-Host "built $id.pck" } else { Write-Host "FAILED $id" }
}
