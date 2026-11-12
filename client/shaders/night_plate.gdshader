shader_type canvas_item;
render_mode blend_mul, unshaded;
// 夜版：把夜色当成第四块版印上去，而不是把整张图调暗。
//   · 靛蓝版：调幅网点，越靠近灯网点越小，灯底下干脆不印（留出纸）
//   · 灯黄版：只印在灯下，和靛蓝版网角不同
//   · 晚霞版：傍晚从河那边斜着铺过来的柿子橙
//   · 旧纸：人老了，这张印刷品也跟着泛黄、起斑
// 用正片叠底盖在整张地图上（世界坐标），网点跟着地图走，不会随镜头游动。
// 灯光是一张烘好的低分辨率贴图（print_light.gd），所以灯再多也只采样一次。

uniform vec2 map_size = vec2(2400.0, 1600.0);
uniform sampler2D light_map : filter_linear, repeat_disable;
uniform float night = 0.0;   // 0 白天 ~ 1 深夜
uniform float dusk = 0.0;    // 晚霞
uniform float dawn = 0.0;    // 清早
uniform float age = 0.0;     // 0 新印的 ~ 1 放了一辈子
uniform vec3 night_ink : source_color = vec3(0.17, 0.24, 0.50);
uniform vec3 lamp_ink : source_color = vec3(0.98, 0.80, 0.42);
uniform vec3 dusk_ink : source_color = vec3(0.98, 0.66, 0.40);
uniform vec3 dawn_ink : source_color = vec3(0.99, 0.86, 0.55);
uniform float cell = 6.0;    // （孔版时的网点间距，像素版不用）
const float PX = 3.0;        // 一个点多大（世界像素）
// 两个人各带一圈光：xy 位置，z 半径，w 强度
uniform vec4 actor_a = vec4(0.0);
uniform vec4 actor_b = vec4(0.0);
// 哪儿是天（scene_art.scene_mask：底图的不透明度缩小版，白 = 实的）。天上的远景、中景自己会变夜色、点灯，
// 夜版在那儿只印薄薄一层（sky_keep），不然远处的灯全被压没了
uniform sampler2D scene_mask : filter_linear, repeat_disable;
uniform bool use_mask = false;
uniform float sky_keep = 0.42;

varying vec2 world;

void vertex() {
	world = UV * map_size;
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

// 像素版的「网点」：每 3 个世界像素一个点（和底图同一张格子），cov 是这一点印不印的概率，
// 按 4×4 拜耳阈值抖动——灯下一圈圈的光是一档一档的点，不是网点。angle、size 留着不用（和孔版那版同一个接口）。
float bayer(vec2 q) {
	int x = int(mod(q.x, 4.0));
	int y = int(mod(q.y, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}

// 人身上不抖：抖动的格子落在脸上像棋盘，人又不一定站在点格上，格子和人的点会错开。
// 人那一块换成抖动的平均值（同样深浅的平涂），边上一圈按拜耳次序过渡，不留硬边。
float screen_dots(vec2 p, float angle, float size, float cov, float person) {
	float dots = step(bayer(floor(p / PX)), cov) * step(0.002, cov);
	return mix(dots, cov, person);
}

// 一个人占的那一块：xy 是脚往上 40（和 glow 同一个点），身子从脚往上约 210 世界像素
float body(vec2 p, vec4 a) {
	if (a.w <= 0.0) {
		return 0.0;
	}
	vec2 c = a.xy + vec2(0.0, 40.0 - 104.0);
	float d = length((p - c) / vec2(62.0, 112.0));
	return 1.0 - smoothstep(0.82, 1.12, d);
}

float glow(vec2 p, vec4 a) {
	float d = distance(p, a.xy) / max(a.z, 1.0);
	return a.w * (1.0 - smoothstep(0.0, 1.0, d));
}

void fragment() {
	// 整块按点算：一个点里颜色一样
	vec2 pw = (floor(world / PX) + 0.5) * PX;
	vec2 puv = pw / map_size;
	float solid = use_mask ? texture(scene_mask, puv).r : 1.0;
	float k = mix(sky_keep, 1.0, solid);
	float nt = night * k;
	float dk = dusk * k;
	float dw = dawn * k;
	// 网点边缘带一点手抖，不然太像电脑算的
	float jitter = (vnoise(pw * 0.035) - 0.5) * 0.04;
	float on_body = max(body(pw, actor_a), body(pw, actor_b));
	float person = step(bayer(floor(pw / PX) + vec2(2.0, 1.0)), on_body);

	vec3 col = vec3(1.0);

	// 晚霞 / 清早：主要是一层很淡的平网，再疏疏地撒一点大网点，斜着由浓到淡
	float slope = clamp((pw.x * 0.8 + (map_size.y - pw.y) * 0.6) / (map_size.x * 0.8 + map_size.y * 0.6), 0.0, 1.0);
	if (dk > 0.001) {
		float dusk_cov = dk * (0.03 + 0.13 * slope + jitter * 0.5);
		col *= mix(vec3(1.0), dusk_ink, screen_dots(pw, 1.309, cell * 2.0, clamp(dusk_cov, 0.0, 1.0), person) * 0.55);
		col *= mix(vec3(1.0), dusk_ink, dk * (0.12 + 0.20 * slope));
	}
	if (dw > 0.001) {
		float dawn_cov = dw * (0.12 - 0.09 * slope + jitter * 0.5);
		col *= mix(vec3(1.0), dawn_ink, screen_dots(pw, 1.309, cell * 2.0, clamp(dawn_cov, 0.0, 1.0), person) * 0.5);
		col *= mix(vec3(1.0), dawn_ink, dw * (0.20 - 0.12 * slope));
	}

	if (nt > 0.001) {
		// 灯：烘好的灯光图 + 两个人身上的一小圈
		float lit = texture(light_map, puv).r;
		lit = 1.0 - (1.0 - lit) * (1.0 - glow(pw, actor_a)) * (1.0 - glow(pw, actor_b));
		// 靛蓝夜版：一层平网打底 + 一层网点。暗处网点连成一片实地，
		// 只有靠近灯的那一圈才看得出网点一点点变小、露出纸来
		float dark = nt * (1.0 - lit);
		float night_cov = clamp(smoothstep(0.0, 0.78, dark) + jitter * nt * (1.0 - dark), 0.0, 1.0);
		col *= mix(vec3(1.0), night_ink, screen_dots(pw, 0.785, cell, night_cov, person) * 0.30);
		col *= mix(vec3(1.0), night_ink, dark * 0.70);
		// 灯黄版：只在灯下，网角和靛蓝版错开
		float lamp_cov = nt * smoothstep(0.25, 1.0, lit) * 0.55;
		col *= mix(vec3(1.0), lamp_ink, screen_dots(pw, 0.262, cell, lamp_cov, person) * 0.85);
		col *= mix(vec3(1.0), lamp_ink, nt * smoothstep(0.05, 0.9, lit) * 0.25);
	}

	// 旧纸：整体泛黄 + 零星的斑 + 四边更深
	if (age > 0.001) {
		vec2 e = min(pw, map_size - pw) / 260.0;
		float edge = 1.0 - clamp(min(e.x, e.y), 0.0, 1.0);
		float fox = smoothstep(0.74, 0.86, vnoise(pw * 0.012) * 0.7 + vnoise(pw * 0.05) * 0.3);
		float amount = age * (0.55 + 0.45 * edge) + fox * age * 0.6;
		col *= mix(vec3(1.0), vec3(0.93, 0.86, 0.70), clamp(amount, 0.0, 1.0) * 0.42);
	}

	COLOR = vec4(col, 1.0);
}
