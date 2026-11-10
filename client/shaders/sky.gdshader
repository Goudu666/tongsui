shader_type canvas_item;
render_mode unshaded;
// 天：孔版的天不是渐变，是一层层网点——越靠近地平线青越浓；
// 白天一轮梅红的太阳，傍晚太阳落到楼后面、整片天印上柿子色，夜里靛蓝底上留出纸白的星星和月亮。
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
uniform float cell = 6.0;

const vec3 PAPER = vec3(0.957, 0.933, 0.882);
const vec3 QING = vec3(0.180, 0.545, 0.478);
const vec3 MEI = vec3(0.851, 0.282, 0.373);
const vec3 INK = vec3(0.169, 0.165, 0.200);
const vec3 NIGHT = vec3(0.17, 0.24, 0.50);
const vec3 DUSK = vec3(0.98, 0.62, 0.38);

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

float screen_dots(vec2 p, float angle, float sz, float cov) {
	float s = sin(angle);
	float c = cos(angle);
	vec2 q = mat2(vec2(c, s), vec2(-s, c)) * p / sz;
	float v = (cos(q.x * 6.2831853) + cos(q.y * 6.2831853)) * 0.25 + 0.5;
	float th = cov < 0.5 ? 0.5 * pow(2.0 * cov, 0.62) : 1.0 - 0.5 * pow(2.0 * (1.0 - cov), 0.62);
	float w = fwidth(v) * 0.75 + 0.001;
	return (1.0 - smoothstep(th - w, th + w, v)) * step(0.002, cov);
}

vec3 ink(vec3 col, vec3 c, float amount) {
	return col * mix(vec3(1.0), c, clamp(amount, 0.0, 1.0));
}

void fragment() {
	// 0 = 看得见的最上头，1 = 地平线
	float top = cam.y - view.y * 0.5;
	float t = clamp((world.y - top) / max(horizon - top, 1.0), 0.0, 1.2);
	vec3 col = PAPER;
	float day = (1.0 - night) * (1.0 - dusk * 0.6);

	// ---- 青版：地平线附近浓，往上淡 ----
	float qing_cov = (0.05 + 0.22 * t * t) * (1.0 - night * 0.5) + overcast * 0.12;
	col = ink(col, QING, screen_dots(world, 0.26, cell, qing_cov) * 0.55 + qing_cov * 0.18);

	// ---- 云：远，跟着镜头走得很慢，自己也往右飘 ----
	vec2 cp = vec2(world.x - cam.x * 0.93 + TIME * 6.0, world.y);
	float n = fbm(vec2(cp.x * 0.0021, cp.y * 0.0105));
	float band = smoothstep(top - 60.0, top + view.y * 0.25, world.y) * (1.0 - smoothstep(horizon - 120.0, horizon, world.y));
	float cloud = smoothstep(0.6 - overcast * 0.22, 0.64 - overcast * 0.22, n) * band;
	float under = smoothstep(0.6, 0.64, fbm(vec2(cp.x * 0.0021, (cp.y - 14.0) * 0.0105))) * band;
	// 云是纸白的，底下一道青网点的影子
	col = mix(col, PAPER, cloud * 0.85);
	col = ink(col, QING, (under - cloud) * 0.45 * (1.0 - night * 0.6));
	col = ink(col, INK, cloud * overcast * 0.22);

	// ---- 太阳：梅红实地一个圆，周围一圈梅网点 ----
	vec2 sun = vec2(cam.x + view.x * mix(-0.34, 0.34, day_t), mix(top + view.y * 0.12, horizon - 40.0, pow(abs(day_t - 0.5) * 2.0, 1.6)));
	sun.y = mix(sun.y, horizon - 70.0, dusk);
	float sr = 54.0 + dusk * 22.0;
	float sd = distance(world, sun);
	float sun_on = (1.0 - night) * (1.0 - overcast) * (1.0 - dawn * 0.4);
	col = ink(col, MEI, sun_on * screen_dots(world, 1.31, cell, (1.0 - smoothstep(sr, sr * 3.2, sd)) * 0.32));
	col = ink(col, MEI, sun_on * (1.0 - smoothstep(sr - 1.5, sr + 1.5, sd)) * (1.0 - cloud * 0.7));

	// ---- 晚霞 / 清早：梅版从地平线往上铺 ----
	float warm = dusk * (0.15 + 0.75 * t) + dawn * (0.05 + 0.35 * t);
	col = ink(col, MEI, screen_dots(world, 1.31, cell * 1.4, warm * 0.55) * 0.7 + warm * 0.2);
	col = ink(col, DUSK, dusk * 0.35 * t);

	// ---- 夜：靛蓝，越往上越深；星星和月亮留成纸白 ----
	if (night > 0.001) {
		float deep = night * (0.75 + 0.25 * (1.0 - t));
		vec3 nc = ink(col, NIGHT, deep * 0.85);
		nc = ink(nc, INK, night * 0.25 * (1.0 - t));
		vec2 sc = world - vec2(cam.x * 0.97, 0.0);
		vec2 g = floor(sc / 34.0);
		float h = hash(g);
		vec2 sp = (g + vec2(hash(g + 3.1), hash(g + 7.7))) * 34.0;
		float tw = 0.6 + 0.4 * sin(TIME * (1.0 + h * 2.0) + h * 40.0);
		float star = step(0.9, h) * (1.0 - smoothstep(0.6, 1.8 + h * 1.2, distance(sc, sp))) * tw * (1.0 - t * 0.8) * (1.0 - cloud);
		vec2 moon = vec2(cam.x + view.x * 0.28, top + view.y * 0.16);
		float md = distance(world, moon);
		float m = 1.0 - smoothstep(30.0, 32.0, md);
		float bite = 1.0 - smoothstep(30.0, 32.0, distance(world, moon + vec2(-14.0, -6.0)));
		float halo = (1.0 - smoothstep(32.0, 130.0, md)) * 0.25;
		nc = mix(nc, PAPER * 1.04, clamp(star * night + m * (1.0 - bite * 0.85) * night + halo * night * 0.5, 0.0, 1.0));
		col = mix(col, nc, smoothstep(0.0, 0.6, night));
	}
	COLOR = vec4(col, 1.0);
}
