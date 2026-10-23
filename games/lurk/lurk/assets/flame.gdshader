shader_type canvas_item;
render_mode blend_add;
// Llama del motor: va en un rectángulo detrás de la nave, con UV.x = 0 en la tobera y 1 en la punta.
// Ruido fractal que fluye hacia la punta; núcleo blanco que pasa al color del jugador y se desvanece.
// `power` (0..1) la enciende y alarga suavemente.

uniform vec4 tint : source_color = vec4(0.53, 0.97, 0.19, 1.0);
uniform float power = 1.0;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float x = UV.x;
	float y = (UV.y - 0.5) * 2.0;
	// El ruido avanza hacia la punta: parece que el gas sale disparado
	float n = fbm(vec2(x * 5.0 - TIME * 9.0, y * 2.2 + seed));
	float length_k = mix(0.35, 1.0, power);
	// Silueta: ancha en la tobera, se estrecha hacia la punta, con bordes rotos por el ruido
	float width = (1.0 - x / length_k) * (0.75 + 0.45 * n);
	float body = smoothstep(0.0, 0.25, width - abs(y));
	float tip = 1.0 - smoothstep(length_k * 0.55, length_k, x + n * 0.25);
	float a = body * tip * power;
	vec3 core = vec3(1.0, 0.97, 0.9);
	vec3 col = mix(core, tint.rgb, smoothstep(0.05, 0.45, x + (1.0 - n) * 0.15));
	col = mix(col, tint.rgb * 0.35, smoothstep(0.5, 1.0, x));
	COLOR = vec4(col * a, a);
}
