shader_type canvas_item;
render_mode unshaded;
// 光与空气（world/atmos.gd）：整张画印好以后，最后在镜头前面罩的一层。
// 孔版的四块版负责「印什么」，这一层只管「那天的光和空气是什么样」：
//   · 分色调：暗部偏冷（白天青灰、夜里靛蓝），亮部偏暖（白天米黄、傍晚柿子、清早杏色）
//   · 光柱：太阳那边斜着打下来几道光，光里飘着细尘；阴天、夜里收起来
//   · 地气：清早和雨天贴着地面浮一层薄雾，慢慢往一边挪
//   · 压角：四边轻轻压暗，把眼睛收到人身上
//   · 下雨：马路上倒着映出街上的灯和招牌
// 灯的晕在 lamp_glow.gdshader（夜版那一层，按烘好的灯光图加），这里不做全屏泛光：
// 屏幕贴图要 mipmap 的话每帧多生成一回，手机上太贵。屏幕只读一次（下雨的马路多三次）。

uniform sampler2D scr : hint_screen_texture, filter_linear;
uniform float night = 0.0;
uniform float dusk = 0.0;
uniform float dawn = 0.0;
uniform float overcast = 0.0;
uniform float indoor = 0.0;       // 剖面图（楼里、出租屋、医院）：没有光柱和地气
uniform vec2 sun = vec2(0.7, 0.15);  // 太阳在屏幕上的位置（0~1，可以在屏幕外）
uniform float ground = 0.78;      // 地面线在屏幕上的 y（0~1）
uniform float horizon = 0.5;      // 远景楼脚（地平线）在屏幕上的 y
uniform vec2 cam = vec2(0.0);     // 镜头的世界坐标（光柱里的尘、雾跟着世界走，不跟屏幕）
uniform float view_h = 1200.0;  // 镜头竖着看得见多少世界像素
uniform float strength = 1.0;
uniform float wet = 0.0;
uniform vec2 focus = vec2(0.5, 0.7);  // 我在屏幕上的位置：压角以人为中心，人永远在最亮的那一圈里          // 下雨：地面湿了，倒着映出街上的灯和招牌     // 整层的总量（设置里关掉时 0）

