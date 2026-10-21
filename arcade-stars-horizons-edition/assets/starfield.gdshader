shader_type canvas_item;
// Fondo cósmico: void + nebulosas suaves (verde / azul / rosa de la paleta) + estrellas con parpadeo.

uniform vec4 void_color : source_color = vec4(0.0118, 0.0118, 0.0549, 1.0);
uniform vec4 nebula_a : source_color = vec4(0.525, 0.969, 0.188, 1.0);
uniform vec4 nebula_b : source_color = vec4(0.651, 0.784, 1.0, 1.0);
uniform vec4 nebula_c : source_color = vec4(0.925, 0.698, 1.0, 1.0);
uniform float nebula_strength : hint_range(0.0, 1.0) = 0.34;
uniform float star_density : hint_range(0.0, 1.0) = 0.5;
uniform vec2 aspect = vec2(1.78, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
			   mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.0 + 17.0;
		a *= 0.5;
	}
	return v;
}

float stars(vec2 uv, float scale, float seed) {
	vec2 g = uv * scale;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float r = hash(id + seed);
	if (r > star_density * 0.35) return 0.0;
	vec2 off = vec2(hash(id + seed + 3.1), hash(id + seed + 7.7)) - 0.5;
	float d = length(f - off * 0.7);
	float size = mix(0.02, 0.07, hash(id + seed + 1.3));
	float tw = 0.65 + 0.35 * sin(TIME * (0.6 + 2.5 * hash(id + seed + 9.9)) + r * 40.0);
	return smoothstep(size, 0.0, d) * tw;
}

void fragment() {
	vec2 uv = UV * aspect;
	vec3 col = void_color.rgb;

	float n1 = fbm(uv * 1.3 + vec2(TIME * 0.004, 0.0));
	float n2 = fbm(uv * 1.7 + vec2(8.0, TIME * -0.003));
	float n3 = fbm(uv * 0.9 + vec2(-5.0, 3.0));
	col += nebula_b.rgb * smoothstep(0.45, 0.85, n1) * nebula_strength;
	col += nebula_c.rgb * smoothstep(0.5, 0.9, n2) * nebula_strength * 0.8;
	col += nebula_a.rgb * smoothstep(0.58, 0.95, n3) * nebula_strength * 0.35;

	float s = stars(uv, 40.0, 1.0) * 0.6 + stars(uv, 22.0, 5.0) * 0.8 + stars(uv, 10.0, 11.0) * 1.0;
	vec3 tint = mix(vec3(1.0), nebula_b.rgb, hash(floor(uv * 22.0)) * 0.6);
	col += tint * s;

	// viñeta (equivalente al bg-shadow de Clustark)
	float v = smoothstep(1.1, 0.35, length(UV - 0.5) * 1.4);
	col *= mix(0.55, 1.0, v);
	COLOR = vec4(col, 1.0);
}
