extends CanvasLayer
## 爽感层：让每一件做完的事都有个响儿。只看、不改规则（规则都在服务器），盖在界面上面、弹窗和转场下面。
##
##   飘字   做完一件事，长了几分、挣了几块、亲近了几分，从人头上一张一张印出来，
##          停一下，再飞进 HUD 里对应的那一格（成长账 / 零花钱 / 两个圆）。落下的那一刻格子里的数才拨上去。
##          连着几张，声音按五声音阶往上走。TA 长的分在 TA 头上小一号地冒一下，不飞。
##   搭伴   两个人搭伴做完的那件事，飘字之前先在两个人中间砸一方「搭伴」的印（有倍率就写倍率）。
##   成长账 每个日子记一个点（两个人的三项），存在 user://growth/<人生线>.json：
##          长大那张墨卡上的阶段成绩单、点开 HUD 成长账看的曲线都从这里来（ui/stage_report.gd）。
##
## 数从哪来：一律是服务器 WORLD 里 stats / money / bond 前后两帧的差（百分制往下取整，和关口纸带一个口径）。
## 服务器要是在 actors[role].did 里说了「刚做完哪一件」（n 递增），就拿它认搭伴和倍率；没有也照样飘。
## 开着弹窗、过场卡的时候不飘：那些数在弹窗里另有交代（关口揭晓、当天小结）。

const P := preload("res://scripts/ui/palette.gd")
const Report := preload("res://scripts/ui/stage_report.gd")
const LifeTime := preload("res://scripts/ui/life_time.gd")
const KEYS := ["body", "mind", "charm"]
const STAGE_OF_AGE := [[3, "childhood"], [12, "teen"], [18, "young"], [30, "middle"], [60, "old"]]
## 五声音阶（D 宫）：连着长的几下一个比一个高
## 有 did 的时候，飘字等这么久再出来（钟从 f 拨到 t 0.9 秒）
const DID_LEAD := 0.95
const SCALE := [1.0, 1.1225, 1.2599, 1.4983, 1.6818, 2.0, 2.245, 2.52]

var main: Node
var journal: Dictionary = {"pts": [], "stages": {}}
var _id := ""                ## 人生线
var _base: Dictionary = {}   ## role -> {body, mind, charm}（百分制）
var _money := -1.0
var _bond: Dictionary = {}
var _did: Dictionary = {}    ## role -> 上一次看到的 did.n
var _was_tg := false         ## 上一帧我是不是在搭伴做事
var _act := ""               ## 上一帧我在做什么
var _combo := 0
var _combo_t := 0.0
var _dirty := false
var _save_t := 0.0
var _shake := 0.0


func _ready() -> void:
	layer = 3


func _audio() -> Node:
	return main.get_node_or_null("Audio") if main != null else null


func cue(name: String, db := 0.0, pitch := 1.0) -> void:
	var a := _audio()
	if a != null and a.has_method("cue"):
		a.cue(name, db, pitch)


func _role() -> String:
	return str(main.my_role)


func _other() -> String:
	return "mei" if _role() == "qing" else "qing"


static func points(v: Variant) -> int:
	return int(floor(float(v) * 10.0 + 0.001))


func _quiet() -> bool:
	if main == null:
		return true
	if main.modal != null and main.modal.visible:
		return true
	if main.fx != null and main.fx.is_busy():
		return true
	var dc: Variant = main.get("day_card")  # 「一天行动循环」线程的当天小结（ui/day_card.gd）
	if dc is CanvasItem and is_instance_valid(dc) and dc.visible:
		return true
	return false


# ======================================================================
# 联机消息
# ======================================================================

