shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
// Un halou albastru în jurul globului: mai intens pe margine.

uniform vec3 glow_color : source_color = vec3(0.35, 0.6, 1.0);
uniform float strength = 0.6;

void fragment() {
	// Pe sfera haloului, marginea globului e la d ≈ 0.35: acolo e cel mai intens,
	// spre exterior se stinge lin (fără margine tăiată), spre interior dispare repede.
	float d = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = 0.355;
	float outer = pow(smoothstep(0.0, edge, d), 2.5);
	float inner = 1.0 - smoothstep(edge, edge + 0.25, d);
	float a = outer * inner * strength;
	ALBEDO = glow_color * a;
}
