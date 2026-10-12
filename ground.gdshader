shader_type canvas_item;
// Pixel-art isometric ground. The terrain type of every tile is stored in a small texture; each
// screen pixel looks up which tile it is over (after a noise warp, so coastlines and forest
// edges wobble organically instead of following the diamond grid) and picks a colour from that
// terrain's palette with ordered dithering. Everything is snapped to whole world pixels.

uniform sampler2D terrain : filter_nearest, repeat_disable;
uniform sampler2D road_mask : filter_linear, repeat_disable; // dirt roads, 8 pixels per tile
uniform vec2 map_size = vec2(80.0, 80.0);
uniform vec2 origin = vec2(0.0); // world position of this rect's top-left corner

varying vec2 world;

void vertex() {
	world = VERTEX + origin;
}

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

vec3 hx(int c) {
	return vec3(float((c >> 16) & 255), float((c >> 8) & 255), float(c & 255)) / 255.0;
}

// v in [0,1], 1 = lightest; a is the lightest colour, d the darkest.
vec3 ramp4(vec3 a, vec3 b, vec3 c, vec3 d, float v) {
	int i = 3 - int(clamp(v, 0.0, 0.999) * 4.0);
	if (i == 0) return a;
	if (i == 1) return b;
	if (i == 2) return c;
	return d;
}

vec2 to_tile(vec2 s) {
	return vec2((s.x / 16.0 + s.y / 8.0) * 0.5, (s.y / 8.0 - s.x / 16.0) * 0.5);
}

int terrain_at(vec2 g) {
	ivec2 t = ivec2(floor(g));
	if (t.x < 0 || t.y < 0 || t.x >= int(map_size.x) || t.y >= int(map_size.y)) {
		return 0; // open sea beyond the island
	}
	return int(texelFetch(terrain, t, 0).r * 255.0 + 0.5);
}

void fragment() {
	vec2 wp = floor(world);
	float bd = bayer(wp);
	vec2 warp = (vec2(vnoise(wp * 0.11), vnoise(wp * 0.11 + vec2(17.3, 5.1))) - 0.5) * 10.0;
	vec2 sp = wp + warp;
	int id = terrain_at(to_tile(sp));
	int id2 = terrain_at(to_tile(sp + vec2(5.0, 3.0)));
	if (id != id2 && bd < 0.5 && hash(wp + 3.0) < 0.6) {
		id = id2; // dithered border between two terrains
	}
	float n = fbm(wp * 0.06);
	float fine = hash(wp);
	float d = (bd - 0.5) * 0.3;
	float t = floor(TIME * 1.4);
	vec3 col;

	if (id == 0) { // deep water
		float ripple = vnoise(vec2(wp.x * 0.2 + t * 0.6, wp.y * 0.65 + t * 0.15));
		col = ramp4(hx(0x3a8fc0), hx(0x2c7db2), hx(0x206b9f), hx(0x185a88), 0.45 + (ripple - 0.5) * 0.7 + d);
		if (hash(wp * 0.77 + t) > 0.988) col = hx(0x8cc8e8);
	} else if (id == 1) { // shallows
		float ripple = vnoise(vec2(wp.x * 0.25 + t * 0.5, wp.y * 0.8 - t * 0.2));
		col = ramp4(hx(0x9ae0f0), hx(0x78cbe6), hx(0x5db7d8), hx(0x46a1c4), 0.5 + (ripple - 0.5) * 0.6 + d);
		if (hash(wp * 0.91 + t) > 0.985) col = hx(0xe8fbff);
	} else if (id == 2) { // beach
		col = ramp4(hx(0xf4e7b0), hx(0xebdc9e), hx(0xddca8a), hx(0xcdb678), 0.55 + (n - 0.5) * 0.7 + d);
		if (fine > 0.97) col = hx(0xc2ac6c);
	} else if (id == 4) { // forest floor
		col = ramp4(hx(0x86b342), hx(0x73a038), hx(0x628e31), hx(0x517c2b), 0.5 + (n - 0.5) * 0.9 + d);
		if (fine > 0.95) col = hx(0x4a6f27);
		else if (fine < 0.012) col = hx(0x9a7a44);
	} else if (id == 5) { // hill slopes: drier grass
		col = ramp4(hx(0xc4d068), hx(0xb0bd58), hx(0x9cab4c), hx(0x889842), 0.5 + (n - 0.5) * 0.9 + d);
		if (fine > 0.96) col = hx(0x7a8a3c);
	} else if (id == 6) { // rock under the mountains
		col = ramp4(hx(0xb0ab9b), hx(0x9c9786), hx(0x888372), hx(0x736f5e), 0.5 + (n - 0.5) * 0.9 + d);
	} else { // grass
		col = ramp4(hx(0xb7de5a), hx(0xa2d04c), hx(0x8ec142), hx(0x7ab039), 0.5 + (n - 0.5) * 1.0 + d);
		if (fine > 0.972) col = hx(0x629931);
		else if (fine < 0.0016) col = hx(0xfff4b4);
		else if (fine > 0.9962) col = hx(0xf4b8d0);
	}
	// Dirt roads worn by walking, over open ground only. The mask is smoothed by filtering and
	// cut with noise, so the edges are ragged and pixelly.
	if (id == 2 || id == 3) {
		vec2 gp = to_tile(wp + (vec2(vnoise(wp * 0.31), vnoise(wp * 0.31 + vec2(9.7, 3.3))) - 0.5) * 3.0);
		if (gp.x > 0.0 && gp.y > 0.0 && gp.x < map_size.x && gp.y < map_size.y) {
			float e = texture(road_mask, gp / map_size).r + (vnoise(wp * 0.45) - 0.5) * 0.4;
			if (e > 0.5) {
				col = ramp4(hx(0xdcc08a), hx(0xcdae76), hx(0xbc9d66), hx(0xa88a56), 0.55 + (fbm(wp * 0.2) - 0.5) * 0.8 + d);
				if (e < 0.6) col = hx(0x9a7c4c); // trodden edge
				else if (fine > 0.975) col = hx(0x8e7446); // pebbles
			}
		}
	}
	COLOR = vec4(col, 1.0);
}
