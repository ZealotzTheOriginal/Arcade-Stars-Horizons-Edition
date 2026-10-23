shader_type canvas_item;
// Marcador de portada: fondo liso con estrellas que giran en espiral alrededor del centro. Las
// estrellas viven en coordenadas polares "retorcidas" (ángulo + log del radio), así cada fila de celdas forma un brazo de espiral; al avanzar el tiempo giran y se acercan lentamente al centro.
// Ligero a propósito (3 capas, una celda por capa): debe ir bien en gráficas integradas antiguas.

uniform vec2 size_px = vec2(210.0, 210.0);    // tamaño de la tarjeta (px lógicos)
uniform vec4 bg_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 star_color : source_color = vec4(1.0);
uniform vec2 center_uv = vec2(0.5, 0.5);
uniform float spin = 0.06;        // vueltas por segundo
uniform float inflow = 0.05;      // velocidad hacia el centro
uniform float fade = 1.0;         // opacidad del árbol (un shader que fija COLOR no hereda el modulate)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Una capa de estrellas: `arms` celdas por vuelta, `rings` celdas por unidad de log(r).
float layer(vec2 p, float arms, float rings, float twist, float speed, float seed) {
	float r = length(p);
	float a = atan(p.y, p.x) / 6.28318;
	float lr = log(max(r, 1.0));
	vec2 g = vec2((a + TIME * spin * speed) * arms + lr * twist, lr * rings + TIME * inflow * speed * rings);
	vec2 cell = floor(g);
	float h = hash(cell + seed);
	if (h < 0.55) {
		return 0.0;    // celdas vacías: no todas tienen estrella
	}
	// Centro de la estrella dentro de su celda, devuelto a cartesianas para que sea redonda
	vec2 c = cell + vec2(0.25 + 0.5 * hash(cell + seed + 1.7), 0.25 + 0.5 * hash(cell + seed + 4.1));
	float slr = (c.y - TIME * inflow * speed * rings) / rings;
	float sa = ((c.x - slr * twist) / arms - TIME * spin * speed) * 6.28318;
	float sr = exp(slr);
	vec2 sp = vec2(cos(sa), sin(sa)) * sr;
	float size = mix(0.6, 1.5, hash(cell + seed + 9.3));
	float d = length(p - sp);
	float star = 1.0 - smoothstep(size * 0.5, size * 0.5 + 1.0, d);
	// Se apagan en el mismo centro (donde se apiñarían) y en el borde de la tarjeta
	float k = smoothstep(3.0, 14.0, sr) * (1.0 - smoothstep(0.42, 0.62, sr / size_px.x));
	float twinkle = 0.55 + 0.45 * sin(TIME * (1.0 + 2.0 * h) + h * 40.0);
	return star * k * twinkle;
}

void fragment() {
	vec2 p = (UV - center_uv) * size_px;
	float s = layer(p, 14.0, 5.0, 1.4, 1.0, 0.0);
	s += layer(p, 22.0, 7.0, 1.4, 0.8, 17.0) * 0.7;
	s += layer(p, 9.0, 4.0, 1.4, 1.25, 41.0) * 0.85;
	vec3 col = mix(bg_color.rgb, star_color.rgb, clamp(s, 0.0, 1.0));
	COLOR = vec4(col, bg_color.a * fade);
}
