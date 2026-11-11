extends Control
## 河畔里的 HUD（横屏）。全部自己画，垫着纸片，压在地图上也看得清。
## 构图是「对门」：我的东西靠左，对门的靠右，中间留给河畔里。
## 11-11 重做：三块纸，左「我」、中「关口」、右「对门」，一样的上沿、一样的色条高、一样的线。
##   左上「我」的牌：色条（节气 / 学期）→ 年纪大字 + 钟点（太阳 / 月亮）→ 三个圆表（饱腹、精力、心情，
##         低了变梅红并且抖一下）→ 成长账（stat_strip.gd 画字）。一张纸，细线分三截
##   中上：下一个关口的纸带（goal_panel.gd，main.gd 按 strip_rect() 摆）；
##         纸带底下两张小签：零花钱，主线（第几章，今天的「下一件事」在哪张图、哪一段）
##   右上「对门」的牌：色条是 TA 的颜色；左边两个圆，越亲近叠得越多；右边 TA 在哪、在做什么
##   左边「我」的牌底下：有孩子时一张小牌（名字、几岁，一行三项；两口子共用的标「两家的」）
##   屏幕边上：对门走出画面时，一个 TA 颜色的小箭头指着方向
## 刘海和圆角在左右两边，inset 是要让开的宽度（Kit.safe_sides）。

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")
const Icons := preload("res://scripts/ui/icons.gd")
const NEED_KEYS := ["hunger", "energy", "mood"]  ## 清洁 11-11 砍了（#47；旧服务器还会发，不画）
const NEED_GLYPH := {"hunger": "饱", "energy": "精", "mood": "心", "clean": "净"}
const STAGE_NAME := {"childhood": "童年", "teen": "少年", "young": "青年", "middle": "中年", "old": "老年"}

const LOW := 30.0          ## 需求低于这个数：圆表变梅红并抖动
const TOP := 28.0          ## 顶上那条横带的上沿
const SIDE := 32.0         ## 离屏幕左右边的距离（再加上 inset）
const GAP := 20.0          ## 三块之间的空
const BAND := 48.0         ## 牌子顶上色条的高
## 左上「我」的牌：色条 + 年纪钟点 → 三个圆表 → 成长账（stat_strip.gd 画字，框是这里画的）
const ME_W := 352.0
const AGE_H := 92.0
const NEEDS_H := 88.0
const STATS_H := 60.0
## 右上「对门」的牌：色条 + 左边两个圆 / 右边 TA 在做什么
const THEM_W := 448.0
const BOND_W := 128.0
const THEM_H := 160.0
const STRIP_H := 112.0     ## 关口纸带的高
const STRIP_MAX := 1280.0  ## 关口纸带最宽这么多（再长尺子就空了）
const TAG_H := 44.0        ## 纸带底下的小签（零花钱、主线）
## 「我」的牌底下：孩子的小牌（WORLD actors[我].kid，见 docs/FAMILY.md）
const KID_GAP := 16.0
const KID_H := 96.0
const CARD := Vector2(ME_W, BAND + AGE_H)  ## 只有日历那一截（离线逛逛时就这么高）
const CLOCK_FS := 36
const CHAPTER_NUM := ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

