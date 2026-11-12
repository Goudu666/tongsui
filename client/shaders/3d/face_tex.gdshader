shader_type spatial;
// 主角模型（造型甲，微缩模型线程的 glb）的脸：五官是贴图（经纬度 UV 画在头那个球上），
// 这里在贴图上补眨眼、张嘴：眼睛、嘴在贴图上的位置由 figure3d.gd 读贴图找出来（eye_l / eye_r / mouth：中心 uv、半宽高）。
//   眨眼：眼睛那块抹成皮肤色，画一道往下弯的闭眼线；张嘴：嘴那儿画一个深色的小椭圆。
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 skin : source_color = vec3(0.96, 0.75, 0.6);
uniform vec3 line_col : source_color = vec3(0.16, 0.1, 0.1);
uniform vec3 mouth_col : source_color = vec3(0.45, 0.15, 0.16);
uniform vec4 eye_l = vec4(0.43, 0.45, 0.02, 0.05);
uniform vec4 eye_r = vec4(0.57, 0.45, 0.02, 0.05);
uniform vec4 mouth = vec4(0.5, 0.31, 0.01, 0.008);
uniform float down = -1.0;  // 脸上「往下」是 v 增大（1）还是减小（-1）
uniform float blink = 0.0;
uniform float open = 0.0;
uniform float smile = 0.5;  // 贴图的嘴是画死的，这个只为和 face.gdshader 同名参数（不用）
uniform float roughness = 0.58;

float closed_eye(vec2 uv, vec4 e, out float lid) {
	vec2 d = (uv - e.xy) / (e.zw * vec2(1.35, 1.25));
	float inside = 1.0 - smoothstep(0.85, 1.0, length(d));
	// 闭眼线：眼睛中线偏下，两头往上翘（∪）
	float x = (uv.x - e.x) / (e.z * 1.25);
	float y = e.y + down * e.w * (0.25 - 0.35 * x * x);
	float thick = e.w * 0.14;
	float aa = fwidth(uv.y) * 1.2;
	lid = (1.0 - smoothstep(thick, thick + aa, abs(uv.y - y))) * step(abs(x), 1.0);
	return inside;
}

void fragment() {
	vec2 uv = UV;
	vec3 c = texture(tex, uv).rgb;
	if (blink > 0.5) {
		float lid_l;
		float lid_r;
		float in_l = closed_eye(uv, eye_l, lid_l);
		float in_r = closed_eye(uv, eye_r, lid_r);
		c = mix(c, skin, max(in_l, in_r));
		c = mix(c, line_col, max(lid_l, lid_r));
	}
	if (open > 0.01) {
		vec2 d = (uv - (mouth.xy + vec2(0.0, down * mouth.w * 1.2))) / (vec2(mouth.z * 0.8, mouth.w * 1.6 * open) + 1e-4);
		float m = 1.0 - smoothstep(0.8, 1.0, length(d));
		c = mix(c, mouth_col, m);
	}
	ALBEDO = c;
	ROUGHNESS = roughness;
	SPECULAR = 0.35;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	RIM = 0.25 * fres;
	RIM_TINT = 0.6;
}
