shader_type canvas_item;
// Glitch del Sabotaje Psiónico sobre toda la pantalla: separación de canales de color, franjas
// horizontales que se desplazan a saltos y líneas de barrido. `amount` 0..1.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float step_t = floor(TIME * 14.0);
	// Franjas desplazadas
	float band = floor(uv.y * 28.0);
	float jolt = hash(vec2(band, step_t));
	if (jolt > 1.0 - 0.18 * amount) {
		uv.x += (hash(vec2(step_t, band)) - 0.5) * 0.06 * amount;
	}
	float split = 0.006 * amount * (0.6 + 0.4 * sin(TIME * 23.0));
	float r = texture(screen_tex, uv + vec2(split, 0.0)).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - vec2(split, 0.0)).b;
	float scan = 1.0 - 0.12 * amount * step(0.5, fract(uv.y * 360.0));
	COLOR = vec4(vec3(r, g, b) * scan, 1.0);
}
