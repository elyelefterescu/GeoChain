shader_type spatial;
render_mode unshaded, cull_back;

// Harta colorată, harta ascunsă de identificare și culoarea fiecărui loc (după index).
uniform sampler2D color_tex : source_color, filter_linear, repeat_enable;
uniform sampler2D id_tex : filter_nearest, repeat_enable;
uniform sampler2D state_tex : filter_nearest;
uniform vec2 id_size = vec2(4096.0, 2048.0);
uniform float border_px = 1.0;
// Harta unei regiuni (SUA), mai detaliată, peste globul lumii. bounds: lon_min, lat_min, lon_max, lat_max.
uniform bool use_region = false;
uniform sampler2D region_color_tex : source_color, filter_linear;
uniform sampler2D region_id_tex : filter_nearest;
uniform vec4 region_bounds = vec4(-180.0, -90.0, 180.0, 90.0);
uniform vec2 region_size = vec2(1.0, 1.0);
// Locurile lumii primesc indexul + WORLD când harta e o regiune (nu au stare, nu sunt în joc).
const int WORLD = 10000;
// Ceață: granițele dintre țări apar doar la locurile colorate; țărmul rămâne.
uniform bool fog = false;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

// Indexul locului și dacă e uscat (b = 1).
ivec2 decode(vec4 c) {
	return ivec2(int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256, int(round(c.b)));
}

vec2 world_uv(vec2 ll) {
	return vec2(ll.x / 360.0 + 0.5, 0.5 - ll.y / 180.0);
}

// Poziția în harta regiunii (în afara [0, 1] = nu e în regiune).
vec2 region_uv(vec2 ll) {
	return vec2((ll.x - region_bounds.x) / (region_bounds.z - region_bounds.x),
		(region_bounds.w - ll.y) / (region_bounds.w - region_bounds.y));
}

bool in_region(vec2 r) {
	return r.x >= 0.0 && r.x <= 1.0 && r.y >= 0.0 && r.y <= 1.0;
}

// ll = (longitudine, latitudine) în grade.
ivec2 place(vec2 ll) {
	if (use_region) {
		vec2 r = region_uv(ll);
		if (in_region(r)) {
			ivec2 p = decode(texture(region_id_tex, r));
			if (p.x != 0) {
				return p;
			}
		}
		ivec2 w = decode(texture(id_tex, world_uv(ll)));
		return ivec2(w.x + WORLD, w.y);
	}
	return decode(texture(id_tex, world_uv(ll)));
}

vec4 state_of(int index) {
	return index < WORLD ? texelFetch(state_tex, ivec2(index, 0), 0) : vec4(0.0);
}

void fragment() {
	vec3 p = normalize(local_pos);
	float lat = asin(clamp(p.y, -1.0, 1.0));
	float lon = atan(p.x, p.z);
	vec2 ll = vec2(degrees(lon), degrees(lat));

	ivec2 here = place(ll);
	vec3 base;
	if (use_region && here.x < WORLD) {
		base = texture(region_color_tex, region_uv(ll)).rgb;
	} else {
		base = texture(color_tex, world_uv(ll)).rgb;
	}
	vec4 state = state_of(here.x);
	if (here.y == 1) {
		base *= 0.9;  // uscatul neimplicat: gri deschis, nu alb orbitor
		if (here.x >= WORLD) {
			base *= 0.62;  // pe harta unei regiuni, restul lumii nu e în joc
		}
	}
	base = mix(base, state.rgb, state.a);

	// Granițe și țărm: unde un vecin are alt index și măcar unul e uscat.
	vec2 step = use_region ? border_px * (region_bounds.zw - region_bounds.xy) / region_size
		: border_px * vec2(360.0, 180.0) / id_size;
	// Pe harta detaliată a unei regiuni, granița are cel puțin un pixel pe ecran,
	// altfel apare întreruptă când globul e departe. (Doar din latitudine: longitudinea
	// sare de la 180 la -180 și ar desena o linie falsă.)
	if (use_region) {
		float screen = fwidth(ll.y) * 0.9;
		step = max(step, vec2(screen / max(cos(lat), 0.05), screen));
	}
	bool edge = false;
	ivec2 n[4] = ivec2[4](place(ll + vec2(step.x, 0.0)), place(ll - vec2(step.x, 0.0)),
			place(ll + vec2(0.0, step.y)), place(ll - vec2(0.0, step.y)));
	for (int i = 0; i < 4; i++) {
		if (n[i].x != here.x && (n[i].y == 1 || here.y == 1)) {
			bool coast = n[i].y != here.y;
			bool involved = state.a > 0.0 || state_of(n[i].x).a > 0.0;
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
