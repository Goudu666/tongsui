shader_type spatial;
// 实时 3D 街景的「真材质」：红砖、灰砖、抹灰墙、水泥方砖、柏油、木板、波纹铁皮、漆过的铁、玻璃、雨棚帆布、油毡屋顶。
// 不用贴图：按世界坐标现算花纹（砖缝、板缝、方砖缝），再用屏幕导数把花纹的高低变成法线起伏（砖缝凹进去、接得住光），
// 所以放多近都不糊，也不占手机显存。全局参数：g_wet 下雨地湿反光、g_snow 朝上的面积雪、g_night 夜里亮窗。
render_mode diffuse_burley, specular_schlick_ggx;

global uniform float g_wet;
global uniform float g_snow;
global uniform float g_night;

uniform int pattern = 0;          // 0 实色 1 砖 2 方砖 3 柏油 4 竖木板 5 波纹铁皮 6 抹灰 7 条纹帆布 8 玻璃窗 9 油毡 10 横木板 11 瓦
uniform vec3 col_a : source_color = vec3(0.6);
uniform vec3 col_b : source_color = vec3(0.4);  // 砖缝 / 方砖缝 / 条纹第二色
uniform vec2 cell = vec2(0.24, 0.065);           // 一块砖（米）
uniform float rough = 0.85;
uniform float relief = 1.0;       // 法线起伏多明显
uniform float grime = 0.5;        // 墙根发黑、雨水往下流的印子
uniform float vary = 0.18;        // 一块一块颜色差多少
uniform float metal = 0.0;
uniform float lit_chance = 0.55;  // 玻璃窗：夜里亮灯的几成
uniform vec3 lit_col : source_color = vec3(1.0, 0.66, 0.36);
uniform float emit = 0.0;         // 自己发光（灯罩、招牌灯）乘 g_night
uniform vec3 emit_col : source_color = vec3(1.0, 0.8, 0.5);
uniform float ground_y = 0.0;     // 墙根在哪个高度

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { s += a * noise(p); p *= 2.03; a *= 0.5; }
	return s;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// 没有切线也能做凹凸：按屏幕导数把高度的变化折进法线（Mikkelsen 的做法）
vec3 bump(vec3 n, vec3 vpos, float h) {
	vec3 dpx = dFdx(vpos);
	vec3 dpy = dFdy(vpos);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpy, n);
	vec3 r2 = cross(n, dpx);
	float det = dot(dpx, r1);
	vec3 g = sign(det) * (dhx * r1 + dhy * r2);
	return normalize(abs(det) * n - g);
}

