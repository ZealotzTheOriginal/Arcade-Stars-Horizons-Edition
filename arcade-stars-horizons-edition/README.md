# Arcade Stars — Horizons Edition

Hub en Godot 4.7 (GDScript) + minijuegos que se instalan como `.pck`, con servidor autoritativo online.

```
Cliente (hub .exe + games/*.pck) ──wss──► Servidor Godot headless (Render) ──REST──► Supabase
```

## Estructura del repositorio

| Ruta | Qué es |
|---|---|
| `arcade-stars-horizons-edition/` | Proyecto Godot del **hub** (cliente) y del **servidor** (`server/`). |
| `games/<id>/` | Un proyecto Godot **por juego**. Todo su contenido vive bajo `res://<id>/` (evita choques al montar el `.pck`). |
| `tools/` | `build_games.ps1` (exporta los `.pck` a `dist/games/`), `sync_server_logic.*` (copia la lógica de los juegos al servidor). |
| `supabase/schema.sql` | Esquema SQL (perfiles, partidas, ranking, RLS). |
| `Dockerfile` | Imagen del servidor para Render. |
| `dist/` | Generado (ignorado por git): `.pck` y ejecutable del hub. |

### Hub (`arcade-stars-horizons-edition/`)
| Ruta | Qué hace |
|---|---|
| `scripts/theme/`, `assets/` | Estética del hub (paleta, tema, fondo). **Solo afecta al hub**: los juegos no la usan. |
| `scripts/ui/hub.gd` | Presencia, salas, sala actual, estado de juegos instalados. |
| `scripts/net/auth.gd`, `backend.gd` | Login anónimo de Supabase y conexión WebSocket al servidor. |
| `scripts/net/net.gd`, `lobby.gd` | Estado de sala/partida y presencia como señales para la UI. |
| `scripts/net/game_registry.gd` | Catálogo de juegos conocido (nombre, versión, jugadores, ajustes). |
| `scripts/net/game_loader.gd` | Escanea y monta los `.pck`, valida manifiestos y lanza juegos. |
| `scripts/net/game_context.gd` | Lo único que un juego conoce del hub (ver contrato). |
| `server/` | Servidor headless: sesiones, salas, partidas, escritura en Supabase. |

## Juegos como `.pck`

El hub **no incluye ningún juego**. Cada `.pck` se busca en `user://games/` (Settings → *Open games folder*),
`<carpeta del .exe>/games/` y, en el editor, `<repo>/dist/games/`. Si un juego está en varias, gana la **versión más alta**.
Con la variable `ASH_GAMES_DIR` se usa solo esa carpeta (pruebas).
Al volver a la ventana del hub se detectan `.pck` recién copiados.

**Biblioteca (pestaña *Library*):** muestra el catálogo que envía el servidor con el estado de cada juego
(Installed / Update available / Not installed) y descarga o actualiza el `.pck` desde GitHub Releases
(verificación SHA-256, solo desde el repo de releases). Si el juego ya estaba cargado, la actualización se aplica al reiniciar.
*Uninstall* (con confirmación) borra el `.pck` de `user://games` y de `<exe>/games` (útil si un archivo se corrompe);
reinstalarlo en la misma sesión también se aplica al reiniciar, porque el motor no desmonta un `.pck` ya cargado.

El nickname elegido en *Settings* se guarda en el dispositivo (`user://player_<perfil>.cfg`).

Un `.pck` ejecuta código: instala solo los que vengan de una fuente de confianza.
El hub solo monta `.pck` cuyo nombre coincide con un juego del catálogo y cuyo `manifest.json` es válido.

### Contrato de un juego
- **`res://<id>/manifest.json`**: `{ id, name, version, api_version, scene, min_players, max_players, settings }`.
  Es la **fuente del catálogo**: el servidor lo lee de `server/games/<id>/manifest.json` y lo envía a los clientes.
  `api_version` = `GameRegistry.API_VERSION`; la `version` instalada debe ser exactamente la del catálogo
  (si no, el jugador cuenta como "sin el juego" y la Biblioteca ofrece actualizar).
- **Escena raíz** con `start(ctx)`. `ctx` (`GameContext`) es **funcional**: `my_id()`, `is_host()`, `player_name(id)`,
  `player_color(id)`, señal `view_received(view)`, `send_ready()`, `send_action(payload)`, `back_to_room()`, `leave()`.
- **Estética: libre.** El juego trae su propio estilo (ver `games/minesweeper/minesweeper/style.gd`).
  Opcionalmente puede usar `ctx.hub_theme()` / `ctx.create_hub_background()` para seguir el diseño del hub.
- **Ventana:** el launcher es sin bordes y su barra vive en un autoload. En juego se muestra un grupo flotante discreto
  arriba a la derecha (deja ~48 px libres arriba a la derecha); `ctx.set_window_controls_visible(false)` lo oculta.
- **Lógica del servidor** `res://<id>/<id>_logic.gd`: `_init(settings, peer_ids)`, `handle_action(pid, payload) -> bool`,
  `view()`, `remove_player(pid)`, `is_over()`, `results()`. El servidor la carga desde `server/games/<id>/` (generado con `tools/sync_server_logic`).
- Para probarlo solo: abrir `games/<id>/` en Godot y ejecutar (usa `dev/mock_context.gd`).

### Añadir un juego
1. Crear `games/<id>/` (proyecto Godot con preset `pck`), con el contrato anterior y su `manifest.json`.
2. `tools\release.ps1 -Games <id> -Publish` y después `git push` (ver *Publicar versiones*).

## Desarrollo local