var time_label := ""    ## LifeTime.at().label，例如 "7 岁 · 立夏"
var stage := "childhood"
var minute := 390.0
var slot_name := ""     ## 一天五段里的哪一段（早上 / 上午……）。日历牌上现在一直写钟点（一件一件做，钟是自己的），这个留给别处用
var playing := false
var tag := ""           ## 日历牌色条上额外的一个词（上学日、预览）
var note := ""          ## 日历牌底下的一行小字（网络延迟）
var needs: Dictionary = {}
var money := -1
var bond: Dictionary = {}
var partner: Dictionary = {}  ## 对门的牌 { name, color, online, big, small }；空的不画（离线逛逛）
var pointer: Dictionary = {}  ## 对门走出画面了 { at: 屏幕上贴边的位置, dir: 方向, color, name }；在画面里是空的
var inset := Vector2.ZERO     ## (左, 右) 给刘海让开的宽度
var story: Dictionary = {}    ## 主线 { chapter, title, next, force }（WORLD 的 story，next 是我这一句）；空的不画
var kid: Dictionary = {}      ## 我的孩子 { name, age, stats: {body, mind, charm}（0~10）, shared }；没孩子是空的
var story_rect := Rect2()     ## 主线小签上一回画在哪（开局引导的纸条贴在它底下）
var money_rect := Rect2()     ## 零花钱那一小块上一回画在哪（飘字的钢镚儿往这儿飞，ui/juice.gd）
var _money_shown := -1.0      ## 零花钱正在显示的数：钢镚儿落下来才拨上去
var _money_hold := 0.0
var _bump := 0.0              ## 亲近 / 默契刚涨：两个圆往一块儿挤一下
var _kid_hold := 0.0          ## 孩子牌上的数先别拨（「孩子 心智 +3」还在路上）
var _kid_held: Dictionary = {} ## 拨之前显示的那份 stats
var _kid_bump := 0.0          ## 飘字落进孩子牌：牌子跳一下
var _kid_hot := ""            ## 刚落进来的是哪一项（那一项的数印成我的颜色，一会儿褪回墨色）
var _shown: Dictionary = {}   ## 圆表上正在显示的值（慢慢追上真实值）
var _t := 0.0
var _idle := 0.0
var _sig: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 只在有东西在动时每帧重画：圆表还在追数、有需求见底在抖、显示的内容变了。
## 其余时候一秒画十次，够两个圆慢慢呼吸。
func _process(delta: float) -> void:
	_t += delta
	_idle += delta
	var moving := false
	for k in needs:
		var target := float(needs[k])
		var cur := float(_shown.get(k, target))
		if absf(cur - target) > 0.05:
			cur = lerpf(cur, target, 1.0 - exp(-6.0 * delta))
			moving = true
		else:
			cur = target
		_shown[k] = cur
		if target < LOW:
			moving = true
	if money >= 0 and (_money_shown < 0.0 or money < _money_shown - 0.5):
		_money_shown = float(money)  # 头一回、花了钱：直接到位
	elif money >= 0 and absf(_money_shown - money) > 0.01 and _t >= _money_hold:
		_money_shown = move_toward(_money_shown, float(money), maxf(1.0, absf(money - _money_shown) * 5.0) * delta)
		moving = true
	if _bump > 0.0:
		_bump = maxf(0.0, _bump - delta)
		moving = true
	if _kid_bump > 0.0:
		_kid_bump = maxf(0.0, _kid_bump - delta)
		moving = true
	if not _kid_held.is_empty() and _t >= _kid_hold:
		_kid_held = {}
		moving = true
	var sig := [time_label, stage, int(minute), slot_name, playing, tag, note, money, bond.hash(), partner.hash(), pointer.hash(), story.hash(), kid.hash(), inset, size]
	if moving or _idle >= 0.1 or sig != _sig:
		_sig = sig
		_idle = 0.0
		queue_redraw()


## 零花钱先别拨（钢镚儿还在路上）
func hold_money(sec: float) -> void:
	_money_hold = _t + sec


## 亲近、默契涨了：两个圆挤一下
func bump() -> void:
	_bump = 0.45


## 孩子牌上的数先停在现在显示的样子，sec 秒后再拨（飘字飞到了 kid_land 会提前放开）
func hold_kid(sec: float) -> void:
	if _kid_held.is_empty():
		_kid_held = _dict(kid.get("stats")).duplicate()
	_kid_hold = maxf(_kid_hold, _t + sec)


## 「孩子 心智 +3」落进孩子牌：数拨上去，牌子跳一下
func kid_land(key: String) -> void:
	_kid_held = {}
	_kid_bump = 0.4
	_kid_hot = key


## 孩子那张小牌在 HUD 里的位置（没孩子是空的；飘字「孩子 心智 +3」往这儿飞）
func kid_rect() -> Rect2:
	if kid.is_empty():
		return Rect2()
	return Rect2(left(), me_rect().end.y + KID_GAP, ME_W, KID_H)


## 孩子牌上那一行：[["体魄", 42], ["心智", 55], ["魅力", 38]]，百分制往下取整（和关口纸带一个口径）
static func kid_points(stats: Dictionary) -> Array:
	var out: Array = []
	for k in ["body", "mind", "charm"]:
		out.append([P.STAT_NAME[k], int(floor(float(stats.get(k, 0.0)) * 10.0 + 0.001))])
	return out


