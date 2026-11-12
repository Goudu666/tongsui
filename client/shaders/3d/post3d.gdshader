shader_type canvas_item;
// 实时 3D 的成片：移轴（只有人站的那一条清楚，上头的楼顶电线、下头的马路渐渐虚掉——微缩模型照片的味道）、
// 灯晕（夜里路灯和亮窗往外泛）、调色、暗角、胶片颗粒。
// sharp 原画，soft 四分之一大小糊过的那张；focus_y 人站的那条线在屏幕上的高度（0 顶 1 底）
uniform sampler2D sharp : filter_linear;
uniform sampler2D soft : filter_linear;
uniform vec2 soft_px = vec2(0.0021, 0.0037);
uniform float focus_y = 0.6;
uniform float focus_band = 0.17;   // 清楚的那条有多宽（半宽）
uniform float tilt = 0.9;          // 移轴强弱（0 关）
uniform float bloom = 0.35;
uniform float bloom_cut = 0.72;
uniform vec3 lift : source_color = vec3(0.0);
uniform vec3 gain : source_color = vec3(1.0);
uniform float saturation = 1.0;
uniform float vignette = 0.32;
uniform float grain = 0.035;
uniform float fade = 0.0;          // 换图时压黑一下

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

vec3 soft_at(vec2 uv) {
	vec3 c = texture(soft, uv).rgb * 0.4;
	c += texture(soft, uv + vec2(soft_px.x, 0.0)).rgb * 0.15;
	c += texture(soft, uv - vec2(soft_px.x, 0.0)).rgb * 0.15;
	c += texture(soft, uv + vec2(0.0, soft_px.y)).rgb * 0.15;
	c += texture(soft, uv - vec2(0.0, soft_px.y)).rgb * 0.15;
	return c;
}

void fragment() {
	vec2 uv = UV;
	vec3 s = texture(sharp, uv).rgb;
	vec3 b = soft_at(uv);
	// 离清楚那条越远越虚；上头（远处的楼顶）虚得慢一点，下头（贴着镜头的马路）虚得快
	float d = uv.y - focus_y;
	float k = smoothstep(focus_band, focus_band + (d < 0.0 ? 0.4 : 0.3), abs(d)) * tilt;
	vec3 c = mix(s, b, k);
	// 灯晕
	vec3 hi = max(b - vec3(bloom_cut), vec3(0.0));
	c += hi * bloom * 2.2;
	// 调色
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = c * gain + lift * (1.0 - c);
	// 暗角
	vec2 v = (uv - 0.5) * vec2(1.2, 1.0);
	c *= 1.0 - vignette * smoothstep(0.35, 0.95, length(v));
	// 颗粒：每帧换
	float g = hash(uv * vec2(1931.0, 1087.0) + fract(TIME * 7.13)) - 0.5;
	c += g * grain * (1.0 - l * 0.5);
	c *= 1.0 - fade;
	COLOR = vec4(c, 1.0);
}
