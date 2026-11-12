shader_type canvas_item;
render_mode unshaded;
// 天：微缩模型后头立着的那张手绘天幕。
//   · 渐变：天顶到地平线平滑过渡，跟着钟点换——白天晴蓝到米白，清早淡紫到杏色，傍晚蓝紫到柿子橙，夜里深蓝；
//     太阳那一侧的地平线更亮、更暖（低太阳的天光）
//   · 云：fbm 噪声画的一团团软云，边是虚的，顶上被太阳照亮、肚子底下发灰紫，横着慢慢飘、按视差走
//   · 太阳：一个柔边的圆盘 + 一大圈晕；傍晚更大更红，被云挡住时变淡
//   · 夜：零星几颗柔和的星星慢慢眨，一弯柔边的月牙带一圈淡淡的光
// 铺在一张图的整条横带上（scene_art.gd），后面没有东西了。全是平滑的，不分档、不抖动
// （只加一点肉眼看不见的噪声，免得 8 位颜色的渐变出现色带）。

uniform vec2 size = vec2(4000.0, 1200.0);   // 这条横带多大（世界像素）
uniform float horizon = 960.0;              // 地平线在横带里的 y
uniform vec2 cam = vec2(0.0);               // 镜头中心（横带坐标）
uniform vec2 view = vec2(1600.0, 900.0);    // 镜头看得见多大（世界像素）
uniform float night = 0.0;
uniform float dusk = 0.0;
uniform float dawn = 0.0;
uniform float day_t = 0.3;                  // 白天走到哪儿了（0 早上 ~ 1 傍晚），太阳从左走到右
uniform float overcast = 0.0;               // 阴天（下雨下雪）：太阳收起来，云连成片

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
	return vnoise(p) * 0.5 + vnoise(p * 2.03 + 7.1) * 0.27 + vnoise(p * 4.07 + 3.3) * 0.15 + vnoise(p * 8.13 + 1.7) * 0.08;
}

// 三段渐变：s = 0 天顶，m 处是中间色，1 地平线
vec3 grad3(vec3 zen, vec3 mid, vec3 hor, float m, float s) {
	return s < m ? mix(zen, mid, smoothstep(0.0, m, s)) : mix(mid, hor, smoothstep(m, 1.0, s));
}

// 天的颜色：s = 0 天顶 ~ 1 地平线
vec3 sky_col(float s) {
	vec3 day = grad3(vec3(0.40, 0.60, 0.86), vec3(0.62, 0.78, 0.92), vec3(0.93, 0.93, 0.88), 0.55, s);
	vec3 du = grad3(vec3(0.24, 0.24, 0.50), vec3(0.72, 0.46, 0.58), vec3(1.00, 0.70, 0.46), 0.5, s);
	vec3 da = grad3(vec3(0.50, 0.58, 0.80), vec3(0.82, 0.76, 0.86), vec3(1.00, 0.87, 0.72), 0.5, s);
	vec3 ni = mix(vec3(0.05, 0.07, 0.17), vec3(0.17, 0.21, 0.40), s * s);
	vec3 c = mix(day, du, dusk);
	c = mix(c, da, dawn * (1.0 - dusk));
	c = mix(c, ni, night);
	vec3 grey = mix(vec3(0.62, 0.66, 0.72), vec3(0.84, 0.85, 0.86), s);
	return mix(c, grey * mix(1.0, 0.35, night), overcast * 0.75);
}

