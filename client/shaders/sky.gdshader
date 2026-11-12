shader_type canvas_item;
render_mode unshaded;
// 天：像素画的天。每 3 个世界像素一个点（和底图同一张格子），天顶到地平线分成一条条色带，
// 带和带之间用 4×4 拜耳抖动过渡；白天青蓝、傍晚紫到柿子橙、夜里靛蓝。
// 云是一团团平涂的点：顶上亮一档、肚子底下暗一档；太阳是个圆点，外面两圈抖动的光晕；
// 夜里星星一个点一个点地眨，月牙边是硬的。
// 铺在一张图的整条横带上（scene_art.gd），后面没有东西了。云按视差慢慢走。

uniform vec2 size = vec2(4000.0, 1200.0);   // 这条横带多大（世界像素）
uniform float horizon = 960.0;              // 地平线在横带里的 y
uniform vec2 cam = vec2(0.0);               // 镜头中心（横带坐标）
uniform vec2 view = vec2(1600.0, 900.0);    // 镜头看得见多大（世界像素）
uniform float night = 0.0;
uniform float dusk = 0.0;
uniform float dawn = 0.0;
uniform float day_t = 0.3;                  // 白天走到哪儿了（0 早上 ~ 1 傍晚），太阳从左走到右
uniform float overcast = 0.0;               // 阴天（下雨下雪）：太阳收起来，云连成片
uniform float cell = 3.0;                   // 一个点多大（世界像素）
uniform float x0 = -200.0;                  // 横带左边在这张图里的 x（格子和底图对齐）

const float BANDS = 11.0;

varying vec2 world;

void vertex() {
	world = UV * size;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.1 + 3.3) * 0.15;
}

