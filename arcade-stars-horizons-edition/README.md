# Arcade Stars — Horizons Edition

Hub en Godot 4.7 (GDScript) + minijuegos cargables como `.pck`, con servidor autoritativo online.

```
Cliente Godot ──wss──► Servidor Godot headless (Render) ──REST──► Supabase (Auth anónima, perfiles, partidas)
```

## Estructura

| Ruta | Qué hace |
|---|---|
| `scripts/theme/`, `assets/starfield.gdshader` | Paleta Clustark, Theme por código, fondo procedural de estrellas/nebulosas. |
| `scripts/ui/hub.gd` | Hub: presencia, lista de salas, sala actual. |
| `scripts/net/auth.gd` | Login anónimo de Supabase (clave publicable). Refresh token por perfil en `user://`. |
| `scripts/net/backend.gd` | WebSocket al servidor: handshake, ping, reconexión. |
| `scripts/net/net.gd`, `lobby.gd` | Estado de sala/partida y presencia, expuestos a la UI como señales. |
| `scripts/net/game_registry.gd` | Metadatos de juegos compartidos por cliente y servidor. |
| `scripts/net/game_loader.gd` | Carga dinámica de `.pck` de juegos. |
| `scripts/net/app_config.gd` | Config pública (URL Supabase, clave publicable, URL del servidor). |
| `server/` | Servidor headless: sesiones, salas, partidas, escritura en Supabase. |
| `games/minesweeper/` | Cliente (UI) + lógica (`minesweeper_logic.gd`, la ejecuta el servidor). |
| `../supabase/schema.sql` | Esquema SQL (perfiles, partidas, ranking, RLS). |
| `../Dockerfile` | Imagen del servidor para Render. |

## Desarrollo local sin Supabase

```
# terminal 1: servidor
ASH_DEV_AUTH=1 PORT=9081 godot --headless --path . res://server/server.tscn
# terminal 2 y 3: clientes (cada uno con su perfil)
ASH_DEV_AUTH=1 ASH_SERVER_URL=ws://127.0.0.1:9081 godot --path . -- --profile=1
ASH_DEV_AUTH=1 ASH_SERVER_URL=ws://127.0.0.1:9081 godot --path . -- --profile=2
```
`ASH_DEV_AUTH=1` omite Supabase (solo local; **nunca** en Render). Test automático: ver `scripts/dev/smoke_test.gd`.

Con Supabase real: copia `.env.example` a `.env`, rellena `SUPABASE_SECRET_KEY` y arranca el servidor sin `ASH_DEV_AUTH`.
Para dos instancias en un mismo PC usa perfiles distintos (`-- --profile=2`); el servidor cierra la sesión duplicada de un mismo usuario.

## Despliegue

1. Supabase: *Authentication → Sign In / Providers → Allow anonymous sign-ins*; ejecutar `supabase/schema.sql`.
2. Render: Web Service, runtime Docker (Dockerfile en la raíz), variables `SUPABASE_URL` y `SUPABASE_SECRET_KEY`.
3. Poner la URL `wss://<servicio>.onrender.com` en `AppConfig.SERVER_URL`.

## Contrato de un minijuego

- **Servidor:** clase con `_init(settings, peer_ids)`, `handle_action(pid, payload) -> bool`, `view() -> Dictionary`,
  `remove_player(pid)`, `is_over()`, `results()`; se registra en `GameRegistry.GAMES[id].logic`.
- **Cliente:** escena raíz con `start(players, settings)`; escucha `Net.game_view`, llama a `Net.send_game_ready()`
  al cargar y envía acciones con `Net.send_game_action(payload)`. Vuelta a la sala: `Net.return_to_room()`.

## Empaquetar un juego como .pck

*Project → Export → Windows* → pestaña **Resources** → *Export selected resources* con `games/minesweeper/` → *Export PCK/ZIP*.
Colocar en `user://games/` o en `games/` junto al `.exe`. Sin `.pck` se usa la copia embebida (desarrollo).