## 几岁：刚生下来那几年写「不到一岁」
static func kid_age_text(age: int) -> String:
	return "不到一岁" if age <= 0 else "%d 岁" % age


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


## 两个圆在 HUD 里的位置（飘字的「亲近 +1」往这儿飞）
func bond_rect() -> Rect2:
	var them := them_rect()
	if partner.is_empty():
		return them
	return Rect2(them.position + Vector2(0, BAND), Vector2(BOND_W, them.size.y - BAND))


func left() -> float:
	return SIDE + inset.x


func right() -> float:
	return size.x - SIDE - inset.y


## 左上「我」的牌整张（在河畔里有圆表、成长账的时候最高）
func me_rect() -> Rect2:
	var h := BAND + AGE_H
	if not needs.is_empty():
		h += NEEDS_H + STATS_H
	return Rect2(left(), TOP, ME_W, h)


## 右上「对门」的牌整张（没有对门时只剩两个圆那一截）
func them_rect() -> Rect2:
	var w := THEM_W if not partner.is_empty() else BOND_W
	return Rect2(right() - w, TOP, w, THEM_H)


## 关口纸带该摆在哪：「我」的牌和「对门」的牌中间，居中，最宽 STRIP_MAX
func strip_rect() -> Rect2:
	var x := left() + ME_W + GAP
	var end := right() - THEM_W - GAP
	var w := clampf(end - x, 420.0, STRIP_MAX)
	return Rect2(x + maxf(0.0, (end - x - w) / 2.0), TOP, w, STRIP_H)


## 三个圆表下面那条成长账（ui/stat_strip.gd）的上沿
func stats_top() -> float:
	return TOP + BAND + AGE_H + NEEDS_H


## 右上角那张牌下面第一个空着的位置（音量按钮放这儿）
func right_slot_top() -> float:
	return TOP + THEM_H + 16.0


func _draw() -> void:
	var f := P.font()
	_scrim()
	_me(f, me_rect())
	if not kid.is_empty():
		_kid(f, kid_rect())
	if not needs.is_empty() or not partner.is_empty():
		_them(f, them_rect())
	var strip := strip_rect()
	var x := strip.position.x
	var y := strip.end.y + 12.0
	money_rect = Rect2()
	if money >= 0:
		x += _money(f, Vector2(x, y)) + 12.0
	story_rect = Rect2()
	if not story.is_empty():
		x += _story(f, Vector2(x, y), strip.end.x - x) + 12.0
	if note != "":
		var nw := f.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_CAPTION).x
		draw_rect(Rect2(x, y + 4, nw + 24, TAG_H - 8), Color(P.PAPER_HI, 0.9))
		Kit.text(self, Vector2(x + 12, y + 30), note, P.FS_CAPTION, P.INK_MID)
	if not pointer.is_empty():
		_pointer(f)


## 顶上、底下各铺一层很淡的纸色，从边上往里淡掉：牌子和按钮底下的地图网点安静一点，字就清楚了。
## 只压网点的明暗，不盖画：最浓处也只有 SCRIM_A
const SCRIM_A := 0.5
const SCRIM_TOP := 360.0
const SCRIM_BOTTOM := 240.0


