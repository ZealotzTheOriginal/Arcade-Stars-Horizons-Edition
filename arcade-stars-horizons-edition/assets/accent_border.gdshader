shader_type canvas_item;
// Borde animado del botón especial (AccentButton): un anillo fino con forma de rectángulo redondeado
// cuyo color sale de un mapa de Voronoi que se mueve despacio. Cada celda recorre en bucle los tres
// acentos de la paleta (rosa -> verde -> azul) con un desfase propio; las fronteras entre celdas se
// aclaran un poco. También pinta el fondo del botón (detrás del texto) para que fondo y borde
// compartan exactamente el mismo contorno.
//
// Nitidez: con escalado de pantalla (125 %...) el botón cae en posiciones físicas fraccionarias y un
// anillo de 1 px quedaría repartido entre dos píxeles en algunos lados (más grueso y borroso que en
// otros). Por eso el rectángulo se ajusta a la rejilla de píxeles FÍSICOS antes de dibujarlo.

uniform vec2 size_px = vec2(160.0, 40.0);      // tamaño del botón (px lógicos)
uniform float px_scale = 1.0;                  // píxeles físicos por píxel lógico
uniform vec2 origin_frac = vec2(0.0);          // parte fraccionaria de la posición física del botón
uniform float radius_px = 3.0;                 // px lógicos
uniform float border_px = 1.0;                 // grosor en píxeles FÍSICOS
uniform vec4 bg_color : source_color = vec4(0.012, 0.012, 0.055, 1.0);
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
	// Coordenadas en píxeles físicos (centros de píxel en k + 0.5) y rectángulo redondeado a la rejilla.
	vec2 q = p * px_scale + origin_frac;
	vec2 a = round(origin_frac);
	// Borde final: en un empate (.5) se redondea hacia abajo; el píxel cuyo centro cae justo en el borde
	// no lo rasteriza el quad del botón, así que el anillo quedaría fuera.
	vec2 b = floor(origin_frac + size_px * px_scale + 0.499);
	float d = sd_round_box(q - (a + b) * 0.5, (b - a) * 0.5, radius_px * px_scale);
	// Cobertura del píxel sobre la franja [-border_px, 0] pegada al contorno (y sobre el interior).
	float lo = max(d - 0.5, -border_px);
	float hi = min(d + 0.5, 0.0);
	float ring = clamp(hi - lo, 0.0, 1.0) * intensity;
	float inside = clamp(0.5 - d, 0.0, 1.0) * bg_color.a;

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
	// Anillo sobre el fondo ("over" con alfa normal)
	float alpha = ring + inside * (1.0 - ring);
	vec3 rgb = (col * ring + bg_color.rgb * inside * (1.0 - ring)) / max(alpha, 0.0001);
	COLOR = vec4(rgb, alpha * fade);
}
