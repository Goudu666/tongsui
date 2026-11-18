shader_type spatial;
// 日漫手办的脸：画在头上（物体空间里头心在原点、脸朝 +Z，按经纬度算位置，放多近都不糊）。
// 皮肤：暖的桃色，明暗是一大片柔的渐变（像手涂的 PVC 手办），明暗交界上一道暖红（皮肤透光），暗面偏玫瑰、
//       环境光那一点偏冷；脸颊一团淡红，脸边、下巴底下暖一点暗一点（脸是圆的，不是一张白纸）。
// 眼睛（最要紧）：上眼线粗、眼尾带一小笔翘；梅多几根睫毛；下眼线淡、只画外半截；眼白偏冷、上面一道眼皮的影；
//       眼珠大，上深下亮，瞳孔、下半一圈透亮、两三颗高光；双眼皮一道细线，眼皮上一层淡淡的暖影。眉毛细，跟头发颜色。
// 鼻子只点一下（一小块影 + 一点高光）；嘴小，下唇一点淡红，张嘴是个圆角的小口子。
// blink 眨眼 / smile 嘴角 / open 张嘴 / happy 笑眯眼（眼睛弯成 ∩）/ look 眼珠往哪瞟（动画设）。
// bang_lat / bang_shadow：刘海在额头上投的影（头发那边设）。
render_mode cull_back, diffuse_lambert;

uniform vec3 skin : source_color = vec3(1.0, 0.86, 0.77);
uniform vec3 shade_tint : source_color = vec3(0.92, 0.66, 0.66);  // 暗面 = 皮肤 × 这个（玫瑰色）
uniform vec3 sss_col : source_color = vec3(1.0, 0.42, 0.32);      // 明暗交界那道透光的暖红
uniform float sss = 0.3;
uniform float band = -0.1;
uniform float soft = 0.3;
uniform float shade_floor = 1.0;
uniform float lit_k = 0.36;      // 亮面多亮（和身上 toon 一样，压一点，别比街上亮）
uniform float rim = 0.3;
uniform vec3 line_col : source_color = vec3(0.16, 0.08, 0.07);
uniform vec3 iris_dark : source_color = vec3(0.16, 0.09, 0.07);
uniform vec3 iris_light : source_color = vec3(0.62, 0.38, 0.22);
uniform vec3 brow_col : source_color = vec3(0.25, 0.16, 0.13);
uniform vec3 lip : source_color = vec3(0.86, 0.42, 0.42);
uniform vec3 blush_col : source_color = vec3(1.0, 0.5, 0.48);
uniform float eye_gap = 0.36;  // 眼睛中心离正中多远（经度，弧度）
uniform float eye_h = -0.15;   // 眼睛中心的纬度
uniform float eye_w = 0.19;    // 半宽
uniform float eye_t = 0.21;    // 半高
uniform float tilt = 0.0;      // 眼尾往上（+）还是往下（-）
uniform float lash = 0.0;      // 0 男孩（眼线粗、不画睫毛）… 1 女孩（眼尾几根睫毛、眼线带翘）
uniform float iris_size = 1.0;
uniform float blush = 0.5;
uniform float age = 0.0;       // 0 小孩 … 1 老人
uniform float brow_arch = 0.2; // 眉毛弯多少（女孩弯、男孩平）
uniform float brow_w = 1.0;    // 眉毛粗细
uniform float nose_h = -0.5;   // 鼻尖的纬度
uniform float mouth_h = -0.68; // 嘴的纬度
uniform float mouth_w = 0.07;  // 嘴半宽（经度）
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

float blob(vec2 d, float lo) {
	return 1.0 - smoothstep(lo, 1.0, length(d));
}

