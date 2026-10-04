shader_type canvas_item;
uniform float tilt_x = 0.0;
uniform float tilt_y = 0.0;
uniform vec2 card_center = vec2(0.0);
// Same projection as the card primitives, with an independent foil fragment.
void vertex() {
	mat4 m = MODEL_MATRIX;
	vec2 c = (m * vec4(VERTEX, 0.0, 1.0)).xy - card_center;
	float cy = cos(tilt_y);
	float sy = sin(tilt_y);
	float cx = cos(tilt_x);
	float sx = sin(tilt_x);
	vec3 q = vec3(c.x * cy, c.y, -c.x * sy);
	vec3 r = vec3(q.x, q.y * cx - q.z * sx, q.y * sx + q.z * cx);
	float f = 520.0;
	float persp = f / (f + r.z);
	vec2 w = vec2(r.x, r.y) * persp + card_center;
	VERTEX = (inverse(m) * vec4(w, 0.0, 1.0)).xy;
}
// Continuous translucent foil over the complete card, preserving readable ink.
vec3 spectrum(float phase) {
	return 0.58 + 0.42 * cos(6.283185 * (phase + vec3(0.0, 0.33, 0.67)));
}
float grain(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
	vec4 tint = COLOR;
	vec2 p = UV * vec2(1.0, 1.35);
	float drift = TIME * 0.10;
	float rings = sin(length((p - vec2(0.50, 0.62)) * vec2(0.9, 1.0)) * 145.0 - TIME * 1.1);
	// Triangular facets reflect different hues, alongside fine foil grain.
	vec2 cell = p * 6.0;
	vec2 local = fract(cell);
	float facet = grain(floor(cell) + step(local.x, local.y) * vec2(13.0, 7.0));
	float phase = p.x * 1.7 + p.y * 0.9 + drift + facet * 0.35;
	vec3 rainbow = spectrum(phase);
	float diagonal = pow(max(0.0, cos((p.x - p.y) * 9.0 - TIME * 0.85)), 22.0);
	float sparkle = pow(grain(floor(UV * vec2(180.0, 245.0))), 28.0);
	float glint = sparkle * (0.5 + 0.5 * sin(TIME * 1.5 + facet * 6.28));
	vec3 foil = mix(rainbow, vec3(0.85, 0.98, 1.0), diagonal * 0.65);
	foil += rings * 0.06 + glint * 0.20;
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float border = 1.0 - smoothstep(0.009, 0.024, edge);
	vec2 q = abs(UV - 0.5) - vec2(0.47, 0.48);
	float rounded = 1.0 - smoothstep(0.017, 0.025, length(max(q, vec2(0.0))));
	COLOR = vec4(clamp(foil, vec3(0.0), vec3(1.0)) * tint.rgb, (0.30 + diagonal * 0.14 + border * 0.40) * rounded * tint.a);
}
