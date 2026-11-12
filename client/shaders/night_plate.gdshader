shader_type canvas_item;
render_mode blend_mul, unshaded;
// 夜色（微缩模型）：白天渲染好的模型，到了傍晚、夜里，像把屋里的顶灯关掉、只留模型里的小灯——
//   · 夜：整块盖一层平滑的蓝紫（正片叠底），离灯越远越深；灯底下几乎不压，留出一圈暖黄的光池
//   · 灯：光池边缘带一点暖色（再亮的那一下在 lamp_glow.gdshader 里往上加）
//   · 晚霞 / 清早：从太阳那边斜着铺过来一层暖色，越靠那边越浓
//   · 旧：人老了，画面像放久了的彩色照片——整体泛暖、褪一点色、四边更深
// 用正片叠底盖在整张图上（世界坐标），跟着地图走，不随镜头游动。全是平滑渐变，没有网点、没有抖动。
// 灯光是一张烘好的低分辨率贴图（print_light.gd），所以灯再多也只采样一次。

uniform vec2 map_size = vec2(2400.0, 1600.0);
uniform sampler2D light_map : filter_linear, repeat_disable;
uniform float night = 0.0;   // 0 白天 ~ 1 深夜
uniform float dusk = 0.0;    // 晚霞
uniform float dawn = 0.0;    // 清早
uniform float age = 0.0;     // 0 新的 ~ 1 放了一辈子
uniform vec3 night_ink : source_color = vec3(0.30, 0.33, 0.62);   // 夜里没灯的地方压成什么色（蓝紫）
uniform vec3 deep_ink : source_color = vec3(0.17, 0.19, 0.42);    // 深夜最暗的角落
uniform vec3 lamp_ink : source_color = vec3(1.00, 0.86, 0.62);    // 灯下（叠底只能压，所以是「少压蓝」= 发暖）
uniform vec3 dusk_ink : source_color = vec3(1.00, 0.74, 0.54);
uniform vec3 dawn_ink : source_color = vec3(1.00, 0.88, 0.74);
// 两个人各带一圈光：xy 位置，z 半径，w 强度
uniform vec4 actor_a = vec4(0.0);
uniform vec4 actor_b = vec4(0.0);
// 哪儿是天（scene_art.scene_mask：底图的不透明度缩小版，白 = 实的）。天上的远景、中景自己会变夜色、点灯，
// 夜版在那儿只压薄薄一层（sky_keep），不然远处的灯全被压没了
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

// 人身上的一圈光：中心最亮，往外平滑淡掉（smoothstep 的平方，边上没有棱）
float glow(vec2 p, vec4 a) {
	if (a.w <= 0.0) {
		return 0.0;
	}
	float d = distance(p, a.xy) / max(a.z, 1.0);
	float g = 1.0 - smoothstep(0.0, 1.0, d);
	return a.w * g * g;
}

void fragment() {
	float solid = use_mask ? texture(scene_mask, UV).r : 1.0;
	float k = mix(sky_keep, 1.0, solid);
	float nt = night * k;
	float dk = dusk * k;
	float dw = dawn * k;

	vec3 col = vec3(1.0);

	// ---- 晚霞 / 清早：一层暖色，从右上往左下斜着由浓到淡（傍晚太阳在右边），带一点很大很慢的起伏 ----
	float slope = clamp((world.x * 0.8 + (map_size.y - world.y) * 0.6) / (map_size.x * 0.8 + map_size.y * 0.6), 0.0, 1.0);
	float swell = vnoise(world * 0.0016) - 0.5;
	if (dk > 0.001) {
		col *= mix(vec3(1.0), dusk_ink, clamp(dk * (0.16 + 0.30 * slope + swell * 0.08), 0.0, 1.0));
	}
	if (dw > 0.001) {
		col *= mix(vec3(1.0), dawn_ink, clamp(dw * (0.26 - 0.14 * slope + swell * 0.06), 0.0, 1.0));
	}

	if (nt > 0.001) {
		// 灯：烘好的灯光图 + 两个人身上的一小圈；smoothstep 一下，光池边缘更柔
		float lit = texture(light_map, UV).r;
		lit = 1.0 - (1.0 - lit) * (1.0 - glow(world, actor_a)) * (1.0 - glow(world, actor_b));
		lit = smoothstep(0.0, 1.0, lit);
		float dark = nt * (1.0 - lit);
		// 蓝紫：有灯处不压，暗处压满；深夜最暗处再往深蓝里沉一点
		vec3 tint = mix(vec3(1.0), night_ink, dark);
		tint = mix(tint, tint * (deep_ink / night_ink), dark * dark * 0.35 * night);
		col *= tint;
		// 灯池：只在灯下「少压蓝」，看起来是暖黄的一圈，往外平滑过渡到蓝紫
		float pool = nt * lit * (1.0 - lit * 0.35);
		col *= mix(vec3(1.0), lamp_ink, clamp(pool, 0.0, 1.0) * 0.55);
	}

	// ---- 旧：像放久了的彩色照片——整体泛暖褪色，四边慢慢深下去（平滑的暗角，没有斑点） ----
	if (age > 0.001) {
		vec2 e = min(world, map_size - world) / 420.0;
		float edge = 1.0 - smoothstep(0.0, 1.0, min(e.x, e.y));
		float drift = vnoise(world * 0.0022) * 0.5;  // 很大、很淡的一片片深浅，像相纸受潮
		float amount = age * (0.45 + 0.40 * edge + drift * 0.25);
		col *= mix(vec3(1.0), vec3(0.95, 0.87, 0.74), clamp(amount, 0.0, 1.0) * 0.46);
	}

	COLOR = vec4(col, 1.0);
}