void fragment() {
	vec3 an = abs(wnrm);
	// 按朝向取平面坐标：地面 xz，朝前后的墙 xy，朝左右的墙 zy
	vec2 uv;
	bool floor_face = an.y > 0.6;
	if (floor_face) uv = wpos.xz * vec2(1.0, -1.0);
	else if (an.x > an.z) uv = vec2(wpos.z, wpos.y);
	else uv = vec2(wpos.x, wpos.y);
	vec3 col = col_a;
	float h = 0.0;
	float r = rough;
	float spec = 0.4;
	float m = metal;
	vec3 emission = vec3(0.0);
	if (pattern == 1) {
		// 砖：一顺一丁的错缝，砖缝凹进去；每块砖颜色略不同、有烧黑的
		float row = floor(uv.y / cell.y);
		float off = mod(row, 2.0) * 0.5;
		float bx = floor(uv.x / cell.x + off);
		vec2 f = vec2(fract(uv.x / cell.x + off), fract(uv.y / cell.y));
		float mort = 0.012;
		vec2 e = min(f, 1.0 - f) * cell;
		float edge = smoothstep(mort * 0.5, mort, min(e.x, e.y));
		float rnd = hash(vec2(bx, row));
		vec3 brick = col_a * (1.0 + (rnd - 0.5) * vary * 2.0);
		brick = mix(brick, brick * 0.55, step(0.93, rnd));
		brick *= 0.9 + 0.2 * noise(uv * 40.0);
		col = mix(col_b, brick, edge);
		h = edge * 0.6 + noise(uv * 60.0) * 0.15;
	} else if (pattern == 2) {
		// 人行道方砖
		vec2 g = uv / cell;
		vec2 f = fract(g);
		vec2 e = min(f, 1.0 - f) * cell;
		float edge = smoothstep(0.004, 0.012, min(e.x, e.y));
		float rnd = hash(floor(g));
		col = mix(col_b, col_a * (1.0 + (rnd - 0.5) * vary * 2.0), edge);
		col *= 0.9 + 0.18 * fbm(uv * 6.0);
		h = edge * 0.5 + noise(uv * 30.0) * 0.2;
	} else if (pattern == 3) {
		// 柏油：细碎的石子 + 一片片补过的颜色
		float grit = noise(uv * 90.0);
		float patch = smoothstep(0.55, 0.6, fbm(uv * 0.35));
		col = col_a * (0.85 + 0.3 * grit) * mix(1.0, 0.82, patch);
		col *= 0.92 + 0.16 * fbm(uv * 2.0);
		h = grit * 0.5;
	} else if (pattern == 4 || pattern == 10) {
		// 木板：竖的（门、板墙）或横的（雨搭、栏杆），板缝 + 木纹
		vec2 q = pattern == 4 ? uv : uv.yx;
		float b = floor(q.x / cell.x);
		float f = fract(q.x / cell.x);
		float edge = smoothstep(0.0, 0.06, min(f, 1.0 - f));
		float rnd = hash(vec2(b, 3.0));
		float grain = noise(vec2(q.x * 60.0, q.y * 4.0 + rnd * 10.0));
		col = col_a * (1.0 + (rnd - 0.5) * vary * 2.0) * (0.88 + 0.24 * grain);
		col = mix(col_b, col, edge);
		h = edge * 0.6 + grain * 0.1;
		// 漆掉了的地方露出木头
		float chip = smoothstep(0.72, 0.75, fbm(uv * 5.0 + 7.0)) * grime;
		col = mix(col, vec3(0.45, 0.33, 0.22), chip * 0.8);
	} else if (pattern == 5) {
		// 波纹铁皮（自行车棚、雨搭）：竖着一道道，带锈
		float w = sin(uv.x / cell.x * 6.2832);
		h = w * 0.5 + 0.5;
		float rust = smoothstep(0.5, 0.8, fbm(uv * vec2(3.0, 1.2))) * grime;
		col = mix(col_a, vec3(0.45, 0.25, 0.14), rust) * (0.85 + 0.15 * h);
		r = mix(rough, 0.95, rust);
		m = mix(metal, 0.0, rust);
	} else if (pattern == 6) {
		// 抹灰墙：大片的斑驳、水渍
		float blot = fbm(uv * 1.3);
		col = col_a * (0.86 + 0.24 * blot) * (0.95 + 0.08 * noise(uv * 25.0));
		h = noise(uv * 18.0) * 0.4 + blot * 0.2;
	} else if (pattern == 7) {
		// 条纹帆布（雨棚）
		float s = step(0.5, fract(uv.x / cell.x));
		col = mix(col_a, col_b, s) * (0.92 + 0.12 * noise(uv * vec2(8.0, 40.0)));
		h = noise(uv * vec2(4.0, 80.0)) * 0.2;
	} else if (pattern == 8) {
		// 玻璃：暗、亮面反光；夜里有的窗亮灯（一扇窗一个随机数），亮的窗里透出窗帘的影
		// 一扇窗一个随机数：搭的时候写在顶点色里（COLOR.r 亮不亮、COLOR.g 窗帘），没写就按格子算
		vec2 id = floor(uv / cell) + COLOR.gb * 37.0;
		float rnd = COLOR.r < 0.999 ? COLOR.r : hash(id + vec2(7.0, 3.0));
		float on = step(1.0 - lit_chance, rnd);
		vec2 f = fract(uv / cell);
		float curtain = smoothstep(0.0, 0.08, abs(f.x - 0.5) - 0.18 - rnd * 0.12);
		vec3 inner = col_a * (0.6 + 0.4 * f.y);
		col = inner;
		r = 0.08;
		spec = 0.8;
		vec3 glow = lit_col * (0.7 + 0.5 * hash(id + vec2(1.0, 9.0))) * mix(1.0, 0.45, curtain * step(0.5, hash(id + 2.0)));
		emission = glow * on * g_night * 1.15;
		col = mix(col, col * 0.4, on * g_night);
	} else if (pattern == 9) {
		// 油毡屋顶：粗、一卷卷搭着
		float row = fract(uv.y / cell.y);
		col = col_a * (0.85 + 0.25 * noise(uv * 20.0)) * mix(0.85, 1.0, smoothstep(0.0, 0.1, row));
		h = smoothstep(0.0, 0.1, row);
	} else if (pattern == 11) {
		// 瓦：一道道的瓦垄
		float w = abs(sin(uv.x / cell.x * 3.1416));
		float row = fract(uv.y / cell.y);
		h = w * 0.7 + smoothstep(0.85, 1.0, row) * 0.3;
		col = col_a * (0.75 + 0.3 * w) * (0.9 + 0.2 * hash(floor(uv / cell)));
	} else {
		col *= COLOR.rgb;
		col *= 0.94 + 0.1 * noise(uv * 12.0);
		h = noise(uv * 30.0) * 0.1;
	}
	// 脏：墙根往上一截发黑，窗台下雨水流的印子
	if (!floor_face) {
		float base = 1.0 - smoothstep(0.0, 0.7 + 0.4 * noise(uv * 2.0), wpos.y - ground_y);
		float streak = smoothstep(0.55, 0.9, noise(vec2(uv.x * 7.0, uv.y * 0.6))) * 0.5;
		col *= 1.0 - grime * (base * 0.35 + streak * 0.18);
	} else {
		col *= 1.0 - grime * 0.12 * smoothstep(0.4, 0.8, fbm(uv * 0.8));
	}
	vec3 n = NORMAL;
	if (relief > 0.0) {
		n = bump(NORMAL, VERTEX, h * 0.004 * relief);
	}
	// 下雨：地面变深、亮、像镜子；墙也深一点
	float up = smoothstep(0.6, 0.9, wnrm.y);
	float wet = g_wet * (up * 0.9 + 0.25);
	col *= 1.0 - wet * 0.38;
	r = mix(r, 0.12, wet * up);
	spec = mix(spec, 0.7, wet * up);
	// 积雪：朝上的面盖白，沿着噪声有薄有厚
	float snow = g_snow * smoothstep(0.55, 0.85, wnrm.y) * smoothstep(0.3, 0.6, noise(wpos.xz * 3.0) * 0.6 + g_snow * 0.6);
	col = mix(col, vec3(0.8, 0.83, 0.87), snow);
	r = mix(r, 0.8, snow);
	ALBEDO = col;
	ROUGHNESS = r;
	METALLIC = m;
	SPECULAR = spec;
	NORMAL = mix(n, NORMAL, snow);
	EMISSION = emission + emit_col * emit * g_night;
}
