shader_type spatial;
// 小人的衣服：实色布 + 细细的织纹 + 布的绒光（边上亮一点）；可选横条纹（青小时候的海魂衫）。
// 条纹按物体空间的高度算，胳膊、身子各自一节，条纹跟着那一节走。
render_mode diffuse_burley, cull_disabled;

uniform vec3 base : source_color = vec3(0.9);
uniform vec3 stripe_col : source_color = vec3(0.2, 0.5, 0.45);
uniform float stripes = 0.0;
uniform float stripe_pitch = 0.045;
uniform float roughness = 0.85;
uniform float double = 0.0;

varying vec3 obj;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	obj = VERTEX;
}

void fragment() {
	vec3 c = base;
	if (stripes > 0.5) {
		float y = obj.y / stripe_pitch;
		float aa = fwidth(y) * 0.8;
		float band = smoothstep(0.5 - aa, 0.5 + aa, abs(fract(y) - 0.5) * 2.0);
		c = mix(c, stripe_col, 1.0 - band);
	}
	// 织纹：很细的经纬，只动一点点明暗
	vec2 w = obj.xy * 900.0 + obj.zy * 900.0;
	float weave = (sin(w.x) * sin(w.y)) * 0.025;
	c *= 1.0 + weave;
	ALBEDO = c;
	ROUGHNESS = roughness;
	SPECULAR = 0.25;
	// 布的绒光：掠射角亮一点
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	RIM = 0.35 * fres;
	RIM_TINT = 0.7;
}
