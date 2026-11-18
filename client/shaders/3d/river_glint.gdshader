shader_type spatial;
// 水里灯的倒影（只给 river3d 用）：平铺在水面上、朝镜头拉长的一条条光，被波纹揉成一截一截、左右晃。
// 一条一个四边形，UV.x 横着（0..1），UV.y 从灯脚（0）往镜头这边（1）；顶点色 rgb 是灯的颜色、a 是一条一个随机数。
// 天黑才有（g_night）；结冰了几乎没有（冰面是糙的）。叠加混合，不写深度，不吃雾。
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

global uniform float g_night;
global uniform float g_snow;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float seed = COLOR.a * 50.0;
	float v = UV.y;
	float t = TIME;
	// 左右晃：越往镜头这边晃得越开
	float wob = sin(wpos.z * 1.7 + t * 1.6 + seed) * 0.16 + sin(wpos.z * 4.3 - t * 2.4 + seed * 1.7) * 0.09;
	float u = (UV.x - 0.5) * 2.0 + wob * (0.4 + v);
	float across = exp(-u * u * 5.0);
	// 一截一截：波峰把光打断
	float dash = sin(wpos.z * 5.5 + t * 2.2 + seed + sin(wpos.z * 1.3 + t) * 2.0) * 0.5 + 0.5;
	dash = smoothstep(0.25, 0.75, dash) * 0.75 + 0.25;
	// 灯脚最亮，往镜头这边渐渐没了
	float along = smoothstep(0.0, 0.06, v) * pow(1.0 - v, 1.4);
	float on = smoothstep(0.35, 0.7, g_night) * (1.0 - smoothstep(0.25, 0.33, g_snow) * 0.85);
	ALBEDO = COLOR.rgb * across * dash * along * on * 1.6;
}
