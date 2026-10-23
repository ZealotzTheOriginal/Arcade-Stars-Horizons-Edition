shader_type canvas_item;
// Fondo del espacio: negro con una bruma muy tenue y tres capas de estrellas en paralaje (dan
// sensación de velocidad al moverse). Va a pantalla completa detrás del mundo; la niebla tapa lo que
// la nave no ve, así que la bruma deja intuir hasta dónde llega la visión.

uniform vec2 screen_size = vec2(1280.0, 720.0);
uniform vec2 cam_pos = vec2(0.0);    // posición de la cámara en el mundo
uniform float zoom = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float stars(vec2 p, float cell, float density, float size) {
	vec2 g = p / cell;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float h = hash(id);
	if (h > density) {
		return 0.0;
	}
	vec2 c = vec2(hash(id + 3.1), hash(id + 7.7));
	float d = length((f - c) * cell);
	float tw = 0.6 + 0.4 * sin(TIME * (0.5 + h * 3.0) + h * 50.0);
	return (1.0 - smoothstep(0.0, size, d)) * tw;
}

void fragment() {
	vec2 p = (UV - 0.5) * screen_size / zoom;
	float s = stars(p + cam_pos * 0.15, 90.0, 0.35, 1.1) * 0.35;
	s += stars(p + cam_pos * 0.35, 140.0, 0.30, 1.4) * 0.5;
	s += stars(p + cam_pos * 0.6, 220.0, 0.22, 1.8) * 0.7;
	vec2 w = (p + cam_pos * 0.9) * 0.0018;
	float haze = noise(w) * 0.6 + noise(w * 2.3 + 7.0) * 0.4;
	vec3 col = vec3(0.035, 0.04, 0.09) * (0.55 + haze * 0.9);
	COLOR = vec4(col + vec3(0.75, 0.82, 1.0) * s, 1.0);
}