func _scrim() -> void:
	var clear := Color(P.PAPER, 0.0)
	var thick := Color(P.PAPER, SCRIM_A)
	var w := size.x
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, SCRIM_TOP), Vector2(0, SCRIM_TOP)]),
		PackedColorArray([thick, thick, clear, clear]))
	var h := size.y
	draw_polygon(PackedVector2Array([Vector2(0, h - SCRIM_BOTTOM), Vector2(w, h - SCRIM_BOTTOM), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([clear, clear, thick, thick]))


## 「我」的牌：一张纸从上到下三截，细线分开
func _me(f: Font, r: Rect2) -> void:
	var at := r.position
	Kit.draw_sheet(self, r, Kit.accent)
	var parts := time_label.split(" · ")
	var age_text := str(parts[0]) if parts.size() > 0 else ""
	var fs := 60 if age_text.length() <= 4 else 44
	var clock := P.clock(minute)
	var cw := f.get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1, CLOCK_FS).x
	var aw := f.get_string_size(age_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# 年纪长了（"34 岁那几年"）一行放不下年纪和钟点：钟点挪到色条右头，顶掉那两个孔
	var long := aw + cw + 92.0 > r.size.x
	# 色条：节气 / 学期 / 人生阶段
	var band := str(parts[1]) if parts.size() > 1 else str(STAGE_NAME.get(stage, ""))
	if tag != "":
		band += " · " + tag
	Kit.draw_band(self, r, Kit.accent, BAND)
	var band_room := r.size.x - (f.get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_LABEL).x + 48.0 if long else 96.0)
	Kit.text(self, at + Vector2(18, 34), band, P.FS_LABEL, P.PAPER_HI, false, band_room)
	if long:
		Kit.text(self, at + Vector2(r.size.x - 16, 34), clock, P.FS_LABEL, P.PAPER_HI, true)
	else:
		# 撕日历的两个孔
		for hx in [r.size.x - 62.0, r.size.x - 30.0]:
			draw_circle(at + Vector2(hx, BAND / 2.0), 6.5, P.PAPER_HI, true, -1.0, true)
			draw_arc(at + Vector2(hx, BAND / 2.0), 6.5, 0, TAU, 16, P.INK, 2.0, true)
	# 年纪（大）和钟点（右边，前面一个太阳 / 月亮）
	var base := at.y + BAND + AGE_H / 2.0 + fs * 0.36
	Kit.text(self, Vector2(at.x + 18, base), age_text, fs, P.INK, false, r.size.x - 30.0)
	if not long:
		var cx := at.x + r.size.x - 18.0
		Kit.text(self, Vector2(cx, at.y + BAND + AGE_H / 2.0 + 13.0), clock, CLOCK_FS, P.INK, true)
		var night := minute >= 1110.0 or minute < 360.0
		Icons.draw(self, "moon" if night else "sun", Vector2(cx - cw - 24.0, at.y + BAND + AGE_H / 2.0), 16.0, P.MEI)
	if needs.is_empty():
		return
	var y := at.y + BAND + AGE_H
	Kit.hair(self, Vector2(at.x + 14, y), Vector2(r.end.x - 14, y))
	var i := 0
	var pitch := (r.size.x - 32.0) / NEED_KEYS.size()
	for k in NEED_KEYS:
		var c := Vector2(at.x + 16.0 + pitch * i + 34.0, y + NEEDS_H / 2.0)
		_gauge(f, c, k)
		var low := float(needs.get(k, 100.0)) < LOW
		Kit.text(self, c + Vector2(36.0, 10.0), str(int(round(float(_shown.get(k, 0.0))))), P.FS_LABEL, P.MEI if low else P.INK_MID)
		i += 1
	y += NEEDS_H
	Kit.hair(self, Vector2(at.x + 14, y), Vector2(r.end.x - 14, y))


func _gauge(f: Font, c: Vector2, key: String) -> void:
	var v := clampf(float(_shown.get(key, 0.0)) / 100.0, 0.0, 1.0)
	var low := float(needs.get(key, 100.0)) < LOW
	var r := 27.0
	if low:
		c += Vector2(sin(_t * 22.0) * 1.6 * maxf(0.0, sin(_t * 2.2)), 0.0)
		draw_circle(c + Vector2(3, 3), r, P.MEI, true, -1.0, true)
	draw_circle(c, r, P.PAPER_HI, true, -1.0, true)
	draw_arc(c, r - 6.0, 0, TAU, 40, P.HAIR, 6.0, true)  # 空着的那一圈：淡淡一道槽
	if v > 0.005:
		draw_arc(c, r - 6.0, -PI / 2.0, -PI / 2.0 + TAU * v, 40, P.MEI if low else P.INK, 6.0, true)
	draw_arc(c, r, 0, TAU, 40, P.INK, 2.0, true)
	var g: String = NEED_GLYPH[key]
	var w := f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_CAPTION).x
	draw_string(f, c + Vector2(-w / 2.0, 9), g, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_CAPTION, P.MEI if low else P.INK)


