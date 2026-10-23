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
const HARD_HIT_DAMAGE := 0.5         # choque a >= 50 % de la velocidad máxima (delata)
const SOFT_HIT_DAMAGE := 0.1         # choque más suave (silencioso)
const SOFT_HIT_MIN_SPEED := 60.0     # por debajo, rozar no hace daño
const HIT_COOLDOWN := 0.5            # un mismo contacto no resta vida varias veces seguidas
const KILL_CREDIT_TIME := 5.0        # quien te dañó en estos segundos se lleva la muerte
const RESPAWN_INVULNERABLE := 2.0    # se pierde al disparar

# ── Disparo ──────────────────────────────────────────────
const AMMO := 3
const RELOAD_TIME := 3.0             # solo al vaciar el cargador (no hay recarga manual)
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

# ── Ruido (delación) ─────────────────────────────────────
const HEARING_RANGE := 1800.0        # choques entre asteroides: se "oyen" hasta aquí
const ROCK_NOISE_MIN_SPEED := 3.0
const ROCK_NOISE_MIN_R := 80.0       # solo suenan los choques entre asteroides grandes
const ROCK_NOISE_COOLDOWN := 3.0
const NOISE_SHOT := 0
const NOISE_CRASH := 1

# ── Explosiones ──────────────────────────────────────────
const BLAST_FLASH_TIME := 0.8
const DEBRIS_SPEED := 28.0           # empuje de los trozos de una roca partida

# ── Power-ups ────────────────────────────────────────────
const POWERUP_BASE := 10             # en el mapa con hasta BASE_PLAYERS jugadores
const POWERUP_PER_PLAYER := 2        # por cada jugador por encima de BASE_PLAYERS
const POWERUP_RADIUS := 16.0
const POWERUP_RESPAWN := 15.0
const POWERUP_SPACING := 1000.0      # siempre alejados entre sí
const VISOR_MULT := 1.25
const RADAR_INTERVAL := 4.0
const RADAR_JITTER := 140.0          # posición aproximada
const RADAR_SHOW := 1.6
const HEAVY_SPREAD := 0.2            # radianes entre las balas del abanico
const MISSILE_SPEED := 560.0
const MISSILE_TURN := 2.6            # rad/s: gira hacia el ratón con suavidad (difícil a propósito)
const MISSILE_RADIUS := 6.0
const MISSILE_LIGHT := 170.0
const MISSILE_BLAST := 240.0
const MISSILE_DAMAGE_INNER := 3.0    # mitad interior del radio
const MISSILE_DAMAGE_OUTER := 1.5
const MISSILE_CARVE := 180.0
const SHIELD_TIME := 30.0
const SHIELD_BULLET_DAMAGE := 1.0
const ARMOR_GAIN := 3.0
const ARMOR_MAX := 9.0
const SPECTRE_TIME := 30.0
const SPECTRE_NEAR := 110.0          # tan cerca, un rival ve el reflejo
const SPECTRE_FIRE_FLASH := 0.6      # disparar deja ver el reflejo un instante
const EXPLOSIVE_RADIUS := 80.0
const EXPLOSIVE_DAMAGE := 0.75
const EXPLOSIVE_CARVE := 70.0
const PSIONIC_TIME := 5.0
const PSIONIC_GHOSTS := 3
const OVERLOAD_TIME := 10.0
const OVERLOAD_MAX_SPEED := 860.0    # doble de velocidad
const OVERLOAD_ACCEL := 1150.0
const OVERLOAD_DAMPING := 0.22       # poca tracción: derrapa mucho
const OVERLOAD_AMMO := 10
const OVERLOAD_BOUNCES := 3
const OVERLOAD_BULLET_DAMAGE := 0.5
const OVERLOAD_GLOW := 280.0         # luz de la nave (visible en la niebla, con sombras)
const OVERLOAD_VISIBLE := 1800.0
const CRATE_HP := 4.5                # tres balas normales
const CRATE_RADIUS := 26.0
const CRATE_RESPAWN := 45.0
const OVERLOAD_DRIFT := 35.0

# ── Puntuación ───────────────────────────────────────────
const SCORE_GEM := 10
const SCORE_POWERUP := 25
const SCORE_KILL := 100
