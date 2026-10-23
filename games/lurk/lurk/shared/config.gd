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

# ── Salud ────────────────────────────────────────────────
const MAX_HP := 3.0
const DAMAGED_HP := 1.5

## Lado del mapa para `players` jugadores: fijo hasta BASE_PLAYERS; después crece con el área.
static func map_size_for(players: int) -> float:
	return MAP_BASE * sqrt(maxf(players, BASE_PLAYERS) / float(BASE_PLAYERS))
