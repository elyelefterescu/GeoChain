shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
// Un halou albastru în jurul globului: mai intens pe margine.

uniform vec3 glow_color : source_color = vec3(0.35, 0.6, 1.0);
uniform float strength = 1.1;

void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float a = pow(rim, 2.6) * strength;
	ALBEDO = glow_color * a;
}