func on_snapshot(data: Dictionary) -> void:
	var life: Dictionary = data.get("life", {}) if data.get("life") is Dictionary else {}
	var id := str(data.get("lifelineId", ""))
	if id != _id:
		_id = id
		_load()
	if str(life.get("phase", "")) != "life" or not life.get("persons") is Dictionary:
		if str(life.get("phase", "")) == "roll":
			journal = {"pts": [], "stages": {}}  # 再来一世：上一世的账不接着记
			_dirty = true
		_base = {}
		_money = -1.0
		return
	var persons: Dictionary = life.persons
	var stats: Dictionary = {}
	for r in persons:
		if persons[r] is Dictionary and bool(persons[r].get("alive", true)):
			stats[r] = persons[r].get("stats", {})
	_rebase(stats, float(_dict(persons.get(_role())).get("money", -1)), _dict(life.get("bond")))
	_record(int(life.get("turn", 0)), stats)


func on_world(data: Dictionary) -> void:
	var stats: Dictionary = _dict(data.get("stats"))
	var me := _role()
	if stats.is_empty():
		return
	var actors: Dictionary = _dict(data.get("actors"))
	var mine: Dictionary = _dict(actors.get(me))
	var did: Dictionary = _dict(mine.get("did"))
	var fresh_did := not did.is_empty() and int(did.get("n", -1)) != int(_did.get(me, -1))
	if not did.is_empty():
		_did[me] = int(did.get("n", -1))
	var money := float(_dict(data.get("money")).get(me, -1))
	var bond: Dictionary = _dict(data.get("bond"))
	var quiet := _quiet()
	if not _base.is_empty() and not quiet:
		_burst(stats, money, bond, fresh_did, did, mine)
	_rebase(stats, money, bond)
	var act := str(mine.get("act", "")) if mine.get("act") != null else ""
	_was_tg = bool(mine.get("tg", false)) and act != ""
	if act != "" and act != _act and not quiet:
		_ring(me)
	_act = act
	if main.life is Dictionary:
		_record(int(main.life.get("turn", 0)), stats)


func on_log(entries: Array) -> void:
	for e in entries:
		if not e is Dictionary:
			continue
		var st := _stage_at(int(e.get("age", -1)))
		if st == "":
			continue
		var c: Dictionary = journal.stages.get(st, {})
		match str(e.get("kind", "")):
			"together":
				c["tg"] = int(c.get("tg", 0)) + 1
			"mirror":
				if e.get("resonance") == true:
					c["res"] = int(c.get("res", 0)) + 1
			"milestone":
				if _dict(e.get("results")).has(_role()):
					c["ms"] = int(c.get("ms", 0)) + 1
			_:
				continue
		journal.stages[st] = c
		_dirty = true


func _rebase(stats: Dictionary, money: float, bond: Dictionary) -> void:
	_base = {}
	for r in stats:
		var row: Dictionary = {}
		for k in KEYS:
			row[k] = points(_dict(stats[r]).get(k, 0))
		_base[r] = row
	_money = money
	_bond = {"close": int(bond.get("close", 0)), "sync": int(bond.get("sync", 0))}


# ======================================================================
# 飘字
# ======================================================================

