shader_type spatial;
// 日漫的脸：画在头上（物体空间里头心在原点、脸朝 +Z，按经纬度算位置，放多近都不糊）。
// 眼睛：上眼线粗、眼尾带一笔，下眼线只画外半截；眼白偏一点冷；眼珠上深下浅，瞳孔、两颗高光、下半一圈透亮；
// 眼皮在眼珠上投一道影。眉毛细长。鼻子只是一小点影；嘴小。腮红是一团淡红加三道斜线（小孩、女孩重一点）。
// blink 眨眼 / smile 嘴角 / open 张嘴 / happy 笑眯眼（眼睛弯成 ∩）/ look 眼珠往哪瞟。
// 明暗和身上的 toon.gdshader 一样（赛璐璐两块），脸上的线和眼睛不受明暗影响太多（画上去的）。
render_mode cull_back, diffuse_lambert;

uniform vec3 skin : source_color = vec3(1.0, 0.89, 0.82);
uniform vec3 shade_tint : source_color = vec3(0.86, 0.68, 0.7);
uniform float band = 0.05;
uniform float soft = 0.05;
uniform float shade_floor = 1.0;
uniform float lit_k = 0.36;      // 亮面多亮（赛璐璐整块亮，比朗伯平均亮，压一点）
uniform float rim = 0.3;
uniform vec3 line_col : source_color = vec3(0.22, 0.12, 0.1);
uniform vec3 iris_dark : source_color = vec3(0.16, 0.09, 0.07);
uniform vec3 iris_light : source_color = vec3(0.62, 0.38, 0.22);
uniform vec3 brow_col : source_color = vec3(0.25, 0.16, 0.13);
uniform vec3 lip : source_color = vec3(0.78, 0.36, 0.36);
uniform vec3 blush_col : source_color = vec3(1.0, 0.55, 0.55);
uniform float eye_gap = 0.3;   // 眼睛中心离正中多远（经度，弧度）
uniform float eye_h = -0.13;   // 眼睛中心的纬度
uniform float eye_w = 0.12;    // 半宽
uniform float eye_t = 0.13;    // 半高
uniform float tilt = 0.0;      // 眼尾往上（+）还是往下（-）
uniform float lash = 0.0;      // 女孩：上眼线更粗、眼尾多一笔
uniform float iris_size = 1.0;
uniform float blush = 0.5;
uniform float age = 0.0;       // 0 小孩 … 1 老人
uniform float blink = 0.0;
uniform float happy = 0.0;
uniform float smile = 0.6;
uniform float open = 0.0;
uniform vec2 look = vec2(0.0);
uniform float paper = 0.0;
uniform float bang_lat = 0.6;   // 刘海梢在哪（纬度）：往上是刘海投在额头上的影
uniform float bang_shadow = 0.0;
uniform float crease = 1.0;     // 双眼皮

uniform float sat = 1.0;

varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

float band_line(float d, float w, float aa) {
	return 1.0 - smoothstep(w, w + aa, abs(d));
}

