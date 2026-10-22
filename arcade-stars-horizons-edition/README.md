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

El hub **no incluye ningún juego**. Cada `.pck` se busca en (por orden):
`user://games/` (botón *Games folder* del hub) · `<carpeta del .exe>/games/` · en el editor, `<repo>/dist/games/`.
Con la variable `ASH_GAMES_DIR` se usa solo esa carpeta (pruebas).
Al volver a la ventana del hub se detectan `.pck` recién copiados. Para **actualizar** un `.pck` ya cargado, reinicia el hub.

Un `.pck` ejecuta código: instala solo los que vengan de una fuente de confianza.
El hub solo monta `.pck` cuyo nombre coincide con un juego del catálogo y cuyo `manifest.json` es válido.

### Contrato de un juego
- **`res://<id>/manifest.json`**: `{ "id", "version", "api_version", "scene" }`. `api_version` debe ser `GameRegistry.API_VERSION`;
  `version` debe coincidir con la del catálogo (si no, el jugador cuenta como "sin el juego").
- **Escena raíz** con `start(ctx)`. `ctx` (`GameContext`) es **funcional**: `my_id()`, `is_host()`, `player_name(id)`,
  `player_color(id)`, señal `view_received(view)`, `send_ready()`, `send_action(payload)`, `back_to_room()`, `leave()`.
- **Estética: libre.** El juego trae su propio estilo (ver `games/minesweeper/minesweeper/style.gd`).
  Opcionalmente puede usar `ctx.hub_theme()` / `ctx.create_hub_background()` para seguir el diseño del hub.
- **Lógica del servidor** `res://<id>/<id>_logic.gd`: `_init(settings, peer_ids)`, `handle_action(pid, payload) -> bool`,
  `view()`, `remove_player(pid)`, `is_over()`, `results()`. El servidor la carga desde `server/games/<id>/` (generado con `tools/sync_server_logic`).
- Para probarlo solo: abrir `games/<id>/` en Godot y ejecutar (usa `dev/mock_context.gd`).

### Añadir un juego
1. Crear `games/<id>/` (proyecto Godot con preset `pck`), con el contrato anterior.
2. Añadir la entrada en `GameRegistry.GAMES` (con `version`).
3. `tools\build_games.ps1` → `dist/games/<id>.pck`.
4. Commit + push (Render reconstruye la imagen con la lógica nueva).

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

## Distribuir el hub a otra persona

1. `tools\build_games.ps1` → `dist/games/minesweeper.pck`.
2. En el editor del hub: *Project → Export → Windows Desktop → Export Project* → `dist/hub/ArcadeStars.exe` (un solo archivo).
3. Carpeta con `ArcadeStars.exe` y `games/minesweeper.pck` al lado → zip → enviar.
   La otra persona descomprime y ejecuta el `.exe`. Solo necesita internet (conecta por `wss://` al servidor).

## Despliegue del servidor

1. Supabase: *Authentication → Sign In / Providers → Allow anonymous sign-ins*; ejecutar `supabase/schema.sql`.
2. Render: Web Service Docker (`Dockerfile` en la raíz); variables `SUPABASE_URL` y `SUPABASE_SECRET_KEY`.
3. URL pública del servidor en `AppConfig.SERVER_URL`.