func _burst(stats: Dictionary, money: float, bond: Dictionary, fresh_did: bool, did: Dictionary, mine: Dictionary) -> void:
	var me := _role()
	var items: Array = []  # [文字, 数, 颜色, 飞去哪 key]
	var row: Dictionary = _dict(stats.get(me))
	var was: Dictionary = _dict(_base.get(me))
	if not was.is_empty():
		for k in KEYS:
			var d := points(row.get(k, 0)) - int(was.get(k, 0))
			if d != 0:
				items.append([P.STAT_NAME[k], d, k])
	if _money >= 0.0 and money >= 0.0:
		var dm := int(round(money - _money))
		if dm != 0:
			items.append(["块", dm, "money"])
	for bk in ["close", "sync"]:
		var db := int(bond.get(bk, 0)) - int(_bond.get(bk, 0))
		if db > 0:
			items.append(["亲近" if bk == "close" else "默契", db, bk])
	var together := bool(did.get("tg", false)) if fresh_did else (_was_tg and not items.is_empty())
	var grew := false
	for it in items:
		if it[2] in KEYS and int(it[1]) > 0:
			grew = true
	# 服务器说了刚做完哪一件（did）：「一天行动循环」那边先把钟拨过去、人在点上把这件事做完（约一秒），字再出来
	var delay := DID_LEAD if fresh_did and not bool(did.get("j", false)) else 0.0  # j：对门后赶上来补的搭伴，那边不拨钟，不用等
	if together and grew:
		var mult := float(did.get("b", 0.0)) if fresh_did else 0.0
		_stamp_together(mult, delay)
		delay += 0.62  # 印先砸下来、开始淡了，字再印出来
	if not items.is_empty():
		_pop_items(me, items, delay, true)
	# TA 的：小一号，在 TA 头上冒一下，不飞
	var other := _other()
	var orow: Dictionary = _dict(stats.get(other))
	var owas: Dictionary = _dict(_base.get(other))
	if not owas.is_empty():
		var theirs: Array = []
		for k in KEYS:
			var d := points(orow.get(k, 0)) - int(owas.get(k, 0))
			if d > 0:
				theirs.append([P.STAT_NAME[k], d, k])
		if not theirs.is_empty():
			_pop_items(other, theirs, delay + 0.1, false)


func _head(role: String) -> Variant:
	var w: Variant = main.world
	if w == null or not is_instance_valid(w):
		return null
	var a: Variant = w.actors.get(role)
	if a == null or not a.visible:
		return null
	var h: float = (a._height() if a.has_method("_height") else 160.0) * a.scale.y
	return w.get_canvas_transform() * (a.global_position + Vector2(0, -h - 40.0))


func _feet(role: String) -> Variant:
	var w: Variant = main.world
	if w == null or not is_instance_valid(w):
		return null
	var a: Variant = w.actors.get(role)
	if a == null or not a.visible:
		return null
	return w.get_canvas_transform() * a.global_position


## 飞去哪：成长账的那一格、零花钱、两个圆
func _target(key: String) -> Variant:
	var strip: Variant = main.get("stat_strip")
	if key in KEYS and strip is Control and strip.visible:
		return strip.cell_rect(key).get_center()
	var hud: Variant = main.hud
	if hud == null:
		return null
	if key == "money" and hud.get("money_rect") is Rect2 and hud.money_rect.size.x > 0.0:
		return hud.money_rect.get_center() + hud.global_position
	if key in ["close", "sync"] and hud.has_method("bond_rect"):
		return hud.bond_rect().get_center() + hud.global_position
	return null


func _pop_items(role: String, items: Array, delay: float, fly: bool) -> void:
	var at: Variant = _head(role)
	if at == null:
		at = Vector2(main.ui.size.x * 0.5, main.ui.size.y * 0.55) if fly else null
	if at == null:
		return
	var color := P.role_color(role)
	var n := mini(items.size(), 5)
	# 一张摞一张往上叠，别横着排（两个人挨着站的时候会撞到一块儿）；我的往左偏、TA 的往右偏，贴不出屏幕
	var side := 0.0
	var other_at: Variant = _head(_other() if role == _role() else _role())
	if other_at is Vector2 and absf(other_at.x - at.x) < 320.0:
		side = -70.0 if other_at.x > at.x else 70.0
	for i in n:
		var it: Array = items[i]
		var amount := int(it[1])
		var key := str(it[2])
		var tag := Tag.new()
		var up := amount > 0
		if key == "money":
			tag.text_big = ("+%d" % amount) if up else ("−%d" % -amount)
			tag.text_small = "块"
		else:
			tag.text_small = str(it[0])
			tag.text_big = ("+%d" % amount) if up else ("−%d" % -amount)
		tag.color = color if up else P.INK_SOFT
		tag.small = not fly
		add_child(tag)
		tag._measure()
		var start: Vector2 = at + Vector2(side, -i * (74.0 if fly else 56.0))
		var vw: Vector2 = main.ui.size
		start.x = clampf(start.x, tag.size.x / 2.0 + 24.0, vw.x - tag.size.x / 2.0 - 24.0)
		start.y = clampf(start.y, 420.0, vw.y - 200.0)
		var target: Variant = _target(key) if fly and up else null
		var strip: Variant = main.get("stat_strip")
		var t0 := delay + i * 0.14
		if target != null and key in KEYS and strip is Control:
			strip.hold(key, t0 + 1.25)
			var gp: Variant = main.get("goal_panel")
			if gp is Control and i == 0:
				gp.land_in = t0 + 1.25  # 纸带上「还差几分」也等第一张落下来再拨
		elif target != null and key == "money" and main.hud.has_method("hold_money"):
			main.hud.hold_money(t0 + 1.25)
		tag.play(start, target, t0, func():
			_landed(key, amount, role))


