shader_type canvas_item;
render_mode blend_add;
// Resplandor de la Sobrecarga del Reactor: luz dorada con aspecto de gas (ruido fractal que se
// arremolina) centrada en la nave, y SOMBRAS de los asteroides: si un asteroide (aproximado por su
// círculo) queda entre la nave y el punto, ese punto no recibe luz. Va en un rectángulo de 2·radio
// centrado en la nave, por encima de la niebla (es luz que se ve en la oscuridad).

const int MAX_OCCLUDERS = 24;

uniform float radius = 280.0;
uniform vec4 tint : source_color = vec4(1.0, 0.88, 0.4, 1.0);
uniform float strength = 1.0;
uniform vec3 occluders[MAX_OCCLUDERS];    // (x, y) relativo a la nave, z = radio
uniform int occluder_count = 0;

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.07 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// 0 = en sombra, 1 = iluminado (borde suave)
float visibility(vec2 p) {
	float lit = 1.0;
	float dp = length(p);
	for (int i = 0; i < MAX_OCCLUDERS; i++) {
		if (i >= occluder_count) break;
		vec2 c = occluders[i].xy;
		float r = occluders[i].z;
		float dc = length(c);
		if (dc > dp + r) continue;    // el asteroide está detrás del punto
		vec2 dir = p / max(dp, 0.001);
		float along = dot(c, dir);
		if (along < 0.0) continue;    // el asteroide está detrás de la luz
		float perp = length(c - dir * along);
		// Más allá del asteroide, la sombra se abre con la distancia (penumbra)
		float beyond = max(dp - along, 0.0);
		float soft = 6.0 + beyond * 0.06;
		lit = min(lit, smoothstep(r - soft, r + soft, perp) + (dp < dc - r ? 1.0 : 0.0));
	}
	return clamp(lit, 0.0, 1.0);
}

void fragment() {
	vec2 p = (UV - 0.5) * radius * 2.0;
	float d = length(p) / radius;
	if (d > 1.0) {
		discard;
	}
	// Gas: ruido que gira despacio alrededor de la nave
	float ang = atan(p.y, p.x);
	vec2 swirl = vec2(cos(ang + TIME * 0.35), sin(ang + TIME * 0.35)) * length(p) * 0.012;
	float gas = fbm(swirl * 3.0 + vec2(TIME * 0.25, -TIME * 0.18)) * 0.7 + fbm(p * 0.01 - TIME * 0.3) * 0.5;
	float falloff = pow(1.0 - d, 1.6);
	float core = exp(-d * 14.0);
	float light = (falloff * (0.3 + 0.7 * gas) * 0.8 + core * 0.45) * visibility(p);
	vec3 col = mix(tint.rgb, vec3(1.0, 0.98, 0.9), core);
	float a = light * strength * 0.75;
	COLOR = vec4(col * a, a);
}
