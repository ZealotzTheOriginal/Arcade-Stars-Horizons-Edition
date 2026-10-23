shader_type canvas_item;
// Fondo cósmico: estrellas nítidas en píxeles físicos (borde antialiasado de 1 px), nebulosas que
// destellan y viñeta suave. Va anclado a la ventana (el launcher tiene tamaño fijo).

uniform vec2 window_px = vec2(1280.0, 720.0); // tamaño de la ventana (px físicos)
uniform sampler2D noise_tex : repeat_enable, filter_linear;

uniform vec4 void_color : source_color = vec4(0.0118, 0.0118, 0.0549, 1.0);
uniform vec4 nebula_a : source_color = vec4(0.525, 0.969, 0.188, 1.0);   // verde
uniform vec4 nebula_b : source_color = vec4(0.651, 0.784, 1.0, 1.0);     // azul
uniform vec4 nebula_c : source_color = vec4(0.925, 0.698, 1.0, 1.0);     // rosa
uniform float nebula_strength : hint_range(0.0, 1.0) = 0.10;
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

// Envolvente de un destello: sube (fade_in), se mantiene (hold) y baja (fade_out) dentro de un ciclo.
// `cycle` devuelve el número de ciclo (sirve para cambiar de lugar en cada destello).
float flash(float period, float phase_s, float fade_in, float hold, float fade_out, out float cycle) {
	float t = TIME + phase_s;
	cycle = floor(t / period);
	float a = t - cycle * period;
	return smoothstep(0.0, fade_in, a) * (1.0 - smoothstep(fade_in + hold, fade_in + hold + fade_out, a));
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
	float inherited_alpha = COLOR.a;    // modulate heredado (p. ej. el fundido de entrada del hub)
	vec2 p = UV * window_px;            // píxeles físicos de la ventana
	vec3 col = void_color.rgb;

	// Nebulosas que DESTELLAN: cada capa sube, se mantiene un instante y se apaga; en cada ciclo
	// aparece en otro lugar del campo. El ruido fractal está precalculado en textura (barato).
	vec2 q = p / nebula_scale;
	float c1; float c2; float c3;
	float f1 = flash(17.0, 2.0, 1.4, 1.6, 5.0, c1);
	float f2 = flash(23.0, 9.0, 1.4, 1.4, 5.5, c2);
	float f3 = flash(29.0, 15.0, 1.6, 1.2, 5.0, c3);
	float n1 = texture(noise_tex, q + hash22(vec2(c1, 1.0)) * 7.0).r;
	float n2 = texture(noise_tex, q * 0.75 + hash22(vec2(c2, 2.0)) * 7.0).r;
	float n3 = texture(noise_tex, q * 1.35 + hash22(vec2(c3, 3.0)) * 7.0).r;
	col += nebula_b.rgb * smoothstep(0.50, 0.88, n1) * nebula_strength * f1;
	col += nebula_c.rgb * smoothstep(0.52, 0.90, n2) * nebula_strength * 0.8 * f2;
	col += nebula_a.rgb * smoothstep(0.60, 0.95, n3) * nebula_strength * 0.5 * f3;

	col += vec3(stars(p));

	// Viñeta muy suave respecto a la ventana y dither para evitar bandas en el degradado.
	float v = smoothstep(1.25, 0.45, length(UV - 0.5) * 1.35);
	col *= mix(0.8, 1.0, v);
	col += (hash21(FRAGCOORD.xy) - 0.5) / 255.0;
	// Respetar el modulate: con alfa fija 1.0 el fondo aparecía opaco de golpe durante el fundido
	// de entrada (el "cuadrado negro" al abrir el launcher).
	COLOR = vec4(col, inherited_alpha);
}
