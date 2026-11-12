shader_type spatial;
// 树冠：模型树那种海绵团（微缩模型里树就是这么做的）。一团团颜色深浅不一、表面细碎起伏，风一吹整团轻轻晃。
// 季节：leaf 颜色由 stage3d 按春夏秋冬设；冬天整团藏起来只剩枝子。
render_mode diffuse_burley;

global uniform float g_snow;
uniform vec3 leaf : source_color = vec3(0.32, 0.45, 0.2);
uniform vec3 leaf2 : source_color = vec3(0.5, 0.58, 0.25);
uniform float sway = 1.0;

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s = sin(TIME * 1.3 + w.x * 0.7 + w.y * 0.4) * 0.03 + sin(TIME * 3.1 + w.z * 2.0) * 0.008;
	VERTEX.x += s * sway * clamp(VERTEX.y + 0.5, 0.0, 1.5);
	// 表面碎一点：一团团的叶子
	float n = noise(w * 7.0) * 0.7 + noise(w * 19.0) * 0.3;
	VERTEX += NORMAL * (n - 0.5) * 0.16;
	wpos = w;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = noise(wpos * 14.0);
	float n2 = noise(wpos * 3.0);
	vec3 c = mix(leaf, leaf2, smoothstep(0.3, 0.8, n2)) * (0.65 + 0.55 * n);
	// 朝上的面亮一点（叶子顶上受光多）
	c *= 0.85 + 0.25 * clamp(wnrm.y, 0.0, 1.0);
	float snow = g_snow * smoothstep(0.3, 0.8, wnrm.y) * step(0.4, n);
	c = mix(c, vec3(0.92, 0.94, 0.97), snow);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	// 透光：背光时叶子边缘发亮
	BACKLIGHT = vec3(0.25, 0.3, 0.1);
}
