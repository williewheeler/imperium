shader_type canvas_item;
#include "res://shaders/terrace.gdshaderinc"
// Pixel-art isometric ground. The terrain type of every tile is stored in a small texture; each
// screen pixel looks up which tile it is over (after a noise warp, so coastlines and forest
// edges wobble organically instead of following the diamond grid) and picks a colour from that
// terrain's palette with ordered dithering. Everything is snapped to whole world pixels.

uniform sampler2D terrain : filter_nearest, repeat_disable;
uniform sampler2D road_mask : filter_linear, repeat_disable; // dirt roads, 8 pixels per tile
uniform sampler2D paved_mask : filter_linear, repeat_disable; // paved Roman roads
uniform float flow = 0.0; // how far the water has drifted: the CPU adds up the time, faster in rough weather, so a change of weather never makes it jump
uniform float rain = 0.0; // 0 dry .. 1 storm: rain ripples the water and a storm roughens it
uniform sampler2D relief : filter_linear, repeat_disable; // light on each tile's slope, 0.5 = flat
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

// Raindrops landing on water: a little splash, then a ring spreading out (squashed, as the water
// is seen at a slant), fading as it grows. Returns how much to lighten the water at this pixel.
float raindrop(vec2 wp, float amount, float time) {
	if (amount < 0.01) return 0.0;
	float cell = 18.0;
	vec2 c = floor(wp / cell);
	float lit = 0.0;
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) { // a ring can spill over into the next cell
			vec2 k = c + vec2(float(ox), float(oy));
			if (hash(k + 11.0) > amount * 0.7) continue; // heavier rain: more drops
			float period = 1.1 + hash(k + 3.0) * 1.2;
			float age = fract(time / period + hash(k + 7.0));
			vec2 centre = (k + vec2(0.2 + 0.6 * hash(k + 1.0), 0.2 + 0.6 * hash(k + 2.0))) * cell;
			vec2 d = (wp - centre) * vec2(1.0, 2.0);
			float dist = length(d);
			float radius = age * 11.0;
			if (age < 0.12 && dist < 1.6) lit = max(lit, 1.0); // the splash
			else if (abs(dist - radius) < 0.9 && age < 0.9) lit = max(lit, 1.0 - age * 0.7);
		}
	}
	return lit;
}

// A cliff face between two terraces: earth with strata, a grassy lip on top and a shaded foot.
vec3 cliff_colour(vec2 wp, int kind, int top_id, float v) {
	float bd = bayer(wp);
	float strata = vnoise(vec2(wp.x * 0.35, floor(wp.y / 2.0) * 1.7)) - 0.5;
	bool rocky = top_id == 5 || top_id == 6;
	float base = kind == 1 ? 0.62 : 0.3; // walls facing the light are lit, the others shaded
	float t = base + strata * 0.35 + (bd - 0.5) * 0.2 - v * 0.18;
	vec3 col;
	if (rocky) {
		col = ramp4(hx(0xc4bfae), hx(0xa29d8c), hx(0x84806f), hx(0x66624f), t);
	} else {
		col = ramp4(hx(0xcba66b), hx(0xb28c58), hx(0x987344), hx(0x7a5a33), t);
		if (v < 0.5 && hash(wp + 5.0) < 1.15 - v) { // grass hanging over the lip
			col = kind == 1 ? hx(0x8ec142) : hx(0x628e31);
		}
	}
	if (v > 0.9) col = col * 0.82; // the dark foot of the wall
	return col;
}

