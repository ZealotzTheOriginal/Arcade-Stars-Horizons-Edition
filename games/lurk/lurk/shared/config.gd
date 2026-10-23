extends RefCounted
## Constantes de Lurk compartidas por el servidor (simulación autoritativa) y el cliente (predicción
## de la nave propia). Unidades: píxeles del mundo y segundos.

# ── Red ──────────────────────────────────────────────────
const TICK_RATE := 30            # pasos de simulación por segundo
const SNAPSHOT_EVERY := 2        # se envía estado cada N pasos (15 Hz)
const MAX_QUEUED_INPUTS := 6     # entradas encoladas por jugador (más = latencia: se descartan las viejas)

# ── Mapa ─────────────────────────────────────────────────
const MAP_BASE := 7000.0         # lado del mapa con hasta BASE_PLAYERS jugadores
const BASE_PLAYERS := 5
const BORDER_RESTITUTION := 0.45

# ── Asteroides ───────────────────────────────────────────
const ASTEROID_COVERAGE := 0.085     # fracción del área cubierta
const ASTEROID_MIN_R := 26.0
const ASTEROID_MAX_R := 150.0
const ASTEROID_GAP := 130.0          # separación mínima entre bordes al generar (pasillos navegables)
const ASTEROID_SPEED_MIN := 6.0
const ASTEROID_SPEED_MAX := 24.0
const ASTEROID_RESTITUTION := 0.9

# ── Gemas ────────────────────────────────────────────────
const GEM_CELL := 400.0              # ~1 gema por celda de 400×400
const GEM_RADIUS := 9.0
const GEM_RESPAWN := 20.0            # segundos hasta que una gema recogida reaparece en otro sitio

# ── Nave ─────────────────────────────────────────────────
const SHIP_RADIUS := 15.0
const SHIP_MAX_SPEED := 430.0
const SHIP_ACCEL := 950.0
const SHIP_DAMPING := 1.4            # amortiguación por segundo (fricción espacial "arcade")
const SHIP_DAMAGED_ACCEL := 620.0    # con la nave dañada: menos control y más deslizamiento
const SHIP_DAMAGED_DAMPING := 0.45
const SHIP_RESTITUTION := 0.4        # rebote contra asteroides y bordes
const SHIP_TANGENT_KEEP := 0.92

# ── Visión ───────────────────────────────────────────────
const VISION_RADIUS := 300.0
const VISION_MARGIN := 140.0         # se envía un poco más allá para que lo que entra aparezca suave

# ── Salud y daño ─────────────────────────────────────────
const MAX_HP := 3.0
const DAMAGED_HP := 1.5
const BULLET_DAMAGE := 1.5
const HARD_HIT_DAMAGE := 1.0         # choque a >= 50 % de la velocidad máxima (delata)
const SOFT_HIT_DAMAGE := 0.1         # choque más suave (silencioso)
const SOFT_HIT_MIN_SPEED := 60.0     # por debajo, rozar no hace daño
const HIT_COOLDOWN := 0.5            # un mismo contacto no resta vida varias veces seguidas
const KILL_CREDIT_TIME := 5.0        # quien te dañó en estos segundos se lleva la muerte
const RESPAWN_INVULNERABLE := 2.0    # se pierde al disparar

# ── Disparo ──────────────────────────────────────────────
const AMMO := 3
const RELOAD_TIME := 5.0             # solo al vaciar el cargador (no hay recarga manual)
const FIRE_COOLDOWN := 0.28
const BULLET_SPEED := 1650.0
const BULLET_RANGE := 1500.0
const BULLET_RADIUS := 3.0
const BULLET_VISIBLE_RANGE := 2200.0 # los rivales ven las balas (no lo que iluminan) hasta esta distancia
const REVEAL_TIME := 3.0             # disparar o chocar fuerte: flecha en la pantalla de los rivales

# ── Túneles de luz (los proyectiles iluminan para quien dispara) ──
const TUNNEL_RADIUS := 120.0
const TUNNEL_TIME := 0.7             # lo iluminado vuelve a la oscuridad en este tiempo
const TUNNEL_SEG_TICKS := 4          # cada cuántos pasos se cierra un tramo de túnel
const FLASH_RADIUS := 170.0          # destello del impacto de una bala propia
const FLASH_TIME := 0.5

## Lado del mapa para `players` jugadores: fijo hasta BASE_PLAYERS; después crece con el área.
static func map_size_for(players: int) -> float:
	return MAP_BASE * sqrt(maxf(players, BASE_PLAYERS) / float(BASE_PLAYERS))
