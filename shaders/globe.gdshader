shader_type spatial;
render_mode unshaded, cull_back;

// Harta colorată, harta ascunsă de identificare și culoarea fiecărui loc (după index).
uniform sampler2D color_tex : source_color, filter_linear, repeat_enable;
uniform sampler2D id_tex : filter_nearest, repeat_enable;
uniform sampler2D state_tex : filter_nearest;
uniform vec2 id_size = vec2(4096.0, 2048.0);
uniform float border_px = 1.0;
// Ceață: granițele dintre țări apar doar la locurile colorate; țărmul rămâne.
uniform bool fog = false;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

// Indexul locului și dacă e uscat (b = 1).
ivec2 place(vec2 uv) {
	vec4 c = texture(id_tex, uv);
	return ivec2(int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256, int(round(c.b)));
}

void fragment() {
	vec3 p = normalize(local_pos);
	float lat = asin(clamp(p.y, -1.0, 1.0));
	float lon = atan(p.x, p.z);
	vec2 uv = vec2(lon / TAU + 0.5, 0.5 - lat / PI);

	vec3 base = texture(color_tex, uv).rgb;
	ivec2 here = place(uv);
	vec4 state = texelFetch(state_tex, ivec2(here.x, 0), 0);
	if (here.y == 1) {
		base *= 0.9;  // uscatul neimplicat: gri deschis, nu alb orbitor
	}
	base = mix(base, state.rgb, state.a);

	// Granițe și țărm: unde un vecin are alt index și măcar unul e uscat.
	vec2 step = border_px / id_size;
	bool edge = false;
	ivec2 n[4] = ivec2[4](place(uv + vec2(step.x, 0.0)), place(uv - vec2(step.x, 0.0)),
			place(uv + vec2(0.0, step.y)), place(uv - vec2(0.0, step.y)));
	for (int i = 0; i < 4; i++) {
		if (n[i].x != here.x && (n[i].y == 1 || here.y == 1)) {
			bool coast = n[i].y != here.y;
			bool involved = state.a > 0.0 || texelFetch(state_tex, ivec2(n[i].x, 0), 0).a > 0.0;
			if (!fog || coast || involved) {
				edge = true;
			}
		}
	}
	if (edge) {
		base = mix(base, vec3(0.12, 0.1, 0.08), 0.8);
	}

	// Lumină moale din stânga-sus, margine ușor întunecată și o strălucire pe ocean.
	vec3 light_dir = normalize(vec3(-0.35, 0.4, 1.0));
	float ndl = max(dot(NORMAL, light_dir), 0.0);
	float light = 0.55 + 0.45 * ndl;
	float limb = mix(0.75, 1.0, smoothstep(0.0, 0.5, dot(NORMAL, VIEW)));
	vec3 col = base * light * limb;
	if (here.y == 0 && state.a == 0.0) {
		float spec = pow(max(dot(reflect(-light_dir, NORMAL), VIEW), 0.0), 40.0);
		col += vec3(0.55, 0.7, 0.9) * spec * 0.35;
	}
	// Pe margine, un pic de albastru de atmosferă.
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	col = mix(col, vec3(0.45, 0.65, 1.0), pow(rim, 3.0) * 0.45);
	ALBEDO = col;
}
