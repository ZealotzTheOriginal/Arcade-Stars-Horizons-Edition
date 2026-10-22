# Empaqueta y (opcionalmente) publica el launcher y los juegos en GitHub Releases.
#
#   .\tools\release.ps1 -Games minesweeper            # solo genera dist/release/ (prueba en seco)
#   .\tools\release.ps1 -Launcher -Games all -Publish # genera y sube todo
#
# Releases que crea (el manifest las enlaza):
#   launcher-<version>        ArcadeStars-<version>-win64.zip   (versión de application/config/version)
#   game-<id>-<version>       <id>.pck                          (versión de games/<id>/<id>/manifest.json)
#   catalog                   manifest.json                     (se sobrescribe en cada publicación)
#
# ORDEN al publicar una versión nueva de un juego: 1) este script con -Publish, 2) git push
# (Render reconstruye el servidor con la lógica y el catálogo nuevos).
param(
    [switch]$Launcher,
    [string[]]$Games = @(),
    [switch]$Publish,
    [string]$BaseUrl = "https://github.com/ZealotzTheOriginal/Arcade-Stars-Horizons-Edition/releases/download",
    [string]$PreviousManifest = "",
    [string]$Godot = ""
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not $Godot) { $Godot = Join-Path $root "Godot_v4.7.2-stable_win64.exe" }
$hub = Join-Path $root "arcade-stars-horizons-edition"
$out = Join-Path $root "dist/release"
# Limpia el contenido (si algún programa tiene abierta la carpeta, no falla)
Get-ChildItem $out -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $out | Out-Null

function Get-Sha256($path) { (Get-FileHash -Algorithm SHA256 $path).Hash.ToLower() }

# ── Manifest previo (para no perder entradas de lo que no se reconstruye) ──
$manifest = @{ schema = 1; launcher = $null; games = @{} }
$previous = $null
if ($PreviousManifest -and (Test-Path $PreviousManifest)) {
    $previous = Get-Content $PreviousManifest -Raw | ConvertFrom-Json
} else {
    try { $previous = Invoke-RestMethod "$BaseUrl/catalog/manifest.json" } catch { Write-Host "No previous manifest (first publication)" }
}
if ($previous) {
    if ($previous.launcher) { $manifest.launcher = $previous.launcher }
    if ($previous.games) { $previous.games.PSObject.Properties | ForEach-Object { $manifest.games[$_.Name] = $_.Value } }
}

$tags = @()   # [tag, archivo, título]

# ── Juegos ──
if ($Games -contains "all") { $Games = (Get-ChildItem (Join-Path $root "games") -Directory).Name }
foreach ($id in $Games) {
    $project = Join-Path $root "games/$id"
    $info = Get-Content (Join-Path $project "$id/manifest.json") -Raw | ConvertFrom-Json
    & $Godot --headless --path $project --import --quit | Out-Null
    $pck = Join-Path $root "dist/games/$id.pck"
    New-Item -ItemType Directory -Force (Split-Path $pck) | Out-Null
    & $Godot --headless --path $project --export-pack "pck" $pck | Out-Null
    if (-not (Test-Path $pck)) { throw "Export failed for $id" }
    $tag = "game-$id-$($info.version)"
    $dir = Join-Path $out $tag
    New-Item -ItemType Directory -Force $dir | Out-Null
    Copy-Item $pck $dir
    $asset = Join-Path $dir "$id.pck"
    $manifest.games[$id] = @{ version = $info.version; url = "$BaseUrl/$tag/$id.pck"; sha256 = (Get-Sha256 $asset); size = (Get-Item $asset).Length }
    $tags += , @($tag, $asset, "$($info.name) $($info.version)")
    Write-Host "game  $id $($info.version)"
}

# ── Launcher ──
if ($Launcher) {
    $version = (Select-String -Path (Join-Path $hub "project.godot") -Pattern '^config/version="([^"]+)"').Matches[0].Groups[1].Value
    $exe = Join-Path $root "dist/hub/ArcadeStars.exe"
    New-Item -ItemType Directory -Force (Split-Path $exe) | Out-Null
    & $Godot --headless --path $hub --import --quit | Out-Null
    & $Godot --headless --path $hub --export-release "Windows Desktop" $exe | Out-Null
    if (-not (Test-Path $exe)) { throw "Launcher export failed" }
    $tag = "launcher-$version"
    $dir = Join-Path $out $tag
    New-Item -ItemType Directory -Force $dir | Out-Null
    $zip = Join-Path $dir "ArcadeStars-$version-win64.zip"
    Compress-Archive -Path $exe -DestinationPath $zip
    $manifest.launcher = @{ version = $version; url = "$BaseUrl/$tag/ArcadeStars-$version-win64.zip"; sha256 = (Get-Sha256 $zip); size = (Get-Item $zip).Length }
    $tags += , @($tag, $zip, "Launcher $version")
    Write-Host "launcher $version"
}

# ── Manifest ──
$catalogDir = Join-Path $out "catalog"
New-Item -ItemType Directory -Force $catalogDir | Out-Null
$manifestPath = Join-Path $catalogDir "manifest.json"
# UTF-8 sin BOM (Windows PowerShell 5.1 añade BOM con -Encoding UTF8 y rompería el parseo)
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "manifest -> $manifestPath"

# ── Publicación ──
# `gh` escribe en stderr cuando algo no existe; con $ErrorActionPreference = "Stop" eso abortaría el script.
function Test-Release($tag) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    gh release view $tag 2>&1 | Out-Null
    $exists = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $prev
    return $exists
}
function Publish-Release($tag, $file, $title) {
    if (Test-Release $tag) { gh release upload $tag $file --clobber } else { gh release create $tag $file --title $title --notes $title }
    if ($LASTEXITCODE -ne 0) { throw "gh failed for $tag" }
}
if ($Publish) {
    foreach ($t in $tags) { Publish-Release $t[0] $t[1] $t[2] }
    Publish-Release "catalog" $manifestPath "Catalog"
    Write-Host "Published. Next: git push (rebuilds the server)."
} else {
    Write-Host "Dry run: nothing published (use -Publish)."
}
