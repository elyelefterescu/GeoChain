shader_type sky;
// Cer de noapte: un gradient albastru-închis și stele fixe, generate din direcție (fără texturi).

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float stars(vec3 dir, float density, float size) {
	vec3 cell = floor(dir * density);
	float h = hash(cell);
	if (h < 0.985) {
		return 0.0;
	}
	vec3 center = (cell + 0.5 + 0.35 * (vec3(hash(cell + 1.7), hash(cell + 3.1), hash(cell + 5.3)) - 0.5)) / density;
	float d = length(dir - center) * density;
	return smoothstep(size, 0.0, d) * (h - 0.985) / 0.015;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 top = vec3(0.035, 0.05, 0.11);
	vec3 bottom = vec3(0.012, 0.015, 0.04);
	vec3 col = mix(bottom, top, dir.y * 0.5 + 0.5);
	float s = stars(dir, 90.0, 0.22) + 0.6 * stars(dir.zxy, 160.0, 0.25);
	col += vec3(0.85, 0.9, 1.0) * s;
	COLOR = col;
}