void fragment() {
	vec3 n = normalize(obj);
	vec2 p = vec2(atan(n.x, n.z), asin(clamp(n.y, -1.0, 1.0)));
	float aa = max(fwidth(p.x), fwidth(p.y)) * 1.1 + 1e-4;
	vec3 col = skin;
	// 刘海在额头上投的影：梢的下沿往下一点，一齿一齿的
	float jag = 0.035 * abs(sin(p.x * 17.0 + 0.6)) + 0.02 * sin(p.x * 7.0);
	float bs = smoothstep(bang_lat - 0.05 + jag - 0.02, bang_lat - 0.05 + jag + 0.01, p.y) * (1.0 - smoothstep(1.0, 1.3, abs(p.x)));
	col = mix(col, col * mix(vec3(0.86), shade_tint, 0.45), bs * bang_shadow * 0.7);
	// 腮红：外眼角下面一团淡红 + 三道细斜线
	for (int s = -1; s <= 1; s += 2) {
		float fs = float(s);
		vec2 bc = vec2(fs * (eye_gap + eye_w * 0.35), eye_h - eye_t * 1.25);
		vec2 d = (p - bc) / vec2(eye_w * 1.05, eye_t * 0.45);
		float b = 1.0 - smoothstep(0.3, 1.0, length(d));
		col = mix(col, blush_col, b * blush * 0.45);
		if (blush > 0.45) {
			for (int k = -1; k <= 1; k++) {
				vec2 q = p - (bc + vec2(fs * float(k) * eye_w * 0.32, 0.0));
				float l = band_line(q.x - fs * q.y * 0.6, 0.0035, aa) * step(abs(q.y), eye_t * 0.22);
				col = mix(col, blush_col * 0.82, l * (blush - 0.45) * 1.2);
			}
		}
	}
	float ow = eye_w * (1.0 - age * 0.12);
	float ot = eye_t * (1.0 - age * 0.3);
	for (int s = -1; s <= 1; s += 2) {
		float fs = float(s);
		vec2 c = vec2(fs * eye_gap, eye_h);
		// 眼睛自己的坐标：x 往外为正，-1…1；y 往上为正
		vec2 q = vec2((p.x - c.x) * fs / ow, (p.y - c.y) / ot);
		float qaa = aa / ot;
		float top = 0.78 - 0.5 * q.x * q.x + tilt * q.x * 0.3;
		float bot = -0.86 + 0.38 * q.x * q.x - tilt * q.x * 0.1;
		float open_k = (1.0 - blink) * (1.0 - happy);
		top = mix(bot + 0.02, top, open_k);
		float inside = step(abs(q.x), 1.0) * smoothstep(bot - qaa, bot + qaa, q.y) * (1.0 - smoothstep(top - qaa, top + qaa, q.y));
		// 眼白：上面被眼皮压出一道影
		vec3 white = vec3(0.97, 0.97, 1.0);
		white = mix(white, vec3(0.78, 0.76, 0.86), smoothstep(top - 0.45, top, q.y));
		vec3 e = white;
		// 眼珠
		vec2 ic = vec2(look.x * fs * 0.25, -0.06 + look.y * 0.12);
		vec2 iq = (q - ic) / vec2(0.5 * iris_size, 0.84 * iris_size);
		float ir = length(iq);
		float irm = 1.0 - smoothstep(1.0 - qaa * 2.0, 1.0, ir);
		vec3 icol = mix(iris_dark, iris_light, smoothstep(0.35, -0.75, iq.y));
		icol = mix(icol, iris_dark * 0.6, smoothstep(0.75, 1.0, ir));               // 外圈一道深边
		icol = mix(icol, iris_light * 1.35 + 0.05, (1.0 - smoothstep(0.0, 0.35, length((iq - vec2(0.0, -0.62)) / vec2(0.75, 0.3)))) * 0.7); // 下半透亮
		float ang = atan(iq.x, iq.y);
		icol *= 1.0 + 0.12 * sin(ang * 14.0) * smoothstep(0.35, 0.8, ir) * (1.0 - smoothstep(0.85, 1.0, ir));  // 虹膜一丝一丝
		float pup = 1.0 - smoothstep(0.85, 1.0, length(iq / vec2(0.36, 0.42)));
		icol = mix(icol, iris_dark * 0.35, pup);
		icol = mix(icol, icol * 0.55, smoothstep(top - 0.55, top - 0.05, q.y));      // 眼皮的影
		e = mix(e, icol, irm);
		// 高光：左上一大颗、右下一小颗
		float h1 = 1.0 - smoothstep(0.75, 1.0, length((q - ic - vec2(-0.16 * fs, 0.3)) / vec2(0.2, 0.24)));
		float h2 = 1.0 - smoothstep(0.7, 1.0, length((q - ic - vec2(0.17 * fs, -0.42)) / vec2(0.09, 0.09)));
		float h3 = 1.0 - smoothstep(0.6, 1.0, length((q - ic - vec2(-0.25 * fs, -0.05)) / vec2(0.05, 0.05)));
		e = mix(e, vec3(1.0), clamp(h1 + h2 * 0.85 + h3 * 0.7, 0.0, 1.0) * irm);
		col = mix(col, e, inside * step(0.2, open_k));
		// 上眼线：粗，眼尾往外多拖一截、往下（或往上）一笔
		float lw = (0.09 + lash * 0.05) * (0.7 + 0.5 * smoothstep(-0.6, 1.0, q.x));
		float top_line = band_line(q.y - top - lw * 0.6, lw, qaa) * step(-1.05, q.x) * step(q.x, 1.12);
		float flick = band_line(q.y - (top - 0.12 - (q.x - 1.0) * 0.9), 0.05 + lash * 0.03, qaa) * step(0.9, q.x) * step(q.x, 1.3 + lash * 0.15);
		// 下眼线：只画外半截，细
		float bot_line = band_line(q.y - bot + 0.02, 0.035, qaa) * smoothstep(0.1, 0.4, q.x) * step(q.x, 0.95);
		float lines = max(max(top_line, flick * open_k), bot_line * open_k);
		// 闭眼 / 笑眯眼：一道弯线（笑眯是 ∩，闭眼是 ∪）
		float arc_y = happy > 0.5 ? -0.05 + 0.45 * (1.0 - q.x * q.x) : -0.25 - 0.25 * (1.0 - q.x * q.x);
		float shut = band_line(q.y - arc_y, 0.07, qaa) * step(abs(q.x), 1.0) * step(0.5, max(blink, happy));
		lines = mix(lines, shut, step(0.5, max(blink, happy)));
		col = mix(col, line_col, lines);
		// 双眼皮：上眼线上面一道淡线，外半截
		float cr = band_line(q.y - (top + 0.3 - 0.06 * q.x * q.x), 0.028, qaa) * smoothstep(-0.4, 0.0, q.x) * step(q.x, 0.95) * open_k;
		col = mix(col, mix(skin, line_col, 0.55), cr * crease);
		// 眼尾的两小撮睫毛
		for (int k = 0; k < 2; k++) {
			float fk = float(k);
			float x0 = 0.72 + fk * 0.22;
			float lx = q.x - x0;
			float ly = q.y - (top + lw * 0.8 + lx * (0.9 + fk * 0.5));
			float tuft = band_line(ly, 0.045 * (1.0 - clamp(lx / 0.28, 0.0, 1.0)), qaa) * step(0.0, lx) * step(lx, 0.28);
			col = mix(col, line_col, tuft * lash * open_k);
		}
		// 眉毛：细长，里头略高
		float bx = q.x;
		float by = 1.75 + 0.22 * (1.0 - bx * bx) + 0.12 * (-bx) * 0.5 - age * 0.1;
		float bw = 0.07 * (1.0 - smoothstep(0.3, 1.2, abs(bx)) * 0.5);
		float brow = band_line(q.y - by, bw, qaa) * step(-0.95, bx) * step(bx, 1.15);
		col = mix(col, brow_col, brow * 0.9);
		// 老了：眼尾两道细纹
		if (age > 0.5) {
			float wr = band_line(q.y - (q.x - 1.25) * 0.5, 0.03, qaa) * step(1.15, q.x) * step(q.x, 1.5);
			col = mix(col, col * 0.8, wr * (age - 0.5) * 1.6);
		}
	}
	// 鼻子：鼻尖下一小块影 + 鼻梁一点高光（日漫只点一下）
	vec2 nc = vec2(0.0, eye_h - eye_t * 1.6);
	float nd = length((p - nc - vec2(0.012, -0.004)) / vec2(0.016, 0.009));
	col = mix(col, col * shade_tint * 0.95, (1.0 - smoothstep(0.4, 1.0, nd)) * 0.75);
	float nh = length((p - nc - vec2(-0.008, 0.03)) / vec2(0.006, 0.02));
	col = mix(col, col * 1.08 + 0.03, (1.0 - smoothstep(0.5, 1.0, nh)) * 0.6);
	// 嘴：小小一道弧；张嘴是个圆角的小口子，下面一点舌头
	vec2 mc = vec2(0.0, eye_h - eye_t * 2.45);
	float mx = (p.x - mc.x) / 0.07;
	float my = mc.y + smile * 0.018 * (mx * mx - 0.5);
	float mline = band_line(p.y - my, 0.006, aa) * step(abs(mx), 1.0);
	vec2 mo = (p - mc - vec2(0.0, -0.012)) / vec2(0.045, 0.04 * open + 0.001);
	float om = (1.0 - smoothstep(0.85, 1.0, length(mo))) * step(0.05, open);
	vec3 mouth_in = mix(lip * 0.55, lip * 1.1, smoothstep(0.1, -0.7, mo.y));
	col = mix(col, line_col * 1.4, mline * (1.0 - step(0.05, open)));
	// 下唇一点淡淡的红
	float ll = length((p - mc - vec2(0.0, -0.022)) / vec2(0.03, 0.01));
	col = mix(col, mix(col, lip, 0.35), (1.0 - smoothstep(0.3, 1.0, ll)) * (1.0 - step(0.05, open)));
	col = mix(col, mouth_in, om);
	// 脸的边上（腮、下颌、额角）往里暗一点、偏暖：脸是圆的，不是一张白纸
	float fr = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	col = mix(col, col * mix(vec3(0.92), shade_tint, 0.6), smoothstep(0.35, 0.8, fr) * 0.55);
	// 下巴底下
	col = mix(col, col * shade_tint, smoothstep(-0.55, -0.95, p.y) * 0.5);
	if (paper > 0.0) {
		col *= 1.0 + (fract(sin(dot(floor(p * 400.0), vec2(12.9, 78.2))) * 43758.5) - 0.5) * 0.04 * paper;
	}
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(vec3(l), col, sat);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float sh = smoothstep(0.35, 0.65, ATTENUATION);
	float lit = smoothstep(band - soft, band + soft, ndl) * sh;
	vec3 lc = LIGHT_COLOR / PI;
	vec3 dark = LIGHT_IS_DIRECTIONAL ? shade_tint * shade_floor * 0.55 * lit_k : vec3(0.0);
	// 脸比身上亮一点：暗面不压太深，五官才看得清
	DIFFUSE_LIGHT += lc * mix(mix(dark, vec3(lit_k), 0.25), vec3(lit_k), lit);
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	SPECULAR_LIGHT += lc * smoothstep(0.6, 0.8, fres) * lit * rim * 0.5;
}
