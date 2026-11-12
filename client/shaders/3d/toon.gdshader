shader_type spatial;
// 日漫风的人：赛璐璐明暗（亮面、暗面两块颜色，交界软一点或硬一点看风格），暗面偏暖偏紫（不是变灰），
// 亮面边上一道轮廓光；头发多一圈「天使环」高光。布：可选横条纹、细织纹；纸感（水彩那一版）。
// 风格参数（soft、shade_tint、rim、paper……）由 figure3d.gd 按选的那一版统一设。
render_mode cull_disabled, diffuse_lambert;

uniform vec3 base : source_color = vec3(0.9);
uniform vec3 shade_tint : source_color = vec3(0.72, 0.62, 0.72); // 暗面 = 底色 × 这个
uniform float band = 0.05;        // 明暗交界在哪（N·L）
uniform float soft = 0.05;        // 交界多软
uniform float shade_floor = 1.0;  // 暗面亮度（乘在 shade_tint 上）
uniform float lit_k = 0.36;      // 亮面多亮（赛璐璐整块亮，比朗伯平均亮，压一点）
uniform float rim = 0.35;         // 轮廓光
uniform vec3 rim_col : source_color = vec3(1.0, 0.96, 0.9);
uniform float stripes = 0.0;
uniform vec3 stripe_col : source_color = vec3(0.2, 0.5, 0.45);
uniform float stripe_pitch = 0.045;
uniform float weave = 0.02;
uniform float paper = 0.0;        // 水彩：纸纹、颜色晕开一点
uniform float hair = 0.0;         // 1 = 头发：天使环
uniform vec3 head_c = vec3(0.0);  // 头发：头心（物体空间）
uniform float ring_lat = 0.78;    // 天使环在头顶往下多少（纬度，弧度）
uniform float ring_w = 0.09;
uniform float ring_amt = 0.32;
uniform float sat = 1.0;          // 整体饱和度

varying vec3 obj;
varying vec3 objn;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	obj = VERTEX;
	objn = NORMAL;
}

void fragment() {
	vec3 c = base;
	if (stripes > 0.5) {
		float y = obj.y / stripe_pitch;
		float aa = fwidth(y) * 0.8;
		float b = smoothstep(0.5 - aa, 0.5 + aa, abs(fract(y) - 0.5) * 2.0);
		c = mix(c, stripe_col, 1.0 - b);
	}
	vec2 w = obj.xy * 900.0 + obj.zy * 900.0;
	c *= 1.0 + sin(w.x) * sin(w.y) * weave;
	if (paper > 0.0) {
		vec2 q = obj.xy * 60.0 + obj.zx * 37.0;
		c *= 1.0 + (noise(q * 2.5) - 0.5) * 0.08 * paper + (noise(q * 0.13) - 0.5) * 0.22 * paper;
	}
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, sat);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float sh = smoothstep(0.35, 0.65, ATTENUATION);
	float lit = smoothstep(band - soft, band + soft, ndl) * sh;
	vec3 lc = LIGHT_COLOR / PI;
	// 平行光（太阳、补光）暗面留一层带色的光，暗面是「暖紫」不是灰；路灯这类点光只照亮面
	vec3 dark = LIGHT_IS_DIRECTIONAL ? shade_tint * shade_floor * 0.55 * lit_k : vec3(0.0);
	DIFFUSE_LIGHT += lc * mix(dark, vec3(lit_k), lit);
	// 轮廓光：亮的那一侧的边上
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float r = smoothstep(0.55, 0.75, fres) * lit * rim;
	SPECULAR_LIGHT += lc * rim_col * r * 0.6;
	if (hair > 0.5) {
		// 天使环：头顶往下一圈亮带，按发丝方向断成一截一截
		vec3 d = normalize(obj - head_c);
		float lat = acos(clamp(d.y, -1.0, 1.0));
		float u = atan(d.x, d.z);
		float zig = sin(u * 26.0) * 0.035 + sin(u * 9.0) * 0.03;
		float ring = 1.0 - smoothstep(ring_w * 0.5, ring_w, abs(lat - ring_lat - zig));
		float face = smoothstep(-0.2, 0.5, dot(NORMAL, VIEW));
		SPECULAR_LIGHT += lc * mix(base, vec3(1.0), 0.45) * ring * ring_amt * face * (0.35 + 0.65 * lit);
	}
}