## 孩子的小牌：上一行名字、几岁（两口子共用的，右头两个叠着的小圆 +「两家的」），细线，下一行三项。
## 错位的色块是我的颜色；两家的孩子用两色叠印的那种深色
func _kid(f: Font, r: Rect2) -> void:
	var lift := sin(clampf(_kid_bump / 0.4, 0.0, 1.0) * PI) * 4.0
	r.position.y -= lift
	var at := r.position
	var shared := bool(kid.get("shared", false))
	Kit.draw_sheet(self, r, P.OVERLAP if shared else Kit.accent)
	var right_room := 0.0
	if shared:
		var mark := "两家的"
		var mw := f.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_CAPTION).x
		Kit.text(self, Vector2(r.end.x - 16.0, at.y + 38.0), mark, P.FS_CAPTION, P.INK_MID, true)
		Kit.draw_pair(self, Vector2(r.end.x - 16.0 - mw - 22.0, at.y + 30.0), 8.0, 7.0)
		right_room = mw + 56.0
	var name := str(kid.get("name", "孩子"))
	var age := kid_age_text(int(kid.get("age", 0)))
	var nw := Kit.text(self, Vector2(at.x + 18.0, at.y + 40.0), name, P.FS_LABEL, P.INK, false, r.size.x - 130.0 - right_room)
	Kit.text(self, Vector2(at.x + 18.0 + nw + 14.0, at.y + 40.0), age, P.FS_CAPTION, P.INK_MID)
	Kit.hair(self, Vector2(at.x + 14, at.y + 54.0), Vector2(r.end.x - 14, at.y + 54.0))
	var stats: Dictionary = _kid_held if not _kid_held.is_empty() else _dict(kid.get("stats"))
	var pitch := (r.size.x - 36.0) / 3.0
	var keys := ["body", "mind", "charm"]
	var row := kid_points(stats)
	for i in 3:
		var x := at.x + 18.0 + pitch * i
		var lw := Kit.text(self, Vector2(x, at.y + 84.0), str(row[i][0]), P.FS_CAPTION, P.INK_MID)
		var hot: bool = keys[i] == _kid_hot and _kid_bump > 0.0
		Kit.text(self, Vector2(x + lw + 8.0, at.y + 84.0), str(row[i][1]), P.FS_LABEL, Kit.accent if hot else P.INK)


## 零花钱：一张小签，钢镚儿 + 几块
func _money(f: Font, at: Vector2) -> float:
	var text := "%d 块" % int(round(_money_shown if _money_shown >= 0.0 else float(money)))
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_LABEL).x
	var r := Rect2(at, Vector2(w + 66, TAG_H))
	money_rect = r
	Kit.draw_sheet(self, r, Color(0, 0, 0, 0), 4.0, P.PAPER_HI, 2.0)
	Icons.draw(self, "coin", at + Vector2(24, TAG_H / 2.0), 15.0, Kit.accent)
	Kit.text(self, at + Vector2(46, 31), text, P.FS_LABEL, P.INK)
	return r.size.x


## 主线的小签：左边一块墨印着「第几章」，右边是章名和今天的下一件事（没排上就只写章名）。
## 章末躲不过去的那一件，签头换成两色叠印的那种深色（P.OVERLAP，两个人的事；梅红是梅自己的颜色），一早就写明「今天傍晚，河边的长椅 · 到点一定会去」：
## 到了它那一段，人在哪儿都会被叫过去。先说好，玩家有准备，不是被拽过去的（人本来就在那儿就照常发生）
static func story_text(st: Dictionary) -> Array:
	var n := int(st.get("chapter", 0))
	var head := "第%s章" % (CHAPTER_NUM[n] if n > 0 and n < CHAPTER_NUM.size() else str(n))
	var next: Variant = st.get("next")
	var body := str(st.get("title", ""))
	if next is String and next != "":
		if bool(st.get("force", false)):
			body += " · 今天%s · 到点一定会去" % next
		else:
			body += " · 下一件事 " + next
	return [head, body]