```
# generar .pck y copiar la lógica al servidor
.\tools\build_games.ps1
.\tools\sync_server_logic.ps1
# terminal 1: servidor sin Supabase
ASH_DEV_AUTH=1 PORT=9081 godot --headless --path arcade-stars-horizons-edition res://server/server.tscn
# terminales 2 y 3: clientes
ASH_DEV_AUTH=1 ASH_SERVER_URL=ws://127.0.0.1:9081 godot --path arcade-stars-horizons-edition -- --profile=1
ASH_DEV_AUTH=1 ASH_SERVER_URL=ws://127.0.0.1:9081 godot --path arcade-stars-horizons-edition -- --profile=2
```
`ASH_DEV_AUTH=1` omite Supabase (solo local; **nunca** en Render). `--profile=N` da una sesión anónima distinta por instancia.
Con Supabase real: `.env` (ver `.env.example`) y sin `ASH_DEV_AUTH`. Pruebas automáticas: `scripts/dev/smoke_test.gd`.

## Ventana, escala y fondo

- **Ventana de tamaño fijo** (`scripts/ui/window_chrome.gd`), como los launchers de juegos: grande (1280×720, por defecto)
  o reducida (1024×576), elegible en *Settings → Window size* y recordada en `user://ui.cfg`. Sin maximizar, sin encajar
  y sin redimensionar; solo minimizar, cerrar (con confirmación) y arrastrar. Si el tamaño grande no cabe, se usa el reducido.
- **Esquinas redondeadas y borde suave**: `assets/window_frame.gdshader` recorta las esquinas (transparencia por píxel)
  y dibuja un borde de 1 px encima de todo.
- **Escala:** la interfaz solo se ajusta al DPI de la pantalla (125 %, 150 %…); `ASH_UI_SCALE=1.5` fuerza un factor.
- **Fondo** (`assets/starfield.gdshader`, `scripts/ui/star_field.gd`): estrellas nítidas en píxeles físicos, nebulosas
  que destellan y estrellas fugaces (port de `starfield-background.ts` de Pro-Clustark). Anclado a la ventana.
  El shader respeta la opacidad heredada: si no, el fondo aparecía opaco de golpe durante el fundido de entrada.
- **Tipografía:** solo **Inter** (variable); todo en MAYÚSCULAS y la jerarquía solo por peso (800 marca, 700 títulos,
  600 botones/enlaces, 500 texto, 400 secundario). Paneles translúcidos sin borde. Navegación estilo navbar de Clustark.
- **Arranque:** sin splash de Godot; la ventana nace de 8×8 px y transparente. El splash (`scenes/splash.tscn`) ya usa
  el tamaño final del launcher (solo su zona central recibe el ratón) y el hub aparece en el sitio con un fundido, sin
  redimensionar. Clic o tecla saltan el splash; `ASH_NO_SPLASH=1` lo omite.
- **Sidebar "Online"** plegable (se recuerda). **Library** compacta: una sola acción por juego.
- Cada juego trae su propia copia del fondo y del estilo (`games/<id>/<id>/background.gd`, `style.gd`) y no referencia
  ningún archivo ni nodo del hub.

## Publicar versiones (launcher y juegos)

Chuleta rápida e historial de versiones en `RELEASING.md`.

Todo se distribuye por **GitHub Releases** del repo. `tools\release.ps1` empaqueta, calcula SHA-256 y escribe el
catálogo `manifest.json` (release con tag `catalog`, URL fija):

```
.\tools\release.ps1 -Games minesweeper              # prueba en seco: solo genera dist/release/
.\tools\release.ps1 -Launcher -Games all -Publish   # genera y sube (necesita `gh auth login` con permisos de escritura)
```
- Versión del **launcher**: `config/version` en `arcade-stars-horizons-edition/project.godot`. Súbela en cada publicación.
- Versión de un **juego**: `version` en `games/<id>/<id>/manifest.json`.
- **Orden al publicar un juego nuevo/actualizado:** 1) `-Publish`, 2) `git push` (Render reconstruye el servidor con la
  lógica y el catálogo nuevos). Mientras tanto los clientes no ven cambios.
- Cambio de protocolo: sube `MIN_LAUNCHER_VERSION` en `server/server_main.gd`; los launchers antiguos reciben el
  error `outdated` y el hub les obliga a actualizar (banner rojo).
- El launcher se actualiza solo desde el banner *Update* (descarga el zip, verifica el hash, cierra, sustituye el `.exe` y
  se relanza). Requiere que el `.exe` esté en una carpeta con permiso de escritura.

## Distribuir el hub por primera vez

`ArcadeStars.exe` (un solo archivo, con icono) + `games/minesweeper.pck` al lado, en un zip. A partir de ahí el
launcher se actualiza solo y descarga los juegos desde la Biblioteca. Exportar a mano: *Project → Export → Windows Desktop*
(`dist/hub/ArcadeStars.exe`); `tools\release.ps1 -Launcher` lo hace sin abrir el editor.

## Iconos

`assets/icons/logo.png` (512×512, con su fondo circular) es el logo original: lo usan la barra de título y el splash
(reducido en tiempo de ejecución al tamaño físico exacto, para que se vea nítido). `python tools/make_icons.py` genera a
partir de él `icon.png` (icono de ventana) e `icon.ico` (16–256 px, icono del `.exe`, referenciado en el preset de
exportación). Windows necesita el ICO multi-tamaño; el PNG cuadrado sirve en ejecución.

## Despliegue del servidor

1. Supabase: *Authentication → Sign In / Providers → Allow anonymous sign-ins*; ejecutar `supabase/schema.sql`.
2. Render: Web Service Docker (`Dockerfile` en la raíz); variables `SUPABASE_URL` y `SUPABASE_SECRET_KEY`.
3. URL pública del servidor en `AppConfig.SERVER_URL`.
