extends RefCounted
## Catálogo de power-ups de Lurk (los números son los del GDD). La Sobrecarga del Reactor no sale en
## el reparto normal: aparece dentro de una caja que hay que destruir a disparos.

enum Kind {
	VISOR = 1,        # +25 % de radio de visión hasta morir
	RADAR = 2,        # cada pocos segundos, posición aproximada de los rivales (sonar)
	HEAVY = 3,        # cargador completo de disparos en abanico (3 balas por disparo)
	REDEEMER = 4,     # un misil teledirigido con onda expansiva
	SHIELD = 5,       # 30 s sin daño por choques; las balas hacen 1 en vez de 1.5
	REPAIR = 6,       # vida al máximo
	ARMOR = 7,        # +3 de armadura (hasta 9)
	SPECTRE = 8,      # 30 s invisible para los rivales (disparar o acercarse deja ver un reflejo)
	EXPLOSIVE = 9,    # las balas explotan al impactar (y rompen asteroides)
	PSIONIC = 10,     # 5 s de naves fantasma con glitch en la pantalla de los rivales
	OVERLOAD = 11,    # Sobrecarga del Reactor (ver GDD 6.1)
}

## Los que salen repartidos por el mapa.
const NORMAL := [Kind.VISOR, Kind.RADAR, Kind.HEAVY, Kind.REDEEMER, Kind.SHIELD, Kind.REPAIR,
	Kind.ARMOR, Kind.SPECTRE, Kind.EXPLOSIVE, Kind.PSIONIC]

const NAMES := {
	Kind.VISOR: "Tactical Visor", Kind.RADAR: "Signal Radar", Kind.HEAVY: "Heavy Weapon",
	Kind.REDEEMER: "The Redeemer", Kind.SHIELD: "Collision Shield", Kind.REPAIR: "Auxiliary Kit",
	Kind.ARMOR: "Cruiser Armor", Kind.SPECTRE: "Spectre Cloak", Kind.EXPLOSIVE: "Explosive Charge",
	Kind.PSIONIC: "Psionic Sabotage", Kind.OVERLOAD: "Reactor Overload",
}