var _combo_i := 0


## 飞到了：格子里的数拨上去，响一下（连着的一下比一下高）
func _landed(key: String, amount: int, role: String) -> void:
	if role != _role():
		return
	var strip: Variant = main.get("stat_strip")
	if key in KEYS and strip is Control:
		strip.land(key, amount)
	elif key in ["close", "sync"] and main.hud.has_method("bump"):
		main.hud.bump()
	if amount <= 0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _combo_t > 1.2:
		_combo_i = 0
	_combo_t = now
	if key == "money":
		cue("coin", -6.0)
	else:
		cue("gain", -3.0, SCALE[mini(_combo_i, SCALE.size() - 1)])
	_combo_i += 1


func _stamp_together(mult: float, lead := 0.0) -> void:
	var a: Variant = _head(_role())
	var b: Variant = _head(_other())
	if a == null:
		return
	var at: Vector2 = a if b == null else (a + b) / 2.0
	at.x = clampf(at.x, 120.0, main.ui.size.x - 120.0)
	at.y = clampf(at.y - 150.0, 440.0, main.ui.size.y - 260.0)
	var s := Stamp.new()
	s.top = "搭伴"
	s.bottom = ("×%.1f" % mult) if mult > 1.01 else "长得快"
	s.color = P.OVERLAP
	add_child(s)
	s.play(at, lead, func():
		cue("seal", -4.0)
		_shake = 0.18)


## 开始做一件事：脚下一圈墨晕开
func _ring(role: String) -> void:
	var at: Variant = _feet(role)
	if at == null:
		return
	var r := Ring.new()
	r.color = P.role_color(role)
	r.position = at
	add_child(r)


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 7.0 * (_shake / 0.18)
	elif offset != Vector2.ZERO:
		offset = Vector2.ZERO
	_save_t += delta
	if _dirty and _save_t > 3.0:
		_save()


# ======================================================================
# 成长账
# ======================================================================

func _stage_at(age: int) -> String:
	if age < 0:
		return ""
	var st := "childhood"
	for row in STAGE_OF_AGE:
		if age >= int(row[0]):
			st = str(row[1])
	return st


func _record(turn: int, stats: Dictionary) -> void:
	var me := _role()
	if not stats.has(me):
		return
	var t: Dictionary = LifeTime.at(turn)
	var row: Array = [turn, int(t.age), str(t.stage)]
	for r in [me, _other()]:
		var s: Dictionary = _dict(stats.get(r))
		for k in KEYS:
			row.append(points(s.get(k, 0)) if not s.is_empty() else -1)
	var pts: Array = journal.pts
	if not pts.is_empty() and int(pts[-1][0]) > turn:
		# 回到了更早的日子：换了一世（或者换了人生线），从头记
		pts.clear()
		journal.stages = {}
	if not pts.is_empty() and int(pts[-1][0]) == turn:
		if pts[-1] == row:
			return
		pts[-1] = row
	else:
		pts.append(row)
	_dirty = true


