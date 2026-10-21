# Arcade Stars — Horizons Edition

Hub en Godot 4.7 (GDScript) + minijuegos cargables como `.pck`. Red P2P con ENet.

## Estructura

| Ruta | Qué hace |
|---|---|
| `scripts/theme/` | `Palette` (colores de Clustark) y `AppTheme` (Theme por código; Space Grotesk + Inter). |
| `assets/starfield.gdshader`, `scripts/ui/star_field.gd` | Fondo procedural: void + nebulosas + estrellas con parpadeo. |
| `scripts/ui/hub.gd` | Hub: presencia, lista de salas, sala actual. UI construida por código. |
| `scripts/net/net.gd` (autoload `Net`) | Crear/unirse a sala con ENet. Host = peer 1 y autoridad. Estado de sala sincronizado por RPC. |
| `scripts/net/lobby.gd` (autoload `Lobby`) | Presencia + salas visibles. Hoy: descubrimiento UDP (LAN y varias instancias en un PC). |
| `scripts/net/game_loader.gd` (autoload `GameLoader`) | Registro de juegos (`GAMES`) y montaje de `.pck`. |
| `games/minesweeper/` | Buscaminas competitivo por turnos (lógica en el host, tablero dibujado por código). |
| `scripts/dev/` | `smoke_test.gd` (prueba de red headless) y `screenshot.gd`. |

## Probar la conexión P2P (dos instancias)

1. Abre dos instancias (editor: *Debug → Customize Run Instances → Enable Multiple Instances*, o ejecuta el proyecto dos veces).
2. Instancia A: **Crear sala**. Instancia B: aparece en la lista (o *Conexión directa* → `127.0.0.1`) → **Unirse**.
3. A: **Iniciar partida**.

Entre PCs distintos: misma LAN y abrir en el firewall UDP 24680-24689 (juego) y 47777-47786 (descubrimiento); o conexión directa por IP.

Prueba automática sin UI:
```
godot --headless --path . -s res://scripts/dev/smoke_test.gd -- host
godot --headless --path . -s res://scripts/dev/smoke_test.gd -- join   # en otra terminal
```

## Contrato de un minijuego

- Escena raíz con método `start(players: Dictionary, settings: Dictionary)` (`players`: `peer_id -> {name, color}`).
- Usa `Net` para RPC; el host es autoritativo. Para volver: `Net.return_to_room()`.
- Se registra en `GameLoader.GAMES` (nombre, escena, jugadores, `settings` que el hub pinta como selectores).

## Empaquetar un juego como .pck

*Project → Export → Add… → Windows* (solo para tener preset), pestaña **Resources** → *Export selected resources* y marca `games/minesweeper/`. Luego *Export PCK/ZIP* → `minesweeper.pck`.
Colócalo en `user://games/` o en `games/` junto al `.exe` del hub. Sin `.pck`, el hub usa la copia embebida (modo desarrollo).
El .pck depende de `Net`, `Palette`, `AppTheme`, `StarField` del hub (no los incluyas dentro).

## Siguiente paso: presencia online (Supabase / backend previo)

`Lobby` es el único punto a cambiar: debe mantener `users` / `rooms` y emitir `users_changed` / `rooms_changed`.
Un backend solo necesita registrar presencia (`sid`, nombre, sala) y publicar `ip:port` del host; el juego sigue siendo ENet directo
(NAT: UPnP o relay, pendiente).