void fragment() {
	// 0 = 看得见的最上头，1 = 地平线
	float top = cam.y - view.y * 0.5;
	float t = clamp((world.y - top) / max(horizon - top, 1.0), 0.0, 1.0);
	vec3 col = sky_col(t);

	// ---- 太阳在哪（和 scene_art.sun_world() 一样） ----
	vec2 sun = vec2(cam.x + view.x * mix(-0.34, 0.34, day_t), mix(top + view.y * 0.12, horizon - 40.0, pow(abs(day_t - 0.5) * 2.0, 1.6)));
	sun.y = mix(sun.y, horizon - 70.0, dusk);
	float sun_on = (1.0 - night) * (1.0 - overcast) * (1.0 - dawn * 0.4);
	vec3 sun_c = mix(vec3(1.0, 0.96, 0.84), vec3(1.0, 0.58, 0.36), dusk);
	sun_c = mix(sun_c, vec3(1.0, 0.82, 0.62), dawn * (1.0 - dusk));

	// 低太阳：太阳那一侧的地平线更亮更暖（横着按离太阳多远淡掉）
	float side = exp(-abs(world.x - sun.x) / max(view.x * 0.45, 1.0));
	float low = clamp(dusk + dawn * 0.7, 0.0, 1.0) * (1.0 - night) * (1.0 - overcast * 0.7);
	col = mix(col, col * 0.6 + sun_c * 0.5, smoothstep(0.45, 1.0, t) * side * low * 0.55);

	// ---- 云：远，跟着镜头走得很慢，自己也往右飘；横着拉长 ----
	vec2 cp = vec2((world.x - cam.x * 0.93 + TIME * 6.0) * 0.0019, world.y * 0.0085);
	float band = smoothstep(top - 60.0, top + view.y * 0.25, world.y) * (1.0 - smoothstep(horizon - 200.0, horizon - 10.0, world.y));
	float th = 0.56 - overcast * 0.22;
	float n = fbm(cp);
	float cloud = smoothstep(th, th + 0.12, n) * band;
	if (cloud > 0.001) {
		// 往太阳那边（上方）错一点再取一次：上沿被照亮，肚子底下在阴里
		float n_up = fbm(cp + vec2(0.0, -0.22));
		float lit = clamp((n - n_up) * 4.0 + 0.55, 0.0, 1.0);
		vec3 c_lit = mix(vec3(1.0, 0.99, 0.96), vec3(1.0, 0.82, 0.66), dusk);
		c_lit = mix(c_lit, vec3(1.0, 0.92, 0.86), dawn * (1.0 - dusk));
		c_lit = mix(c_lit, vec3(0.32, 0.36, 0.55), night);
		c_lit = mix(c_lit, vec3(0.82, 0.84, 0.87) * mix(1.0, 0.4, night), overcast);
		vec3 c_shade = mix(c_lit, sky_col(0.2) * 0.82, 0.48);
		c_shade = mix(c_shade, vec3(0.62, 0.46, 0.64), dusk * 0.45);
		vec3 cc = mix(c_shade, c_lit, lit);
		// 靠太阳的云边透光（银边）
		float sd0 = distance(world, sun);
		cc += sun_c * (1.0 - smoothstep(0.0, 360.0, sd0)) * (1.0 - smoothstep(0.0, 0.5, cloud)) * sun_on * 0.35;
		col = mix(col, cc, cloud * 0.92);
	}

	// ---- 太阳：柔边圆盘 + 大晕 ----
	if (sun_on > 0.001) {
		float sr = 46.0 + dusk * 24.0;
		float sd = distance(world, sun);
		float veil = 1.0 - cloud * 0.75;
		float halo = exp(-sd / (sr * 2.4)) * 0.45 + exp(-sd / (sr * 7.0)) * 0.18;
		col = mix(col, sun_c, clamp(halo * sun_on * veil, 0.0, 1.0));
		float disc = 1.0 - smoothstep(sr - 3.0, sr + 3.0, sd);
		col = mix(col, mix(sun_c, vec3(1.0, 0.97, 0.88), 0.55 - dusk * 0.2), disc * sun_on * veil);
	}

	// ---- 夜：柔和的星星慢慢眨，月牙 ----
	if (night > 0.001) {
		vec2 sc = world - vec2(cam.x * 0.97, 0.0);
		vec2 g = floor(sc / 38.0);
		float h = hash(g);
		vec2 sp = (g + vec2(0.2, 0.2) + vec2(hash(g + 3.1), hash(g + 7.7)) * 0.6) * 38.0;
		float tw = 0.65 + 0.35 * sin(TIME * (0.6 + h * 1.6) + h * 40.0);
		float rad = 0.9 + fract(h * 17.0) * 1.6;
		float star = step(0.91, h) * (1.0 - smoothstep(0.0, rad, distance(sc, sp))) * tw;
		star *= (1.0 - t * 0.75) * (1.0 - cloud);
		col = mix(col, vec3(1.0, 0.97, 0.88), clamp(star * night, 0.0, 1.0));
		vec2 moon = vec2(cam.x + view.x * 0.28, top + view.y * 0.16);
		float md = distance(world, moon);
		float m = 1.0 - smoothstep(29.0, 31.5, md);
		float bite = 1.0 - smoothstep(26.0, 29.0, distance(world, moon + vec2(-13.0, -7.0)));
		float halo = exp(-max(md - 30.0, 0.0) / 60.0) * 0.35;
		float veil = 1.0 - cloud * 0.8;
		col = mix(col, mix(col, vec3(0.46, 0.52, 0.78), 0.7), halo * night * veil);
		col = mix(col, vec3(1.0, 0.96, 0.84), m * (1.0 - bite) * night * veil);
	}

	// 防色带：比 1/255 还小的一点噪声
	col += (hash(floor(world)) - 0.5) / 255.0;
	COLOR = vec4(col, 1.0);
}
