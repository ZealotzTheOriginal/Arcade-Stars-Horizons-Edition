# Cómo publicar (chuleta)

Todo desde la raíz del repo, en PowerShell. Requiere `gh auth login` con una cuenta con permisos de escritura en el repo.

## Nueva versión del launcher
1. Sube `config/version` en `arcade-stars-horizons-edition/project.godot` (p. ej. `1.0.1` -> `1.0.2`).
2. `git add -A; git commit -m "Launcher 1.0.2"`
3. `.\tools\release.ps1 -Launcher -Publish`
4. `git push`

Los launchers instalados verán el aviso **UPDATE** y se actualizarán solos.
Si no subes el número, los launchers instalados nunca detectarán el cambio.

## Nueva versión de un juego
1. Sube `version` en `games/<id>/<id>/manifest.json`.
2. `git add -A; git commit -m "<id> 1.2.0"`
3. `.\tools\release.ps1 -Games <id> -Publish`   (primero las releases)
4. `git push`   (después; Render reconstruye el servidor con la lógica y el catálogo nuevos)

Los jugadores verán **UPDATE AVAILABLE** en la pestaña Library; mientras no actualicen figuran como *MISSING GAME* en las salas.

## Las dos cosas a la vez
`.\tools\release.ps1 -Launcher -Games all -Publish` y después `git push`.

## Probar sin publicar
Quita `-Publish`: genera todo en `dist/release/` sin subir nada (revisa `dist/release/catalog/manifest.json`).

## Cambio de protocolo (rompe launchers antiguos)
Sube `MIN_LAUNCHER_VERSION` en `arcade-stars-horizons-edition/server/server_main.gd` a la versión nueva del launcher.
Los antiguos verán el aviso rojo de actualización obligatoria.

## Historial de versiones (todas las versiones pasadas)
Cada publicación crea una release **propia y permanente** en GitHub: `launcher-1.1.0`, `game-minesweeper-1.2.0`…
Publicar una versión nueva no borra las anteriores, así que todas siguen descargables en la página de Releases
(*Settings → All versions* en el launcher). Además el script crea una **etiqueta git** con el mismo nombre en el commit
publicado, para poder reconstruir cualquier versión desde el código. Solo las releases del launcher se marcan como "Latest".

GitHub no cobra ni limita el espacio total de las releases de un repo público (cada archivo, hasta 2 GB), así que
conservarlas todas es lo normal. Si algún día molestan, se borra una con `gh release delete launcher-1.0.0`
(el catálogo nunca apunta a versiones antiguas, así que no afecta a los jugadores).

## Primera entrega a una persona nueva
Basta con `ArcadeStars.exe` (de `dist/hub/`, o el zip de la última release `launcher-x.y.z`), en una carpeta con permiso
de escritura. Los juegos se descargan desde la pestaña Library y el launcher se actualiza solo.

## Problemas típicos
- `Remove-Item ... IOException` al generar: algún programa tiene abierta `dist/release`; el script ya lo tolera.
- `gh` sin permisos: `gh auth status` y `gh auth login` con la cuenta propietaria.
- Un jugador no ve la actualización del launcher: su `.exe` está en una carpeta sin permiso de escritura (Archivos de programa).