// 鼻子的小鼓包（高度，按头的半径算）：从两眼之间淡淡起来，到鼻尖最高，下面很快收回去。只改法线，不改网格。
float nose_bump(vec2 p) {
	float ramp = smoothstep(nose_h + 0.3, nose_h + 0.015, p.y) * (1.0 - smoothstep(nose_h + 0.005, nose_h - 0.045, p.y));
	float w = mix(0.035, 0.05, smoothstep(nose_h + 0.2, nose_h, p.y));
	return 0.035 * ramp * exp(-(p.x * p.x) / (w * w));
}

void fragment() {
	vec3 n = normalize(obj);
	vec2 p = vec2(atan(n.x, n.z), asin(clamp(n.y, -1.0, 1.0)));
	float aa = max(fwidth(p.x), fwidth(p.y)) * 1.1 + 1e-4;
	vec3 sk = skin;
	vec3 col = sk;
	vec3 shade = sk * shade_tint;
	// 鼻子：把法线按小鼓包掰一下，光照到鼻子上就有一面亮一面暗（像捏出来的）
	{
		vec3 east = normalize(vec3(n.z, 0.0, -n.x) + vec3(1e-5, 0.0, 0.0));
		vec3 north = cross(n, east);
		float e = 0.004;
		float gx = (nose_bump(p + vec2(e, 0.0)) - nose_bump(p - vec2(e, 0.0))) / (2.0 * e);
		float gy = (nose_bump(p + vec2(0.0, e)) - nose_bump(p - vec2(0.0, e))) / (2.0 * e);
		vec3 ev = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(east, 0.0))).xyz);
		vec3 nv = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(north, 0.0))).xyz);
		NORMAL = normalize(NORMAL - (gx * ev + gy * nv) * 0.9);
	}
	// 手办上色：额头、鼻梁一带稍亮，脸边上晕一层暖暖的暗，往下巴稍暗（上面来的光）
	float fr = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	col = mix(col, sk * vec3(0.94, 0.83, 0.81), smoothstep(0.25, 0.85, fr) * 0.6);
	col *= 1.0 + 0.05 * (1.0 - smoothstep(0.0, 0.55, length(p - vec2(0.0, 0.2))));
	col *= mix(1.0, 0.93, smoothstep(-0.35, -1.0, p.y));
	// 刘海在额头上投的影：梢的下沿往下一点，一齿一齿的，边软
	float jag = 0.035 * abs(sin(p.x * 17.0 + 0.6)) + 0.02 * sin(p.x * 7.0);
	float bs = smoothstep(bang_lat - 0.1 + jag - 0.06, bang_lat - 0.05 + jag + 0.04, p.y) * (1.0 - smoothstep(1.0, 1.3, abs(p.x)));
	col = mix(col, mix(col, shade, 0.75) * vec3(0.97, 0.95, 1.0), bs * bang_shadow * 0.6);
	// 腮红：眼睛下面偏外一团淡红，边很软
	for (int s = -1; s <= 1; s += 2) {
		float fs = float(s);
		vec2 bc = vec2(fs * (eye_gap + eye_w * 0.2), eye_h - eye_t * 1.45);
		float b = blob((p - bc) / vec2(eye_w * 1.25, eye_t * 0.62), 0.0);
		col = mix(col, col * blush_col * 1.05, b * b * blush * 0.55);
		// 一道细细的斜线（小孩、女孩有，淡）
		if (blush > 0.5) {
			for (int k = 0; k < 3; k++) {
				vec2 q = p - (bc + vec2(fs * (float(k) - 1.0) * eye_w * 0.3, 0.0));
				float l = band_line(q.x - fs * q.y * 0.55, 0.003, aa) * step(abs(q.y), eye_t * 0.18);
				col = mix(col, col * blush_col * 0.92, l * (blush - 0.5) * 0.9);
			}
		}
	}
	float ow = eye_w * (1.0 - age * 0.08);
	float ot = eye_t * (1.0 - age * 0.28);
	float open_k = (1.0 - smoothstep(0.15, 0.5, blink)) * (1.0 - happy);
	float shut_on = step(0.5, max(blink, happy));
	for (int s = -1; s <= 1; s += 2) {
		float fs = float(s);
		vec2 c = vec2(fs * eye_gap, eye_h);
		// 眼睛自己的坐标：x 往外为正（-1 内眼角 … 1 外眼角），y 往上为正（-1…1）
		vec2 q = vec2((p.x - c.x) * fs / ow, (p.y - c.y) / ot);
		float qaa = aa / ot;
		float x2 = q.x * q.x;
		// 上眼皮：上边平一点，内眼角低、外眼角按 tilt 翘或垂；老了眼尾往下耷一点
		float top_peak = 0.84;
		float ti = tilt - age * 0.12;
		float top = top_peak - (0.66 - 0.12 * ti) * (0.55 * x2 + 0.45 * x2 * x2) + (0.08 + 0.13 * ti) * q.x;
		float bot = -0.86 + (0.9 + 0.1 * ti) * (0.35 * x2 + 0.65 * x2 * x2) + (0.05 + 0.1 * ti) * q.x;
		bot += smoothstep(0.4, 1.0, age) * 0.28 * (1.0 - x2);  // 老了下眼皮微微往上弯：眼睛带笑、和气
		float top_o = top;
		top = mix(bot + 0.02, top, open_k);
		float inside = step(abs(q.x), 1.0) * smoothstep(bot - qaa, bot + qaa, q.y) * (1.0 - smoothstep(top - qaa, top + qaa, q.y));
		// 眼皮上一层淡淡的暖影（像手办眼窝上的那层晕）
		float lid = smoothstep(1.6, 0.6, q.y - top_o) * step(0.0, q.y - top_o) * smoothstep(1.35, 0.7, abs(q.x));
		col = mix(col, col * mix(shade_tint, vec3(0.9, 0.62, 0.6), 0.5), lid * 0.32 * (1.0 - shut_on * 0.5));
		// 眼白：偏一点冷，上面被眼皮压出一道影
		vec3 white = vec3(0.98, 0.97, 0.98);
		white = mix(white, vec3(0.7, 0.7, 0.84), smoothstep(top - 0.55, top - 0.05, q.y));
		white = mix(white, vec3(0.88, 0.86, 0.92), smoothstep(0.6, 1.0, abs(q.x)) * 0.6);
		vec3 e = white;
		// 眼珠：大，上头被眼皮盖掉一截
		vec2 ic = vec2(look.x * fs * 0.28, -0.06 + look.y * 0.14);
		vec2 iq = (q - ic) / vec2(0.54 * iris_size, 0.94 * iris_size);
		float ir = length(iq);
		float irm = 1.0 - smoothstep(1.0 - qaa * 2.5, 1.0, ir);
		float g = smoothstep(0.75, -0.85, iq.y);
		vec3 icol = mix(iris_dark, iris_light, g * g * (3.0 - 2.0 * g));
		// 中间一圈稍亮（虹膜的纹）
		float ang = atan(iq.x, iq.y);
		icol *= 1.0 + 0.1 * sin(ang * 13.0 + 1.0) * smoothstep(0.4, 0.75, ir) * (1.0 - smoothstep(0.8, 0.95, ir));
		// 下半一弯透亮的光（眼珠里的反光）
		float cres = smoothstep(0.35, 0.72, ir) * (1.0 - smoothstep(0.78, 0.95, ir)) * smoothstep(-0.15, -0.65, iq.y);
		icol = mix(icol, iris_light * 1.45 + vec3(0.06), cres * 0.75);
		// 外圈一道深边
		icol = mix(icol, iris_dark * 0.45, smoothstep(0.8, 0.98, ir));
		// 瞳孔：竖的小椭圆，偏上
		float pup = 1.0 - smoothstep(0.82, 1.0, length((iq - vec2(0.0, 0.08)) / vec2(0.3, 0.4)));
		icol = mix(icol, iris_dark * 0.25, pup * 0.92);
		// 眼皮的影压在眼珠上半
		icol = mix(icol, icol * 0.42, smoothstep(top - 0.75, top - 0.08, q.y));
		icol = mix(icol, icol * 0.62, smoothstep(0.04, 0.16, qaa));  // 远了眼珠压深一点，眼睛立得住
		e = mix(e, icol, irm);
		// 高光：同一边（光从同一个方向来）：一大颗、一小颗、一点
		vec2 hq = q - ic;
		float h1 = blob((hq - vec2(-0.2 * fs, 0.3)) / vec2(0.2, 0.25), 0.7);
		float h2 = blob((hq - vec2(0.2 * fs, -0.45)) / vec2(0.1, 0.09), 0.6);
		float h3 = blob((hq - vec2(0.12 * fs, 0.42)) / vec2(0.06, 0.06), 0.5);
		e = mix(e, vec3(1.0), clamp(h1 + h2 * 0.85 + h3 * 0.75, 0.0, 1.0) * irm);
		col = mix(col, e, inside * step(0.05, open_k));
		// 上眼线：粗，往外越来越粗，眼尾拖出去一小笔（翘）
		float lw = (0.1 + lash * 0.035) * (0.45 + 0.75 * smoothstep(-0.9, 0.9, q.x));
		lw = max(lw, qaa * 0.9);  // 离得远（街上脸只有三四十像素）：眼线至少一个多像素粗，眼睛才不糊成一片
		float top_line = band_line(q.y - top - lw * 0.55, lw, qaa) * step(-1.04, q.x) * step(q.x, 1.0);
		float wx = q.x - 1.0;
		float top1 = top_peak - (0.66 - 0.12 * ti) + (0.08 + 0.13 * ti);  // 外眼角那一点（翘的那一笔从这儿往外拖，不跟着曲线往下栽）
		float wing_y = mix(bot, top1, open_k) + 0.03 - wx * (0.45 - lash * 0.32);
		float wing = band_line(q.y - wing_y - lw * 0.3, lw * (1.0 - smoothstep(0.0, 0.32 + lash * 0.1, wx)), qaa) * step(0.0, wx) * step(wx, 0.32 + lash * 0.1);
		// 下眼线：淡、细，只画外半截，眼尾和上眼线接上
		float bot_line = band_line(q.y - bot + 0.03, 0.032 + 0.015 * smoothstep(0.4, 1.0, q.x), qaa) * smoothstep(-0.1, 0.45, q.x) * step(q.x, 1.0);
		vec3 lc_soft = mix(line_col, sk * vec3(0.7, 0.45, 0.42), 0.45);
		float lines = max(top_line, wing * open_k);
		// 闭眼 / 笑眯眼：一道弯线（笑眯是 ∩，闭眼是 ∪），线带一点睫毛的尾巴
		float arc_y = happy > 0.5 ? -0.12 + 0.5 * (1.0 - x2) : -0.3 - 0.22 * (1.0 - x2);
		float shut = band_line(q.y - arc_y, 0.075 * (0.6 + 0.5 * smoothstep(-0.8, 0.9, q.x)), qaa) * step(abs(q.x), 1.02);
		lines = mix(lines, shut, shut_on);
		col = mix(col, lc_soft, bot_line * open_k * 0.85);
		col = mix(col, line_col, lines);
		// 双眼皮：上眼线上面一道淡线（外三分之二）
		float cr_y = top_o + 0.3 + 0.08 * (1.0 - x2) + age * 0.08;
		float cr = band_line(q.y - cr_y, 0.025, qaa) * smoothstep(-0.5, 0.0, q.x) * step(q.x, 0.98) * open_k;
		col = mix(col, mix(sk, line_col, 0.5), cr * crease);
		// 睫毛：眼尾往外上方散开的几根（女孩）
		for (int k = 0; k < 3; k++) {
			float fk = float(k);
			float x0 = 0.55 + fk * 0.2;
			float lx = q.x - x0;
			float base_y = top_peak - (0.66 - 0.12 * ti) * (0.55 * x0 * x0 + 0.45 * x0 * x0 * x0 * x0) + (0.08 + 0.13 * ti) * x0 + lw * 0.9;
			float len = 0.24 + fk * 0.04;
			float ly = q.y - (base_y + lx * (0.9 + fk * 0.45) * 1.0 + lx * lx * 0.0);
			float tuft = band_line(ly, 0.045 * (1.0 - clamp(lx / len, 0.0, 1.0)), qaa) * step(0.0, lx) * step(lx, len);
			col = mix(col, line_col, tuft * smoothstep(0.3, 0.9, lash) * open_k);
		}
		// 眉毛：细，内头略粗、往外收尖；跟头发一个颜色
		float bx = q.x;
		float by = top_peak + 0.95 + brow_arch * (1.0 - bx * bx) - 0.1 * bx - age * 0.06;
		float bw = max(0.075 * brow_w * (1.0 - smoothstep(-0.6, 1.2, bx) * 0.55), qaa * 0.6);
		float brow = band_line(q.y - by, bw, qaa) * smoothstep(-1.0, -0.88, bx) * (1.0 - smoothstep(1.05, 1.2, bx));
		col = mix(col, brow_col, brow * 0.92);
		// 中年以后：眼睛下面一道很淡的卧蚕线；老了眼尾两三道笑纹
		float und = band_line(q.y - (bot - 0.32 - 0.05 * (1.0 - x2)), 0.025, qaa) * smoothstep(-0.3, 0.2, q.x) * (1.0 - smoothstep(0.6, 0.95, q.x));
		col = mix(col, col * shade_tint, und * smoothstep(0.3, 0.6, age) * 0.6);
		if (age > 0.5) {
			for (int k = 0; k < 3; k++) {
				float fk = float(k) - 1.0;
				float wy = q.y - (0.05 + fk * 0.28) - (q.x - 1.2) * fk * 0.3;
				float wr = band_line(wy, 0.028, qaa) * smoothstep(1.12, 1.22, q.x) * (1.0 - smoothstep(1.4, 1.55 - abs(fk) * 0.08, q.x));
				col = mix(col, col * shade_tint * 0.88, wr * (age - 0.5) * 2.2);
			}
		}
	}
	// 鼻子：鼻尖下一小块影（偏一边）+ 鼻尖一点高光（日漫只点一下）
	vec2 nc = vec2(0.0, nose_h);
	// 离得远（街上一张脸三四十像素）：鼻影、唇下影都淡掉，嘴只留一道淡淡的粉线，不然糊成一个「o」像在吃惊
	float far = smoothstep(0.006, 0.03, aa);
	float nd = blob((p - nc - vec2(0.014, -0.006)) / vec2(0.02, 0.011), 0.2);
	col = mix(col, col * shade_tint * 0.92, nd * 0.7 * (1.0 - far));
	float nh = blob((p - nc - vec2(-0.006, 0.012)) / vec2(0.01, 0.012), 0.3);
	col = mix(col, col * 1.06 + vec3(0.03), nh * 0.5);
	// 嘴：小小一道弧，嘴角按 smile 往上；下唇一点淡红、下面一点影
	float mx = p.x / mouth_w;
	float my = mouth_h + smile * 0.02 * (mx * mx - 0.4);
	float lip_area = blob((p - vec2(0.0, mouth_h - 0.02)) / vec2(mouth_w * 0.75, 0.022), 0.0);
	col = mix(col, col * lip * 1.12, lip_area * 0.35 * (1.0 - 0.5 * far));
	float under = blob((p - vec2(0.0, mouth_h - 0.05)) / vec2(mouth_w * 0.45, 0.012), 0.2);
	col = mix(col, col * shade_tint, under * 0.4 * (1.0 - step(0.05, open)) * (1.0 - far));
	float mline = band_line(p.y - my, max(0.0065 * (1.0 - 0.55 * mx * mx), aa * 0.5), aa) * step(abs(mx), 1.0);
	vec3 mcol = mix(line_col, lip * 0.55, 0.45);
	col = mix(col, mix(mcol, col * lip * 0.85, far), mline * (1.0 - step(0.05, open)) * (1.0 - 0.45 * far));
	// 张嘴：上沿就是带笑的嘴线（宽、平），下沿圆（D 字形，笑着张嘴）；里面深红，下面一点舌头，大张时上面一道牙
	float oh = 0.058 * open + 0.002;
	float xo = p.x / (mouth_w * (0.9 + 0.35 * smile));
	float dep = oh * pow(max(1.0 - pow(abs(xo), 2.4), 0.0), 0.55);
	float yy = my - p.y;
	float on = step(0.05, open) * step(abs(xo), 1.0);
	float om = smoothstep(-aa * 0.5, aa * 0.5, yy) * (1.0 - smoothstep(dep - aa, dep, yy)) * on;
	float v = yy / max(dep, 1e-4);
	vec3 mouth_in = mix(lip * 0.36, lip * 0.92, smoothstep(0.5, 0.95, v));
	mouth_in = mix(mouth_in, vec3(0.97, 0.95, 0.93), (1.0 - smoothstep(0.14, 0.24, v)) * step(0.45, open));
	col = mix(col, mouth_in, om);
	float orim = (1.0 - smoothstep(aa * 0.4, aa * 1.4, abs(yy - dep))) * step(0.0, yy) * on;
	col = mix(col, mcol, max(orim * 0.6, band_line(yy, max(0.004, aa * 0.5), aa) * on));
	// 下巴底下暖一点暗一点
	col = mix(col, shade, smoothstep(-0.75, -1.15, p.y) * 0.45);
	if (paper > 0.0) {
		col *= 1.0 + (fract(sin(dot(floor(p * 400.0), vec2(12.9, 78.2))) * 43758.5) - 0.5) * 0.04 * paper;
	}
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(vec3(l), col, mix(1.0, sat, 0.5));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float sh = mix(0.25, 1.0, smoothstep(0.25, 0.75, ATTENUATION));
	float lit = smoothstep(band - soft, band + soft, ndl);
	vec3 lc = LIGHT_COLOR / PI;
	if (LIGHT_IS_DIRECTIONAL) {
		// 暗面：玫瑰色的一层（不是灰）；亮面：本身也有一点由暗到亮的渐变（像手涂的）
		vec3 dark = shade_tint * shade_floor * 0.55 * lit_k;
		vec3 bright = vec3(lit_k) * mix(0.8, 1.03, smoothstep(0.05, 0.95, ndl));
		vec3 d = mix(dark, bright, lit * sh);
		// 明暗交界那一道透出来的暖红（皮肤的 subsurface）
		float term = exp(-pow((ndl - band) / (soft * 0.9 + 0.05), 2.0));
		d += sss_col * term * sss * lit_k * mix(0.5, 1.0, sh);
		DIFFUSE_LIGHT += lc * d;
	} else {
		// 路灯这类点光只照亮面（和身上一样）
		DIFFUSE_LIGHT += lc * vec3(lit_k) * lit * sh;
	}
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	SPECULAR_LIGHT += lc * vec3(1.0, 0.92, 0.86) * smoothstep(0.62, 0.85, fres) * lit * sh * rim * 0.45;
	// 手办漆面那一点点柔光（脸颊、鼻梁上一层很淡的亮，不是油光）
	vec3 hv = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += lc * vec3(1.0, 0.95, 0.9) * pow(max(dot(NORMAL, hv), 0.0), 18.0) * 0.035 * lit * sh * lit_k / 0.36;
}
