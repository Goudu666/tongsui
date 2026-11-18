shader_type spatial;
// 日漫手办的头发：像上了漆的 PVC 发型——明暗软、根深梢浅、发束缝里暗，
// 头顶一圈「天使环」（顺着发丝方向的各向异性高光，Kajiya-Kay），每一缕高低错开一点，环就断成一截一截。
// 网格自带：COLOR.rgb = 发丝方向（物体空间，×0.5+0.5），COLOR.a = 从根到梢 0→1；UV.x = 这一缕的编号（0~1，随机）。
// 天使环画在底色里（像手办上漆的那道亮），亮度跟着场景的光走，白天晚上都在、不会曝；真的光再加一点细高光。
render_mode cull_disabled, diffuse_lambert;

uniform vec3 base : source_color = vec3(0.3, 0.2, 0.18);
uniform vec3 tip_col : source_color = vec3(0.5, 0.35, 0.28);   // 发梢透光的颜色（浅一点、暖一点）
uniform float tip_amt = 0.45;
uniform float root_k = 0.72;      // 发根压暗
uniform vec3 spec_col : source_color = vec3(0.9, 0.8, 0.75);   // 天使环的颜色（青偏冷蓝，梅偏暖）
uniform float ring_amt = 0.75;    // 天使环多亮（混进底色的比例）
uniform float ring_shift = 0.12;  // 环往上 / 往下挪（沿法线偏发丝方向）
uniform float ring_jit = 0.13;    // 每缕错开多少（环断开的程度）
uniform float ring_pow = 110.0;    // 环多窄
uniform float sheen = 0.18;       // 第二道宽的、带颜色的光泽
uniform float inner_k = 0.5;      // 发束里头那面 / 背面
uniform vec3 shade_tint : source_color = vec3(0.72, 0.62, 0.72);
uniform float band = 0.0;
uniform float soft = 0.05;
uniform float shade_floor = 1.0;
uniform float lit_k = 0.36;
uniform float rim = 0.3;
uniform vec3 rim_col : source_color = vec3(1.0, 0.96, 0.9);
uniform float sat = 1.0;
uniform float paper = 0.0;
uniform float glow = 0.035;       // 晚上：环自己留一点亮（很少）

varying vec3 tang;
varying float along;
varying float sid;
varying vec3 obj;

float hash1(float x) { return fract(sin(x * 127.1 + 11.7) * 43758.5453); }
float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash1(i), hash1(i + 1.0), f);
}
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	obj = VERTEX;
	vec3 t = COLOR.rgb * 2.0 - 1.0;
	if (COLOR.a > 0.999 && min(COLOR.r, min(COLOR.g, COLOR.b)) > 0.999) {
		// 没带方向的网格：当它往下垂
		t = vec3(0.0, -1.0, 0.0);
	}
	t = t - NORMAL * dot(NORMAL, t);
	tang = normalize((MODELVIEW_MATRIX * vec4(t + vec3(0.0, 1e-4, 0.0), 0.0)).xyz);
	along = COLOR.a;
	sid = UV.x;
}

// Kajiya-Kay：沿法线把发丝方向挪一点，环就上下错开
float kk(vec3 T, vec3 N, vec3 H, float shift, float p) {
	vec3 t = normalize(T + N * shift);
	float th = dot(t, H);
	float s = sqrt(max(0.0, 1.0 - th * th));
	return smoothstep(-1.0, 0.0, th) * pow(s, p);
}

void fragment() {
	// 每一缕：编号定一个随机的深浅和环的高低；发壳（编号连续变）就是一圈细细的发丝
	float strand = noise1(sid * 37.0);
	float strand2 = noise1(sid * 113.0 + along * 3.0);
	vec3 c = base * (0.94 + 0.12 * strand);
	// 根深、梢浅偏暖
	c = mix(c * root_k, c, smoothstep(0.0, 0.4, along));
	c = mix(c, tip_col, smoothstep(0.45, 1.0, along) * tip_amt);
	if (!FRONT_FACING) {
		c *= inner_k;
	}
	vec3 N = normalize(NORMAL);
	vec3 V = normalize(VIEW);
	// 天使环：一盏「画上去的灯」在镜头上方偏一点，环就总在头顶前面那一圈
	vec3 Lv = normalize(vec3(-0.15, 0.85, 1.0));
	vec3 H = normalize(Lv + V);
	float sh = ring_shift + (strand - 0.5) * ring_jit + (strand2 - 0.5) * 0.06;
	float k1 = kk(tang, N, H, sh, ring_pow);
	float aa = fwidth(k1) * 1.5 + 0.02;
	float ring = smoothstep(0.66 - aa, 0.78 + aa, k1) * 0.8 + smoothstep(0.3, 0.7, k1) * 0.2;
	ring *= smoothstep(0.04, 0.2, along) * (1.0 - smoothstep(0.5, 0.75, along));
	ring *= smoothstep(0.0, 0.35, dot(N, V));
	if (!FRONT_FACING) {
		ring = 0.0;
	}
	// 第二道：宽一点、带头发本色的光泽（漆面的感觉）
	float k2 = kk(tang, N, H, sh - 0.25, 10.0);
	c += base * sheen * 2.0 * k2;
	c = mix(c, spec_col, clamp(ring * ring_amt, 0.0, 1.0));
	if (paper > 0.0) {
		vec2 q = obj.xy * 60.0 + obj.zx * 37.0;
		c *= 1.0 + (noise2(q * 2.5) - 0.5) * 0.08 * paper + (noise2(q * 0.13) - 0.5) * 0.22 * paper;
	}
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, sat);
	ALBEDO = c;
	EMISSION = spec_col * ring * ring_amt * glow;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float sh = smoothstep(0.35, 0.65, ATTENUATION);
	// 头发的明暗交界软一点（手办上漆的渐变，不是一刀切）
	float sf = max(soft, 0.16);
	float lit = smoothstep(band - sf, band + sf, ndl) * sh;
	vec3 lc = LIGHT_COLOR / PI;
	vec3 dark = LIGHT_IS_DIRECTIONAL ? shade_tint * shade_floor * 0.55 * lit_k : vec3(0.0);
	DIFFUSE_LIGHT += lc * mix(dark, vec3(lit_k), lit);
	// 轮廓光：亮的那一侧的边上，细一点
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float r = smoothstep(0.6, 0.85, fres) * lit * rim;
	SPECULAR_LIGHT += lc * rim_col * r * 0.5;
	// 真的光打出来的发丝高光（路灯下也闪一下）
	vec3 H = normalize(LIGHT + VIEW);
	float k = kk(tang, NORMAL, H, ring_shift * 0.5, 90.0);
	SPECULAR_LIGHT += lc * spec_col * k * 0.18 * lit;
}
