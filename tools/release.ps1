# Empaqueta y (opcionalmente) publica el launcher y los juegos en GitHub Releases.
#
#   .\tools\release.ps1 -Games minesweeper            # solo genera dist/release/ (prueba en seco)
#   .\tools\release.ps1 -Launcher -Games all -Publish # genera y sube todo
#
# Releases que crea (el manifest las enlaza):
#   launcher-<version>        ArcadeStars-<version>-win64.zip y ArcadeStars-<version>-linux-x86_64.tar.gz
#                             (versión de application/config/version)
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
$manifest = @{ schema = 1; launcher = $null; launcher_linux = $null; games = @{} }
$previous = $null
if ($PreviousManifest -and (Test-Path $PreviousManifest)) {
    $previous = Get-Content $PreviousManifest -Raw | ConvertFrom-Json
} else {
    try { $previous = Invoke-RestMethod "$BaseUrl/catalog/manifest.json" } catch { Write-Host "No previous manifest (first publication)" }
}
if ($previous) {
    if ($previous.launcher) { $manifest.launcher = $previous.launcher }
    if ($previous.launcher_linux) { $manifest.launcher_linux = $previous.launcher_linux }
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
    $tags += , @($tag, $asset, "$($info.name) $($info.version)", $false)
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
    $tags += , @($tag, $zip, "Launcher $version", $true)
    Write-Host "launcher $version"

    # Linux x86_64: binario con el .pck incrustado, empaquetado en .tar.gz (conserva el permiso de ejecución)
    $linuxDir = Join-Path $root "dist/hub-linux"
    $bin = Join-Path $linuxDir "ArcadeStars.x86_64"
    New-Item -ItemType Directory -Force $linuxDir | Out-Null
    Remove-Item $bin -ErrorAction SilentlyContinue
    & $Godot --headless --path $hub --export-release "Linux" $bin | Out-Null
    if (-not (Test-Path $bin)) { throw "Linux launcher export failed" }
    $tgzName = "ArcadeStars-$version-linux-x86_64.tar.gz"
    $tgz = Join-Path $dir $tgzName
    # Desde Windows el archivo no tiene permiso de ejecución: tarfile de Python lo fija a 755 en el .tar.gz
    python (Join-Path $PSScriptRoot "make_tarball.py") $bin $tgz
    if ($LASTEXITCODE -ne 0) { throw "tarball failed" }
    $manifest.launcher_linux = @{ version = $version; url = "$BaseUrl/$tag/$tgzName"; sha256 = (Get-Sha256 $tgz); size = (Get-Item $tgz).Length }
    $tags += , @($tag, $tgz, "Launcher $version", $true)
    Write-Host "launcher-linux $version"
}

# ── Manifest ──
$catalogDir = Join-Path $out "catalog"
New-Item -ItemType Directory -Force $catalogDir | Out-Null
$manifestPath = Join-Path $catalogDir "manifest.json"
# UTF-8 sin BOM (Windows PowerShell 5.1 añade BOM con -Encoding UTF8 y rompería el parseo)
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "manifest -> $manifestPath"

# ── Publicación ──
# Cada versión queda como release propia y PERMANENTE (launcher-x.y.z, game-<id>-x.y.z): nada se borra
# al publicar otra, así que todas las versiones pasadas siguen descargables en la página de Releases.
# Además se crea una etiqueta git en el commit actual con el mismo nombre (código fuente de esa versión).
# Solo las releases del launcher se marcan como "Latest"; juegos y catálogo no.
#
# `gh` y `git` escriben en stderr en casos normales ("no existe"); con $ErrorActionPreference = "Stop"
# eso abortaría el script, por eso esas consultas se hacen en modo "Continue".
function Test-Release($tag) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    gh release view $tag 2>&1 | Out-Null
    $exists = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $prev
    return $exists
}
function Ensure-GitTag($tag) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    git rev-parse -q --verify "refs/tags/$tag" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { git tag $tag 2>&1 | Out-Null }
    $remote = git ls-remote --tags origin "refs/tags/$tag" 2>$null
    $ok = $true
    if (-not $remote) { git push origin $tag 2>&1 | Out-Null; $ok = ($LASTEXITCODE -eq 0) }
    $ErrorActionPreference = $prev
    if (-not $ok) { throw "Could not push git tag $tag" }
}
function Publish-Release($tag, $file, $title, [bool]$latest, [bool]$sourceTag) {
    $latestFlag = "--latest=" + $latest.ToString().ToLower()
    if (Test-Release $tag) {
        gh release upload $tag $file --clobber
    } elseif ($sourceTag) {
        Ensure-GitTag $tag
        gh release create $tag $file --title $title --notes $title --verify-tag $latestFlag
    } else {
        gh release create $tag $file --title $title --notes $title $latestFlag
    }
    if ($LASTEXITCODE -ne 0) { throw "gh failed for $tag" }
}
if ($Publish) {
    foreach ($t in $tags) { Publish-Release $t[0] $t[1] $t[2] $t[3] $true }
    Publish-Release "catalog" $manifestPath "Catalog" $false $false
    Write-Host "Published. Next: git push (rebuilds the server)."
} else {
    Write-Host "Dry run: nothing published (use -Publish)."
}
