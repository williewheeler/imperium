shader_type canvas_item;
// The weather as one pixel-art overlay: cloud shadows, a dark tint, fog banks, rain and lightning.
// Everything is quantized to chunky pixels and dithered, to sit with the rest of the art.

uniform vec2 area = vec2(1280.0, 720.0); // the screen in logical pixels
uniform float darkness = 0.0;
uniform float shadow = 0.0;
uniform float rain = 0.0;
uniform float fog = 0.0;
uniform float flash = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.0) * 0.3 + vnoise(p * 4.0) * 0.2;
}

float bayer(vec2 p) {
	int x = int(mod(p.x, 2.0));
	int y = int(mod(p.y, 2.0));
	int i = x + 2 * y;
	if (i == 0) return 0.0;
	if (i == 1) return 0.5;
	if (i == 2) return 0.75;
	return 0.25;
}

// Composites `col` with opacity `a` over what is already in (pm, acc), premultiplied.
void over(inout vec3 pm, inout float acc, vec3 col, float a) {
	pm = col * a + pm * (1.0 - a);
	acc = a + acc * (1.0 - a);
}

// Rain streaks in one layer: thin slanted lines falling at different speeds.
float streaks(vec2 p, float cell, float speed, float length_px, float seed, float amount) {
	vec2 q = vec2(p.x + p.y * 0.28, p.y);  // the slant
	float col = floor(q.x);
	float band = floor(col / cell);
	float lane = floor(hash(vec2(band, seed)) * cell);  // one rain column per band
	if (mod(col, cell) != lane) return 0.0;
	if (hash(vec2(band, seed + 9.0)) > amount) return 0.0;  // lighter rain: fewer columns
	float period = 60.0 + hash(vec2(band, seed + 3.0)) * 50.0;
	float y = mod(q.y - TIME * speed + hash(vec2(band, seed + 5.0)) * period, period);
	return step(y, length_px);
}

void fragment() {
	float px = 2.0;  // chunky pixels: one art pixel on screen
	vec2 p = floor(UV * area / px);
	float t = TIME;
	float bd = bayer(p);
	vec3 pm = vec3(0.0);
	float acc = 0.0;

	// cloud shadows drifting across the ground
	if (shadow > 0.001) {
		float n = fbm(p * 0.018 + vec2(t * 0.012, t * 0.004));
		float s = smoothstep(0.42, 0.72, n) * shadow * 3.0;
		if (s > 0.25 + bd * 0.5) over(pm, acc, vec3(0.04, 0.06, 0.12), 0.26);
	}
	// the sky darkening
	if (darkness > 0.001) {
		over(pm, acc, vec3(0.05, 0.07, 0.14), darkness);
	}
	// fog: banks that roll in on the wind, thicker in some places than others
	if (fog > 0.001) {
		float bank = fbm(p * 0.0065 + vec2(-t * 0.014, t * 0.004));
		float wisp = fbm(p * 0.02 + vec2(-t * 0.03, t * 0.006));
		float d = fog * smoothstep(0.16, 0.6, bank) * (0.55 + 0.7 * wisp);
		float level = 0.0;
		if (d > 0.55 + bd * 0.15) level = 0.62;
		else if (d > 0.3 + bd * 0.15) level = 0.4;
		else if (d > 0.1 + bd * 0.12) level = 0.2;
		if (level > 0.0) over(pm, acc, vec3(0.83, 0.86, 0.85), level);
	}
	// rain
	if (rain > 0.001) {
		float far_rain = streaks(p, 4.0, 55.0, 4.0, 1.0, rain) * 0.3;
		float near_rain = streaks(p, 6.0, 95.0, 8.0, 2.0, rain) * 0.5;
		float r = max(far_rain, near_rain);
		if (r > 0.0) over(pm, acc, vec3(0.78, 0.86, 0.95), r);
	}
	// lightning
	if (flash > 0.001) {
		over(pm, acc, vec3(0.92, 0.95, 1.0), flash * 0.5);
	}
	COLOR = vec4(pm / max(acc, 0.0001), acc);
}
