shader_type spatial;
// 脚底、桌底的接触阴影：一块软的暗斑压在地面上（没有 SSAO，靠它把东西放稳）。
// 用普通的透明混合：gl_compatibility 下 blend_mul 的面片在 HDR/曝光之后会整块发黑。
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float strength = 0.45;

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	float k = 1.0 - smoothstep(0.15, 1.0, r);
	ALBEDO = vec3(0.03, 0.025, 0.03);
	ALPHA = strength * k * k;
}