func _path() -> String:
	return "user://growth/%s.json" % _id.validate_filename() if _id != "" else ""


func _load() -> void:
	journal = {"pts": [], "stages": {}}
	var p := _path()
	if p == "" or not FileAccess.file_exists(p):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if parsed is Dictionary and parsed.get("pts") is Array:
		journal = {"pts": parsed.pts, "stages": _dict(parsed.get("stages"))}


func _save() -> void:
	_dirty = false
	_save_t = 0.0
	var p := _path()
	if p == "":
		return
	DirAccess.make_dir_recursive_absolute("user://growth")
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(journal))


## 长大那张墨卡上的成绩单：刚过完的那个阶段。成长账里没有那一段就不放（返回 null）
func stage_report() -> Control:
	var pts: Array = journal.pts
	if pts.size() < 2:
		return null
	var cur := str(pts[-1][2])
	var prev := ""
	for i in range(pts.size() - 1, -1, -1):
		if str(pts[i][2]) != cur:
			prev = str(pts[i][2])
			break
	if prev == "":
		return null
	# 上一阶段的「到」用新阶段第一天的数（长大那一刻），所以把这一个点也算进去
	var view: Array = []
	for p in pts:
		view.append(p)
	var bridge: Array = pts[-1].duplicate()
	bridge[2] = prev
	view.insert(view.size() - 1, bridge)
	var r := Report.new()
	r.setup(view, prev, P.role_color(_role()), P.role_color(_other()), _dict(journal.stages.get(prev)), true, true)
	return r


## 点开 HUD 成长账：正在过的这一阶段（纸上，墨色字）
func growth_report(width := 1180.0) -> Control:
	var pts: Array = journal.pts
	if pts.is_empty():
		return null
	var cur := str(pts[-1][2])
	var r := Report.new()
	r.setup(pts, cur, P.role_color(_role()), P.role_color(_other()), _dict(journal.stages.get(cur)), false, false, width)
	return r


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


# ======================================================================
# 画出来的小东西
# ======================================================================