// 4×4 拜耳阈值（0~1）
float bayer(vec2 q) {
	int x = int(mod(q.x, 4.0));
	int y = int(mod(q.y, 4.0));
	int i = y * 4 + x;
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

// 抖动：v 在 0~1，落在 n 档里的哪一档（按点的拜耳阈值往上或往下取）
float dstep(float v, float n, float b) {
	float t = v * n;
	return (floor(t) + step(b, fract(t))) / n;
}

// 天的颜色：s = 0 天顶 ~ 1 地平线
vec3 sky_col(float s) {
	vec3 dz = vec3(0.38, 0.58, 0.84);
	vec3 dm = vec3(0.58, 0.76, 0.90);
	vec3 dh = vec3(0.90, 0.92, 0.86);
	vec3 day = s < 0.6 ? mix(dz, dm, s / 0.6) : mix(dm, dh, (s - 0.6) / 0.4);
	vec3 uz = vec3(0.22, 0.20, 0.46);
	vec3 um = vec3(0.70, 0.40, 0.56);
	vec3 uh = vec3(1.00, 0.68, 0.42);
	vec3 du = s < 0.55 ? mix(uz, um, s / 0.55) : mix(um, uh, (s - 0.55) / 0.45);
	vec3 az = vec3(0.46, 0.56, 0.78);
	vec3 am = vec3(0.80, 0.74, 0.84);
	vec3 ah = vec3(1.00, 0.86, 0.68);
	vec3 da = s < 0.55 ? mix(az, am, s / 0.55) : mix(am, ah, (s - 0.55) / 0.45);
	vec3 nz = vec3(0.05, 0.06, 0.16);
	vec3 nh = vec3(0.16, 0.20, 0.40);
	vec3 ni = mix(nz, nh, s * s);
	vec3 c = mix(day, du, dusk);
	c = mix(c, da, dawn * (1.0 - dusk));
	c = mix(c, ni, night);
	vec3 grey = mix(vec3(0.62, 0.66, 0.72), vec3(0.82, 0.83, 0.84), s);
	return mix(c, grey * mix(1.0, 0.35, night), overcast * 0.75);
}

void fragment() {
	vec2 q = floor(vec2(world.x + x0, world.y) / cell);   // 这个点在格子里的编号
	vec2 w = (q + 0.5) * cell - vec2(x0, 0.0);             // 点的中心（横带坐标）
	float b = bayer(q);
	float top = cam.y - view.y * 0.5;
	float t = clamp((w.y - top) / max(horizon - top, 1.0), 0.0, 1.0);

	// ---- 色带 + 抖动 ----
	vec3 col = sky_col(dstep(t, BANDS, b));

	// ---- 云：横着拉长的一团团，按视差慢慢走 ----
	float px = w.x - cam.x * 0.93 + TIME * 6.0;
	vec2 cp = vec2(floor(px / cell) * cell, w.y);
	float band = smoothstep(top - 60.0, top + view.y * 0.22, w.y) * (1.0 - smoothstep(horizon - 160.0, horizon - 20.0, w.y));
	float th = 0.6 - overcast * 0.24;
	float n = fbm(vec2(cp.x * 0.0021, cp.y * 0.0105));
	float n_up = fbm(vec2(cp.x * 0.0021, (cp.y - cell * 2.0) * 0.0105));
	float n_dn = fbm(vec2(cp.x * 0.0021, (cp.y + cell * 2.0) * 0.0105));
	float cloud = step(th, n) * step(0.5, band);
	if (cloud > 0.5) {
		vec3 lit = mix(vec3(1.0, 0.98, 0.94), vec3(1.0, 0.80, 0.62), dusk);
		lit = mix(lit, vec3(1.0, 0.90, 0.82), dawn * (1.0 - dusk));
		lit = mix(lit, vec3(0.30, 0.34, 0.52), night);
		lit = mix(lit, vec3(0.80, 0.82, 0.85) * mix(1.0, 0.4, night), overcast);
		vec3 shade = mix(lit, sky_col(0.25) * 0.8, 0.45);
		shade = mix(shade, vec3(0.62, 0.42, 0.62), dusk * 0.5);
		vec3 c = lit;
		// 顶上那条边亮一档，肚子底下暗一档（中间一档抖动）
		if (n_dn < th) {
			c = shade;
		} else if (n - th < 0.025) {
			c = b < 0.5 ? shade : lit;
		}
		if (n_up < th) {
			c = mix(lit, vec3(1.0), 0.35 * (1.0 - night));
		}
		col = c;
	}

	// ---- 太阳：圆点 + 两圈抖动的光晕 ----
	vec2 sun = vec2(cam.x + view.x * mix(-0.34, 0.34, day_t), mix(top + view.y * 0.12, horizon - 40.0, pow(abs(day_t - 0.5) * 2.0, 1.6)));
	sun.y = mix(sun.y, horizon - 70.0, dusk);
	float sr = 36.0 + dusk * 18.0;
	float sd = distance(w, sun);
	float sun_on = (1.0 - night) * (1.0 - overcast) * (1.0 - dawn * 0.4);
	vec3 sun_c = mix(vec3(1.0, 0.97, 0.82), vec3(1.0, 0.56, 0.36), dusk);
	if (sun_on > 0.01 && cloud < 0.5) {
		float h1 = 1.0 - smoothstep(sr, sr * 2.2, sd);
		float h2 = 1.0 - smoothstep(sr * 2.2, sr * 4.0, sd);
		col = mix(col, mix(col, sun_c, 0.5), step(b, h2 * 0.5 * sun_on));
		col = mix(col, mix(col, sun_c, 0.75), step(b, h1 * sun_on));
		col = mix(col, sun_c, step(sd, sr) * sun_on);
	}

	// ---- 夜：星星一个点一个点地眨，月牙 ----
	if (night > 0.001) {
		vec2 sq = floor((w - vec2(cam.x * 0.97, 0.0)) / cell);
		float h = hash(sq);
		float tw = step(0.35, sin(TIME * (0.8 + fract(h * 13.0) * 2.0) + h * 40.0));
		float star = step(0.9965, h) * (1.0 - t * 0.7) * mix(0.55, 1.0, tw) * (1.0 - cloud);
		// 亮的几颗打个十字
		float big = 0.0;
		for (int i = 0; i < 4; i++) {
			vec2 o = vec2(i == 0 ? 1.0 : (i == 1 ? -1.0 : 0.0), i == 2 ? 1.0 : (i == 3 ? -1.0 : 0.0));
			float hh = hash(sq + o);
			big = max(big, step(0.9995, hh) * tw);
		}
		star = max(star, big * (1.0 - cloud) * 0.8);
		vec3 sc = vec3(1.0, 0.96, 0.84);
		col = mix(col, sc, clamp(star * night, 0.0, 1.0));
		vec2 moon = vec2(cam.x + view.x * 0.28, top + view.y * 0.16);
		float md = distance(w, moon);
		float m = step(md, 30.0) * (1.0 - step(distance(w, moon + vec2(-13.0, -7.0)), 27.0));
		float halo = 1.0 - smoothstep(32.0, 120.0, md);
		col = mix(col, mix(col, vec3(0.42, 0.48, 0.72), 0.6), step(b, halo * 0.5 * night) * (1.0 - cloud));
		col = mix(col, vec3(1.0, 0.95, 0.80), m * night);
	}
	COLOR = vec4(col, 1.0);
}
