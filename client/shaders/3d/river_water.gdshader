shader_type spatial;
// 海河的水（只给 river3d 用）：吃光（太阳、路灯在水面上有高光），自己算慢慢走的波纹法线；
// 兼容渲染器没有屏幕空间反射，所以「倒影」是假的：按菲涅尔把天色（stage3d 每帧塞进来的天顶/天边色）叠上去，
// 远处贴着对岸那一溜再压一道暗（对岸楼群、树的倒影），近处看得见水本身的深绿褐。
// 冬天 g_snow（stage3d：冬天 0.35、下雪 1）一上来就结冰：变灰白、不反光、有冰裂纹；下雪时冰上盖一层白。
// 下雨 g_wet：水面多一层细碎的雨点纹。
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

global uniform float g_night;
global uniform float g_snow;
global uniform float g_wet;

uniform vec3 deep : source_color = vec3(0.075, 0.095, 0.08);   // 近处往下看：深绿褐
uniform vec3 murk : source_color = vec3(0.2, 0.22, 0.16);      // 浑一点的地方
uniform vec3 sky_hor : source_color = vec3(0.78, 0.84, 0.9);   // 天边色（stage3d 的天，每帧更新）
uniform vec3 sky_top : source_color = vec3(0.32, 0.52, 0.82);  // 天顶色
uniform vec3 bank_col : source_color = vec3(0.16, 0.17, 0.16); // 对岸楼群、树的倒影
uniform float far_z = -62.0;    // 对岸河堤在哪
uniform float refl = 1.35;      // 天光倒影多亮

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// 一道正弦波的斜率：方向 d、波数 k、振幅 a、走的速度 w
vec2 wv(vec2 p, vec2 d, float k, float a, float w, float t) {
	return d * (a * k * cos(dot(p, d) * k + t * w));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 to_cam = cam - wpos;
	float dist = length(to_cam);
	vec3 V = to_cam / dist;
	float t = TIME;
	// 河水往右（+X）流：波纹整体慢慢往右漂
	vec2 p = wpos.xz + vec2(-t * 0.25, 0.0);
	vec2 g = vec2(0.0);
	g += wv(p, normalize(vec2(0.35, 1.0)), 1.7, 0.035, 0.9, t);
	g += wv(p, normalize(vec2(-0.6, 1.0)), 2.6, 0.022, 1.3, t);
	g += wv(p, normalize(vec2(1.0, 0.25)), 0.9, 0.05, 0.6, t);
	g += wv(p, normalize(vec2(0.15, -1.0)), 4.3, 0.012, 1.9, t);
	// 细碎的小涟漪：噪声差分
	vec2 q = p * vec2(1.6, 3.2) + vec2(t * 0.3, t * 0.12);
	float n0 = noise(q);
	g += vec2(noise(q + vec2(0.07, 0.0)) - n0, noise(q + vec2(0.0, 0.07)) - n0) * 0.9;
	// 下雨：一层更碎的点
	vec2 r = wpos.xz * 9.0 + vec2(t * 2.0, -t * 1.3);
	float rn = noise(r);
	g += vec2(noise(r + vec2(0.11, 0.0)) - rn, noise(r + vec2(0.0, 0.11)) - rn) * 2.2 * g_wet;
	// 远了波纹细得看不出，压平一点（也免得远处闪）
	g *= 1.0 / (1.0 + dist * 0.025);
	float ice = smoothstep(0.25, 0.33, g_snow);
	g *= 1.0 - ice * 0.92;
	vec3 n = normalize(vec3(-g.x, 1.0, -g.y));

	float ndv = clamp(dot(n, V), 0.0, 1.0);
	float fres = 0.06 + 0.94 * pow(1.0 - ndv, 4.0);
	vec3 R = reflect(-V, n);
	vec3 sky = mix(sky_hor, sky_top, clamp(R.y * 2.2, 0.0, 1.0));
	// 对岸的倒影：贴着对岸一溜暗，边上被波纹揉碎
	float wob = (noise(vec2(wpos.x * 0.6, wpos.z * 2.5 + t * 0.4)) - 0.5) * 4.0;
	float bank = smoothstep(far_z + 13.0, far_z + 1.5, wpos.z + wob);
	sky = mix(sky, bank_col * (1.0 - 0.6 * g_night), bank * 0.8);
	// 水本身：近处深、有一块块浑的
	float m = noise(wpos.xz * 0.12 + vec2(t * 0.02, 0.0));
	vec3 body = mix(deep, murk, smoothstep(0.35, 0.9, m) * 0.6);

	// 冰：灰白、有一道道裂纹；下雪了盖白
	vec2 ip = wpos.xz * 0.45;
	float c1 = abs(noise(ip) - 0.5);
	float c2 = abs(noise(ip * 2.3 + 7.0) - 0.5);
	float crack = 1.0 - smoothstep(0.0, 0.025, min(c1, c2 * 1.4));
	vec3 icec = mix(vec3(0.42, 0.5, 0.55), vec3(0.6, 0.66, 0.7), noise(wpos.xz * 0.3));
	icec = mix(icec, icec * 0.72, crack * 0.8);
	icec = mix(icec, vec3(0.86, 0.88, 0.92), smoothstep(0.6, 1.0, g_snow) * smoothstep(0.3, 0.7, noise(wpos.xz * 0.8)));

	ALBEDO = mix(body * (1.0 - fres), icec, ice);
	EMISSION = sky * fres * refl * (1.0 - ice * 0.7);
	ROUGHNESS = mix(0.07, 0.55, ice);
	SPECULAR = mix(0.35, 0.2, ice);
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