## 一张飘字：纸片 + 墨边 + 错位色块，左边小字（心智），右边大字（+3）
class Tag extends Control:
	const P := preload("res://scripts/ui/palette.gd")
	var text_small := ""
	var text_big := ""
	var color := P.QING
	var small := false
	var _box := Vector2.ZERO

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		modulate.a = 0.0

	func _measure() -> void:
		var f := P.font()
		var fs := 22 if small else 26
		var fb := 34 if small else 44
		var w := f.get_string_size(text_small, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + f.get_string_size(text_big, HORIZONTAL_ALIGNMENT_LEFT, -1, fb).x + 34.0
		_box = Vector2(w, 46.0 if small else 60.0)
		size = _box
		pivot_offset = _box / 2.0

	func play(start: Vector2, target: Variant, delay: float, on_land: Callable) -> void:
		_measure()
		position = start - _box / 2.0
		rotation = randf_range(-0.06, 0.06)
		scale = Vector2.ONE * 0.3
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(self, "modulate:a", 1.0, 0.08)
		tw.parallel().tween_property(self, "scale", Vector2.ONE * 1.12, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(self, "position:y", position.y - 46.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "scale", Vector2.ONE, 0.12)
		if target is Vector2:
			tw.tween_interval(0.22)
			var from := position - Vector2(0, 46.0)
			var to: Vector2 = target - _box / 2.0
			tw.tween_method(func(k: float):
				# 一道弧线：先往上挑一点再落进去
				var mid := (from + to) / 2.0 + Vector2(0, -160.0)
				position = from.lerp(mid, k).lerp(mid.lerp(to, k), k)
				scale = Vector2.ONE * lerpf(1.0, 0.45, k * k)
				rotation = lerpf(rotation, 0.0, k), 0.0, 1.0, 0.48).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			tw.tween_callback(on_land)
			tw.tween_property(self, "modulate:a", 0.0, 0.06)
		else:
			tw.tween_interval(0.55 if not small else 0.35)
			tw.tween_callback(on_land)
			tw.tween_property(self, "modulate:a", 0.0, 0.35)
			tw.parallel().tween_property(self, "position:y", position.y - 80.0, 0.35)
		tw.tween_callback(queue_free)

	func _draw() -> void:
		var f := P.font()
		var fs := 22 if small else 26
		var fb := 34 if small else 44
		var r := Rect2(Vector2.ZERO, _box)
		draw_rect(Rect2(r.position + Vector2(5, 5), r.size), color)
		draw_rect(r, P.PAPER)
		draw_rect(r, P.INK, false, 2.5)
		var sw := f.get_string_size(text_small, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := _box.y / 2.0 + fb * 0.34
		draw_string(f, Vector2(12, base - 2), text_small, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, P.INK)
		draw_string(f, Vector2(20 + sw + 2, base + 2), text_big, HORIZONTAL_ALIGNMENT_LEFT, -1, fb, Color(P.INK, 0.4))
		draw_string(f, Vector2(20 + sw, base), text_big, HORIZONTAL_ALIGNMENT_LEFT, -1, fb, color)


## 「搭伴」的印：从大到小砸下来，停一会儿，淡掉
class Stamp extends Control:
	const P := preload("res://scripts/ui/palette.gd")
	var top := ""
	var bottom := ""
	var color := P.OVERLAP
	var _since := -1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(150, 150)
		pivot_offset = size / 2.0

	func play(at: Vector2, lead: float, on_hit: Callable) -> void:
		position = at - size / 2.0
		rotation = -0.18
		scale = Vector2.ONE * 2.6
		modulate.a = 0.0
		var tw := create_tween()
		if lead > 0.0:
			tw.tween_interval(lead)
		tw.tween_property(self, "modulate:a", 1.0, 0.06)
		tw.parallel().tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			_since = 0.0
			on_hit.call())
		tw.tween_property(self, "scale", Vector2.ONE * 1.06, 0.06)
		tw.tween_property(self, "scale", Vector2.ONE, 0.1)
		tw.tween_interval(0.4)
		tw.tween_property(self, "modulate:a", 0.0, 0.35)
		tw.parallel().tween_property(self, "position:y", position.y - 30.0, 0.4)
		tw.tween_callback(queue_free)

	func _process(delta: float) -> void:
		if _since >= 0.0:
			_since += delta
			queue_redraw()

	func _draw() -> void:
		var f := P.font()
		var r := Rect2(Vector2(16, 16), size - Vector2(32, 32))
		draw_rect(r, Color(P.PAPER, 0.9))
		draw_rect(r, Color(color, 0.14))
		draw_rect(r, color, false, 6.0)
		draw_rect(r.grow(-10.0), Color(color, 0.75), false, 2.0)
		var tw := f.get_string_size(top, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		draw_string(f, Vector2(size.x / 2.0 - tw / 2.0, 72), top, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, color)
		var bw := f.get_string_size(bottom, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		draw_string(f, Vector2(size.x / 2.0 - bw / 2.0, 112), bottom, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, color)
		if _since >= 0.0 and _since < 0.4:
			var e := _since / 0.4
			for i in 10:
				var ang := TAU * i / 10.0
				var d := 70.0 + e * 50.0
				draw_circle(size / 2.0 + Vector2(cos(ang), sin(ang)) * d, 6.0 * (1.0 - e), Color(color, 0.85 * (1.0 - e)), true, -1.0, true)


## 脚下一圈墨：开始做事的那一下
class Ring extends Node2D:
	var color := Color.WHITE
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t > 0.6:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var e := _t / 0.6
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.36))
		draw_arc(Vector2.ZERO, 30.0 + e * 70.0, 0, TAU, 40, Color(color, 0.8 * (1.0 - e)), 6.0 * (1.0 - e) + 1.0, true)
		draw_set_transform(Vector2.ZERO)
