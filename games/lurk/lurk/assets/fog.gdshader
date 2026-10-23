shader_type canvas_item;
// Niebla de guerra: negro absoluto salvo donde hay luz. Va en un rectángulo a pantalla completa por
// encima del mundo. Fuentes de luz (en píxeles de pantalla):
//   lights[i]   = (x, y, radio, intensidad)     visión de la nave, destellos…
//   seg_a[i]/seg_b[i] = extremos de un tramo de luz (túneles de los proyectiles); seg_a.z = radio,
//                       seg_a.w = intensidad
// El borde de cada luz es suave y "respira" un poco con ruido para que no parezca un círculo perfecto.

const int MAX_LIGHTS = 24;
const int MAX_SEGS = 64;

uniform vec2 screen_size = vec2(1280.0, 720.0);
uniform vec4 lights[MAX_LIGHTS];
uniform int light_count = 0;
uniform vec4 seg_a[MAX_SEGS];
uniform vec4 seg_b[MAX_SEGS];
uniform int seg_count = 0;
uniform float edge = 0.45;    // fracción del radio que ocupa el degradado del borde

// Hash sin seno ("hash without sine", D. Hoskins): fract(sin(x)) pierde precisión en algunas GPU y
// deja bloques con cortes rectos en el ruido.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float circle_light(vec2 p, vec4 l) {
	float d = distance(p, l.xy);
	return (1.0 - smoothstep(l.z * (1.0 - edge), l.z, d)) * l.w;
}

float segment_light(vec2 p, vec4 a, vec4 b) {
	vec2 ab = b.xy - a.xy;
	float h = clamp(dot(p - a.xy, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0);
	float d = distance(p, a.xy + ab * h);
	// La intensidad se interpola a lo largo del tramo (la cola del túnel ya se está apagando)
	float k = mix(a.w, b.w, h);
	return (1.0 - smoothstep(a.z * 0.35, a.z, d)) * k;
}

void fragment() {
	vec2 p = UV * screen_size;
	// Pequeña ondulación del borde (niebla viva)
	vec2 wobble = vec2(noise(p * 0.02 + TIME * 0.4), noise(p * 0.02 - TIME * 0.35)) * 10.0 - 5.0;
	vec2 q = p + wobble;
	float light = 0.0;
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= light_count) break;
		light = max(light, circle_light(q, lights[i]));
	}
	for (int i = 0; i < MAX_SEGS; i++) {
		if (i >= seg_count) break;
		light = max(light, segment_light(q, seg_a[i], seg_b[i]));
	}
	COLOR = vec4(0.0, 0.0, 0.0, 1.0 - clamp(light, 0.0, 1.0));
}