func _story(f: Font, at: Vector2, room: float) -> float:
	var parts := story_text(story)
	var hw := f.get_string_size(parts[0], HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_CAPTION).x + 26.0
	var bw := minf(f.get_string_size(parts[1], HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_CAPTION).x + 30.0, maxf(160.0, room - hw))
	var r := Rect2(at, Vector2(hw + bw, TAG_H))
	story_rect = r
	Kit.draw_sheet(self, r, Color(0, 0, 0, 0), 4.0, P.PAPER_HI, 2.0)
	draw_rect(Rect2(at, Vector2(hw, TAG_H)), P.OVERLAP if bool(story.get("force", false)) else P.INK)
	Kit.text(self, at + Vector2(13, 30), parts[0], P.FS_CAPTION, P.PAPER_HI)
	Kit.text(self, at + Vector2(hw + 15, 30), parts[1], P.FS_CAPTION, P.INK, false, bw - 26.0)
	return r.size.x


## 「对门」的牌：色条是 TA 的颜色；左边两个圆（亲近决定叠多少），右边大字是 TA 在做什么，小字补一句
func _them(f: Font, r: Rect2) -> void:
	var at := r.position
	var color: Color = partner.get("color", P.MEI)
	Kit.draw_sheet(self, r, color if not partner.is_empty() else Color(0, 0, 0, 0))
	if not partner.is_empty():
		Kit.draw_band(self, r, color, BAND)
		Kit.text(self, at + Vector2(18, 34), "对门 · %s" % str(partner.get("name", "TA")), P.FS_LABEL, P.PAPER_HI, false, r.size.x - 70.0)
		# 在线是一个实心的点；人不在、影子替着，是一个空圈
		var dot := at + Vector2(r.size.x - 26.0, BAND / 2.0)
		if bool(partner.get("online", false)):
			draw_circle(dot, 8.0, P.PAPER_HI, true, -1.0, true)
		else:
			draw_arc(dot, 7.0, 0, TAU, 16, P.PAPER_HI, 2.5, true)
	var b := bond_rect()
	var close := clampf(float(bond.get("close", 0)) / 100.0, 0.0, 1.0)
	var rad := 19.0
	var squeeze := sin(clampf(_bump / 0.45, 0.0, 1.0) * PI) * rad * 0.55
	var gap := lerpf(rad * 2.15, rad * 0.5, close) + sin(_t * 1.4) * 1.2 - squeeze
	var top := b.position.y if not partner.is_empty() else at.y
	Kit.draw_pair(self, Vector2(b.get_center().x, top + 30.0), rad, gap, 1.0, 1.6)
	for i in 2:
		var text := ("亲近 %d" % int(bond.get("close", 0))) if i == 0 else ("默契 %d" % int(bond.get("sync", 0)))
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, P.FS_CAPTION).x
		Kit.text(self, Vector2(b.get_center().x - w / 2.0, top + 74.0 + i * 26.0), text, P.FS_CAPTION, P.INK if i == 0 else P.INK_MID)
	if partner.is_empty():
		return
	draw_line(Vector2(b.end.x, b.position.y + 12), Vector2(b.end.x, b.end.y - 12), P.HAIR, P.LINE_HAIR, true)
	var x := b.end.x + 18.0
	var room := r.end.x - x - 16.0
	var big := str(partner.get("big", ""))
	var fs := P.FS_H
	while fs > P.FS_LABEL and f.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		fs -= 4
	Kit.text(self, Vector2(x, b.position.y + 50.0), big, fs, P.INK, false, room)
	Kit.text(self, Vector2(x, b.position.y + 90.0), str(partner.get("small", "")), P.FS_CAPTION, P.INK_MID, false, room)


## 对门不在画面里：贴着屏幕边一个 TA 颜色的圆，尖儿朝着 TA 的方向
func _pointer(f: Font) -> void:
	var at: Vector2 = pointer.at
	var dir: Vector2 = pointer.dir
	var color: Color = pointer.get("color", P.MEI)
	var r := 30.0 + sin(_t * 2.4) * 1.5
	var tip := at + dir * (r + 22.0)
	var side := dir.orthogonal() * 15.0
	var base := at + dir * (r - 6.0)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(3, 3), base + side + Vector2(3, 3), base - side + Vector2(3, 3)]), P.SHADE)
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), color)
	draw_circle(at + Vector2(3, 3), r, P.SHADE, true, -1.0, true)
	draw_circle(at, r, color, true, -1.0, true)
	draw_arc(at, r, 0, TAU, 32, P.INK, 2.5, true)
	var ch := str(pointer.get("name", "TA")).left(1)
	var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(f, at + Vector2(-w / 2.0, 11), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, P.PAPER_HI)
