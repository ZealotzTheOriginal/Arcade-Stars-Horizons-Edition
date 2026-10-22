shader_type canvas_item;
// Fondo cósmico anclado al ESCRITORIO: la ventana es un "portal" sobre un campo de estrellas fijo.
// Al mover o redimensionar la ventana no se estira nada: se descubren otras zonas del campo.
// Todo se calcula en píxeles físicos (nítido a cualquier escala) con borde antialiasado de 1 px.

uniform vec2 window_origin = vec2(0.0);   // posición de la ventana en el escritorio (px)
uniform vec2 window_px = vec2(1280.0, 720.0); // tamaño de la ventana (px físicos)
uniform sampler2D noise_tex : repeat_enable, filter_linear;

uniform vec4 void_color : source_color = vec4(0.0118, 0.0118, 0.0549, 1.0);
uniform vec4 nebula_a : source_color = vec4(0.525, 0.969, 0.188, 1.0);   // verde
uniform vec4 nebula_b : source_color = vec4(0.651, 0.784, 1.0, 1.0);     // azul
uniform vec4 nebula_c : source_color = vec4(0.925, 0.698, 1.0, 1.0);     // rosa
uniform float nebula_strength : hint_range(0.0, 1.0) = 0.16;
uniform float nebula_scale = 2600.0;      // px por repetición de la textura de ruido
uniform float cell = 104.0;               // px por celda de estrellas (~1 estrella por celda)

float hash11(float x) {
	x = fract(x * 0.1031);
	x *= x + 33.33;
	x *= x + x;
	return fract(x);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Estrellas: parpadeo coseno por estrella (periodo 3-8 s), radio 0.6-2.3 px, opacidad base 0.2-0.75.
float stars(vec2 p) {
	vec2 base = floor(p / cell);
	float acc = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			vec2 id = base + vec2(float(dx), float(dy));
			if (hash21(id + 11.0) > 0.88) continue;               // algunas celdas vacías
			vec2 pos = (id + 0.12 + 0.76 * hash22(id)) * cell;
			float r = mix(0.6, 2.3, hash21(id + 3.7));
			float base_op = mix(0.2, 0.75, hash21(id + 7.3));
			float period = mix(3.0, 8.0, hash21(id + 13.1));
			float phase = hash21(id + 21.9);
			float wave = 0.5 + 0.5 * cos(6.2831853 * (TIME / period + phase));
			float op = clamp(0.12 + (base_op - 0.12) * wave, 0.0, 1.0);
			float d = distance(p, pos);
			acc += op * clamp(r + 0.5 - d, 0.0, 1.0);             // disco con borde de 1 px
		}
	}
	return clamp(acc, 0.0, 1.0);
}

void fragment() {
	vec2 p = UV * window_px + window_origin;    // coordenadas de escritorio (px)
	vec3 col = void_color.rgb;

	// Nebulosas: ruido fractal precalculado en textura (barato) y muestreado con deriva lenta.
	vec2 q = p / nebula_scale;
	float n1 = texture(noise_tex, q + vec2(TIME * 0.0015, 0.0)).r;
	float n2 = texture(noise_tex, q * 0.75 + vec2(0.37, 0.61 - TIME * 0.001)).r;
	float n3 = texture(noise_tex, q * 1.35 + vec2(0.71, 0.13)).r;
	col += nebula_b.rgb * smoothstep(0.50, 0.88, n1) * nebula_strength;
	col += nebula_c.rgb * smoothstep(0.52, 0.90, n2) * nebula_strength * 0.8;
	col += nebula_a.rgb * smoothstep(0.60, 0.95, n3) * nebula_strength * 0.35;

	col += vec3(stars(p));

	// Viñeta muy suave respecto a la ventana y dither para evitar bandas en el degradado.
	float v = smoothstep(1.25, 0.45, length(UV - 0.5) * 1.35);
	col *= mix(0.8, 1.0, v);
	col += (hash21(FRAGCOORD.xy) - 0.5) / 255.0;
	COLOR = vec4(col, 1.0);
}