vec3 ground_colour(vec2 wp, vec2 g, float time, bool below_wall, int lvl) {
	float bd = bayer(wp);
	vec2 warp = (vec2(vnoise(wp * 0.11), vnoise(wp * 0.11 + vec2(17.3, 5.1))) - 0.5) * 10.0;
	vec2 gw = g + to_tile(warp); // the tile this pixel is "in", after the coastline wobble
	int id = terrain_at(gw);
	int id2 = terrain_at(gw + to_tile(vec2(5.0, 3.0)));
	if (id != id2 && bd < 0.5 && hash(wp + 3.0) < 0.6) {
		id = id2; // dithered border between two terrains
	}
	float n = fbm(wp * 0.06);
	float fine = hash(wp);
	float d = (bd - 0.5) * 0.3;
	if (id >= 2) { // the land is lit from the top-left: slopes that face the light brighten, the others darken
		d += (texture(relief, gw / map_size).r - 0.5) * 1.4;
	}
	d += float(lvl) * 0.1; // higher terraces are a touch lighter, so the steps read
	if (below_wall) d -= 0.4; // the foot of a cliff sits in shadow
	float t = floor(time * 1.4);
	vec3 col;

	if (id == 0) { // deep water
		float ripple = vnoise(vec2(wp.x * 0.2 + flow * 0.6, wp.y * 0.65 + flow * 0.15));
		col = ramp4(hx(0x3a8fc0), hx(0x2c7db2), hx(0x206b9f), hx(0x185a88), 0.45 + (ripple - 0.5) * (0.7 + rain * 0.5) + d - rain * 0.12);
		if (hash(wp * 0.77 + t) > 0.988 - rain * 0.022) col = hx(0x8cc8e8); // whitecaps multiply in a storm
		col = mix(col, hx(0xd2ebf7), raindrop(wp, rain, floor(time * 8.0) / 8.0) * 0.85);
	} else if (id == 1) { // shallows
		float ripple = vnoise(vec2(wp.x * 0.25 + flow * 0.5, wp.y * 0.8 - flow * 0.2));
		col = ramp4(hx(0x9ae0f0), hx(0x78cbe6), hx(0x5db7d8), hx(0x46a1c4), 0.5 + (ripple - 0.5) * (0.6 + rain * 0.5) + d - rain * 0.1);
		if (hash(wp * 0.91 + t) > 0.985 - rain * 0.015) col = hx(0xe8fbff);
		col = mix(col, hx(0xf2fbff), raindrop(wp, rain, floor(time * 8.0) / 8.0) * 0.85);
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
	} else if (id == 7) { // marsh: waterlogged ground with pools of standing water and tufts of reed
		float pools = fbm(wp * 0.085 + vec2(5.0, 2.0));
		col = ramp4(hx(0x86a058), hx(0x728c4a), hx(0x5e783c), hx(0x4a6230), 0.5 + (n - 0.5) * 0.8 + d);
		if (pools > 0.56) {
			float ripple = vnoise(vec2(wp.x * 0.3 + t * 0.4, wp.y * 0.9));
			col = ramp4(hx(0x8fbcb2), hx(0x74a7a0), hx(0x5d9190), hx(0x4a7d7e), 0.45 + (ripple - 0.5) * 0.6 + d);
			if (hash(wp * 0.83 + t) > 0.99) col = hx(0xd6efe8);
			col = mix(col, hx(0xe4f4ef), raindrop(wp, rain, floor(time * 8.0) / 8.0) * 0.8);
		} else if (pools > 0.5) {
			col = hx(0x5a6a38); // the muddy rim
		} else if (fine > 0.955) {
			col = hx(0x41562a);
		}
	} else { // grass
		col = ramp4(hx(0xb7de5a), hx(0xa2d04c), hx(0x8ec142), hx(0x7ab039), 0.5 + (n - 0.5) * 1.0 + d);
		if (fine > 0.972) col = hx(0x629931);
		else if (fine < 0.0016) col = hx(0xfff4b4);
		else if (fine > 0.9962) col = hx(0xf4b8d0);
	}
	// Dirt roads worn by walking, over open ground only. The mask is smoothed by filtering and
	// cut with noise, so the edges are ragged and pixelly.
	if (id == 2 || id == 3) {
		vec2 gp = g + to_tile((vec2(vnoise(wp * 0.31), vnoise(wp * 0.31 + vec2(9.7, 3.3))) - 0.5) * 3.0);
		if (gp.x > 0.0 && gp.y > 0.0 && gp.x < map_size.x && gp.y < map_size.y) {
			float e = texture(road_mask, gp / map_size).r + (vnoise(wp * 0.45) - 0.5) * 0.4;
			if (e > 0.5) {
				col = ramp4(hx(0xdcc08a), hx(0xcdae76), hx(0xbc9d66), hx(0xa88a56), 0.55 + (fbm(wp * 0.2) - 0.5) * 0.8 + d);
				if (e < 0.6) col = hx(0x9a7c4c); // trodden edge
				else if (fine > 0.975) col = hx(0x8e7446); // pebbles
			}
		}
	}
	// Paved Roman roads: dark polygonal basalt blocks laid in the iso grid, with lighter curb stones.
	if (id == 2 || id == 3) {
		vec2 gt = g;
		if (gt.x > 0.0 && gt.y > 0.0 && gt.x < map_size.x && gt.y < map_size.y) {
			float pe = texture(paved_mask, gt / map_size).r + (vnoise(wp * 0.45) - 0.5) * 0.15;
			if (pe > 0.5) {
				vec2 q = gt * 6.0;
				vec2 cell = floor(q);
				vec2 f = fract(q);
				float tone = hash(cell + 17.0);
				col = ramp4(hx(0x9a9aa0), hx(0x82828a), hx(0x6c6c74), hx(0x585860), 0.25 + tone * 0.6 + d * 0.5);
				if (f.x < 0.14 || f.y < 0.14) col = hx(0x3e3e46); // gaps between the blocks
				else if (f.x < 0.3 || f.y < 0.3) col = col * 1.12; // lit edges (light from the top-left)
				if (pe < 0.62) col = ramp4(hx(0xd2cdbe), hx(0xc2bdac), hx(0xa8a392), hx(0x908b7a), 0.5 + tone * 0.4); // curb stones
			}
		}
	}
	return col;
}

void fragment() {
	vec2 wp = floor(world);
	int cliff;
	float wall_v;
	vec2 g = surface(wp, cliff, wall_v);
	if (cliff > 0) {
		COLOR = vec4(cliff_colour(wp, cliff, terrain_at(g), wall_v), 1.0);
	} else {
		int c2;
		float v2;
		surface(wp - vec2(0.0, 3.0), c2, v2);
		COLOR = vec4(ground_colour(wp, g, TIME, c2 > 0, level_at(g)), 1.0);
	}
}
