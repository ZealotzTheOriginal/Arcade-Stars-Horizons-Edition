shader_type canvas_item;
// Borde animado del botón especial (AccentButton): un anillo fino con forma de rectángulo redondeado
// cuyo color sale de un mapa de Voronoi que se mueve despacio. Cada celda recorre en bucle los tres
// acentos de la paleta (rosa -> verde -> azul) con un desfase propio; las fronteras entre celdas se
// aclaran un poco. Se dibuja encima del botón y fuera del anillo es totalmente transparente.

uniform vec2 size_px = vec2(160.0, 40.0);      // tamaño del botón (px lógicos)
uniform float radius_px = 6.0;
uniform float border_px = 1.5;
uniform vec4 color_a : source_color = vec4(0.925, 0.698, 1.0, 1.0);   // ACC_PINK
uniform vec4 color_b : source_color = vec4(0.525, 0.969, 0.188, 1.0); // ACC_GREEN
uniform vec4 color_c : source_color = vec4(0.651, 0.784, 1.0, 1.0);   // ACC_BLUE
uniform float cell_px = 28.0;      // tamaño medio de una celda de Voronoi
uniform float cycle_speed = 0.22;  // vueltas de color por segundo
uniform float drift_speed = 0.7;   // movimiento de los puntos de Voronoi
uniform float intensity = 0.85;    // 1.0 al pasar el ratón
uniform float fade = 1.0;          // opacidad del árbol (un shader que fija COLOR no hereda el modulate)

float sd_round_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Ciclo continuo rosa -> verde -> azul -> rosa.
vec3 accent_cycle(float t) {
	t = fract(t) * 3.0;
	if (t < 1.0) return mix(color_a.rgb, color_b.rgb, smoothstep(0.0, 1.0, t));
	if (t < 2.0) return mix(color_b.rgb, color_c.rgb, smoothstep(0.0, 1.0, t - 1.0));
	return mix(color_c.rgb, color_a.rgb, smoothstep(0.0, 1.0, t - 2.0));
}

void fragment() {
	vec2 p = UV * size_px;
	float d = sd_round_box(p - size_px * 0.5, size_px * 0.5, radius_px);
	float aa = max(fwidth(d), 0.0001);
	float ring = smoothstep(-border_px - aa, -border_px + aa, d) * (1.0 - smoothstep(-aa, aa, d));

	vec2 g = p / cell_px;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float best = 8.0;
	float second = 8.0;
	float phase = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 h = hash2(cell + o);
			vec2 pt = o + 0.5 + 0.45 * sin(TIME * drift_speed + 6.2831 * h) - f;
			float dist = dot(pt, pt);
			if (dist < best) {
				second = best;
				best = dist;
				phase = h.x;
			} else if (dist < second) {
				second = dist;
			}
		}
	}
	vec3 col = accent_cycle(phase + TIME * cycle_speed);
	float edge = 1.0 - smoothstep(0.0, 0.3, sqrt(second) - sqrt(best));
	col = mix(col, vec3(1.0), edge * 0.3);
	COLOR = vec4(col, ring * intensity * fade);
}