const vec3 COOL_DAY = vec3(0.86, 0.93, 0.98);
const vec3 WARM_DAY = vec3(1.04, 1.00, 0.92);
const vec3 COOL_NIGHT = vec3(0.70, 0.78, 1.02);
const vec3 WARM_LAMP = vec3(1.10, 0.96, 0.78);
const vec3 WARM_DUSK = vec3(1.12, 0.92, 0.78);
const vec3 COOL_DUSK = vec3(0.86, 0.80, 0.96);
const vec3 WARM_DAWN = vec3(1.07, 0.98, 0.88);
const vec3 COOL_DAWN = vec3(0.88, 0.92, 1.00);

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

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 screen_blend(vec3 a, vec3 b) {
	return 1.0 - (1.0 - a) * (1.0 - b);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 base = texture(scr, uv).rgb;
	// ---- 湿地面的倒影：地面线往下，按地面线翻过来取，越远越虚越淡，再被雨丝打碎 ----
	if (wet > 0.01 && indoor < 0.5 && uv.y > ground) {
		float dy = uv.y - ground;
		float ripple = sin(uv.y * 900.0 + TIME * 3.0) * 0.0015 + sin(uv.x * 60.0 + uv.y * 400.0) * 0.001;
		vec2 ruv = vec2(uv.x + ripple, ground - dy * 1.15);
		// 越远越虚：横着错开取三下（不用 mip，手机上省一次生成 mipmap）
		float bx = (1.5 + dy * 60.0) * SCREEN_PIXEL_SIZE.x;
		vec3 refl = (texture(scr, ruv).rgb * 2.0 + texture(scr, ruv + vec2(bx, 0.0)).rgb + texture(scr, ruv - vec2(bx, 0.0)).rgb) * 0.25;
		float f = wet * (0.30 + 0.25 * night) * (1.0 - smoothstep(0.0, 0.2, dy)) * step(0.0, ruv.y);
		// 倒影只让暗的路面亮起来、亮的路面暗下去一点：像一层水膜
		base = mix(base, refl * 0.9 + base * 0.1, f);
	}
	vec3 col = base;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;  // 宽 / 高
	float day = (1.0 - night) * (1.0 - dusk * 0.5);
	float k = strength;

	// ---- 分色调 ----
	float l = luma(col);
	vec3 cool = COOL_DAY;
	vec3 warm = WARM_DAY;
	cool = mix(cool, COOL_DAWN, dawn);
	warm = mix(warm, WARM_DAWN, dawn);
	cool = mix(cool, COOL_DUSK, dusk);
	warm = mix(warm, WARM_DUSK, dusk);
	cool = mix(cool, COOL_NIGHT, night);
	warm = mix(warm, WARM_LAMP, night);
	// 阴天：整体灰一点、冷一点
	cool = mix(cool, vec3(0.88, 0.92, 0.95), overcast * 0.6);
	warm = mix(warm, vec3(0.98, 0.99, 1.00), overcast * 0.7);
	float sh = 1.0 - smoothstep(0.08, 0.62, l);
	float hi = smoothstep(0.42, 0.95, l);
	vec3 graded = col * mix(vec3(1.0), cool, sh * mix(0.85, 0.5, night)) * mix(vec3(1.0), warm, hi);
	// 饱和度：白天提一点，阴天、夜里收一点
	float sat = 1.0 + 0.10 * day - 0.18 * overcast - 0.06 * night;
	graded = mix(vec3(luma(graded)), graded, sat);
	// 轻轻一道 S 曲线：纸白更透、墨更沉
	graded = mix(graded, graded * graded * (3.0 - 2.0 * graded), 0.22);
	col = mix(col, graded, k);

	// ---- 对面的楼投过来的影子：太阳低（清早、傍晚）时街这边的下半截在阴里，楼顶还亮着 ----
	// 影子上沿是一排高高低低的楼的剪影（按世界 x 分块），边是软的
	float outdoor = 1.0 - indoor;
	float low_sun = clamp(dawn * 0.9 + dusk + (1.0 - night) * 0.08, 0.0, 1.0) * (1.0 - overcast * 0.6);
	if (low_sun > 0.01 && outdoor > 0.0) {
		float wx = cam.x + (uv.x - 0.5) * aspect * view_h;
		float bx = floor(wx / 170.0);
		float hb = hash(vec2(bx, 3.0)) * 0.55 + hash(vec2(floor(wx / 520.0), 9.0)) * 0.45;
		float hn = hash(vec2(bx + 1.0, 3.0)) * 0.55 + hash(vec2(floor((wx + 170.0) / 520.0), 9.0)) * 0.45;
		float hs = mix(hb, hn, smoothstep(0.82, 1.0, fract(wx / 170.0)));
		// 影子有多高（世界像素，从地面往上）
		float sh_h = (60.0 + hs * 260.0) * low_sun + 30.0;
		float wy = cam.y + (uv.y - 0.5) * view_h;
		float gy = cam.y + (ground - 0.5) * view_h;
		float edge = 1.0 - smoothstep(gy - sh_h - 14.0, gy - sh_h + 14.0, wy);
		float shade = 1.0 - edge;
		vec3 shade_col = mix(vec3(0.74, 0.80, 0.96), vec3(0.56, 0.60, 0.92), dusk);
		col *= mix(vec3(1.0), shade_col, shade * low_sun * 0.5 * k * (1.0 - night * 0.8));
		// 没进影子的那截被斜阳照着：再暖一点
		vec3 lit_col = mix(vec3(1.06, 1.0, 0.92), vec3(1.10, 0.95, 0.82), dusk);
		col *= mix(vec3(1.0), lit_col, edge * smoothstep(horizon - 0.1, horizon + 0.1, uv.y) * low_sun * 0.6 * k * (1.0 - night));
	}

	// ---- 近处的地面压暗：眼睛收到人站的那一条 ----
	float near = smoothstep(ground + 0.03, 1.02, uv.y) * outdoor;
	col *= mix(vec3(1.0), mix(vec3(0.82, 0.83, 0.88), vec3(0.62, 0.64, 0.80), night), near * 0.55 * k);

	// ---- 光柱：从太阳那边斜下来 ----
	float sun_on = (1.0 - night) * (1.0 - overcast) * (1.0 - indoor);
	if (sun_on > 0.01) {
		vec2 d = (uv - sun) * vec2(aspect, 1.0);
		float dist = length(d);
		float ang = atan(d.x, d.y);
		// 角度上的几道条纹，各自慢慢变宽变窄
		float t = TIME * 0.035;
		float rays = vnoise(vec2(ang * 9.0, t)) * 0.6 + vnoise(vec2(ang * 23.0 + 4.0, t * 1.7)) * 0.4;
		rays = smoothstep(0.42, 0.95, rays);
		float fall = exp(-dist * 1.15) * smoothstep(0.0, 0.12, dist);
		// 光柱主要在空中：地面线往下淡掉
		float air = 1.0 - smoothstep(ground - 0.08, ground + 0.04, uv.y);
		float amt = rays * fall * air * sun_on * (0.10 + dusk * 0.22 + dawn * 0.16) * k;
		vec3 ray_col = mix(vec3(1.0, 0.94, 0.80), vec3(1.0, 0.70, 0.45), dusk);
		ray_col = mix(ray_col, vec3(1.0, 0.86, 0.70), dawn);
		col = screen_blend(col, ray_col * amt);
		// 太阳周围一大团暖光（比天上画的那个圆大得多，罩在楼上）
		float halo = exp(-dist * 3.2) * sun_on * (0.10 + dusk * 0.28 + dawn * 0.18) * k;
		col = screen_blend(col, ray_col * halo);
		// 光里的尘：世界坐标里的稀疏小点，慢慢飘，只在光柱里看得见
		vec2 wp = (cam + (uv - 0.5) * vec2(aspect, 1.0) * view_h) / 26.0;
		wp += vec2(TIME * 0.35, sin(TIME * 0.21) * 0.6);
		vec2 g = floor(wp);
		float h = hash(g);
		vec2 sp = g + vec2(hash(g + 1.7), hash(g + 9.1));
		float mote = step(0.86, h) * (1.0 - smoothstep(0.03, 0.09, distance(wp, sp)));
		mote *= 0.6 + 0.4 * sin(TIME * (1.0 + h * 3.0) + h * 30.0);
		col = screen_blend(col, ray_col * mote * (rays * 0.7 + 0.3) * fall * air * sun_on * 0.8 * k);
	}

	// ---- 地气：清早、雨天贴地一层薄雾 ----
	float mist = (dawn * 0.45 + overcast * 0.35 + dusk * 0.1) * (1.0 - indoor);
	if (mist > 0.01) {
		vec2 wp = (cam + (uv - 0.5) * vec2(aspect, 1.0) * view_h) / 900.0;
		float n = vnoise(vec2(wp.x * 2.2 + TIME * 0.025, wp.y * 6.0)) * 0.6 + vnoise(vec2(wp.x * 5.0 - TIME * 0.04, wp.y * 11.0)) * 0.4;
		// 地平线到地面之间最厚，地面线往下薄
		float band = smoothstep(horizon - 0.12, ground - 0.02, uv.y) * (1.0 - smoothstep(ground + 0.02, ground + 0.24, uv.y) * 0.7);
		vec3 fog = mix(vec3(0.93, 0.95, 0.97), vec3(0.98, 0.88, 0.80), dusk);
		fog = mix(fog, vec3(0.90, 0.92, 0.94), overcast);
		col = mix(col, fog, band * (0.25 + 0.55 * n) * mist * 0.42 * k);
	}

	// ---- 压角 ----
	vec2 v = (uv - mix(vec2(0.5), focus, 0.55)) * vec2(aspect * 0.62, 1.0);
	float vig = smoothstep(0.35, 0.95, length(v));
	vec3 vig_col = mix(vec3(0.80, 0.80, 0.86), vec3(0.42, 0.46, 0.66), night);
	col *= mix(vec3(1.0), vig_col, vig * (0.28 + 0.35 * night) * k);

	COLOR = vec4(col, 1.0);
}
