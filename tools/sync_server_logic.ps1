# Equivalente en PowerShell de sync_server_logic.sh (para Windows).
# Copia games/<id>/<id>/<id>_logic.gd a arcade-stars-horizons-edition/server/games/<id>/.
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "arcade-stars-horizons-edition/server/games"
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force $out | Out-Null
foreach ($dir in Get-ChildItem (Join-Path $root "games") -Directory) {
    $id = $dir.Name
    $src = Join-Path $dir.FullName "$id/${id}_logic.gd"
    if (-not (Test-Path $src)) { Write-Host "skip $id (no ${id}_logic.gd)"; continue }
    New-Item -ItemType Directory -Force (Join-Path $out $id) | Out-Null
    Copy-Item $src (Join-Path $out $id)
    Copy-Item (Join-Path $dir.FullName "$id/manifest.json") (Join-Path $out $id)
    Write-Host "synced $id"
}
