extends RefCounted
## 传承的界面：投胎页上摆着的老物件（自己的能挑，对门的看得见）、家业那一行，
## 结局页的「留给河畔里」和「再来一世」，大厅里的「第几世」。
## 规则都在服务端（server/src/legacy.ts），老物件的文字在 content/heirlooms.yaml，这里只管画。设计见 docs/LEGACY.md。
## 用的都是 kit.gd 的部件；投票的两个圆和别处一样用 Kit.draw_pair。
##
## main.gd 在这几处调进来：
##   _show_roll        → roll_head / my_offer / their_offer
##   _roll_card        → house_line
##   _on_roll_state    → same_cards / refresh_roll（只是换了手里的东西就原地改，不整页重画）
##   _show_ending      → ending
##   _on_snapshot、_on_presence → on_protocols；net.again_state → on_again
##   _on_lifelines     → life_text

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")
const RisoBox := preload("res://scripts/ui/riso_box.gd")
const Op := preload("res://scripts/net/protocol.gd")

var m: Node  ## main.gd
## 两边安装包的协议版本（不在线是 0）。服务器 3 版起在快照和 PRESENCE 里带
var protocols: Dictionary = {}
var _mine_box: VBoxContainer
var _their_box: VBoxContainer
var _again_box: VBoxContainer


func _init(main: Node) -> void:
	m = main


func heirloom(id: Variant) -> Dictionary:
	if id == null:
		return {}
	for h in m.content.get("heirlooms", []):
		if str(h.id) == str(id):
			return h
	return {}


func _name(role: String) -> String:
	return str(m.names.get(role, P.ROLE_NAME.get(role, "TA")))


func _alive(box: Variant) -> bool:
	return box != null and is_instance_valid(box) and box.is_inside_tree()


## 带上它多了什么（属性按百分制写，和日结、关口上的写法一样）
func effect_text(h: Dictionary) -> String:
	var parts: Array = []
	var bonus: Dictionary = h.get("bonus", {})
	for k in ["body", "mind", "charm", "luck"]:
		var v := float(bonus.get(k, 0.0)) * 10.0
		if v > 0.0:
			parts.append("%s +%d" % [P.STAT_NAME[k], int(round(v))])
	if int(h.get("money", 0)) > 0:
		parts.append("零花钱 +%d 块" % int(h.money))
	if int(h.get("close", 0)) > 0:
		parts.append("亲近 +%d" % int(h.close))
	return "　".join(parts)


# ----------------------------------------------------------------------
# 投胎页
# ----------------------------------------------------------------------

## 页头。头一世和以前一样；之后多一枚「第 N 世」和上一世的一行小传
func roll_head(body: Container) -> void:
	var n := int(m.life.get("life", 1))
	if n <= 1:
		m._label(body, "你出生在……", 40, P.INK_SOFT)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	body.add_child(row)
	Kit.chip(row, "第 %d 世" % n, P.OVERLAP, 32)
	var l: Label = m._label(row, "你又出生在……", 40, P.INK_SOFT)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var line := past_line()
	if line != "":
		m._label(body, line, 30, P.INK_SOFT)


## 上一世的一行小传：结局的名字、两个人各活到多少岁
func past_line() -> String:
	var lg: Variant = m.life.get("legacy")
	if not lg is Dictionary or not lg.get("past") is Array or lg.past.is_empty():
		return ""
	var last: Dictionary = lg.past[-1]
	var title := ""
	var endings: Variant = m.content.get("endings")
	if endings is Dictionary:
		for e in endings.get("pair", []):
			if str(e.id) == str(last.get("pair", "")):
				title = str(e.title)
	var ages: Array = []
	for r in ["qing", "mei"]:
		var p: Variant = last.get("persons", {}).get(r)
		if p is Dictionary and p.get("diedAtAge") != null:
			ages.append("%s %d 岁" % [str(p.get("name", _name(r))), int(p.diedAtAge)])
	var head := "上一世「%s」" % title if title != "" else "上一世"
	return " · ".join([head] + ages)


## 出生证里多的一行：这户人家的营生之前有人接下过
func house_line(col: Container, r: Dictionary) -> void:
	var house := int(r.get("house", 0))
	if house <= 0:
		return
	var rules: Variant = m.content.get("rules", {}).get("legacy")
	var per := int(rules.get("houseMoney", 0)) if rules is Dictionary else 0
	var text := "家里的营生传了 %d 代" % house
	if per > 0:
		text += "，家底多 %d 块" % (per * house)
	m._label(col, text, 30, P.OVERLAP)


## 我面前摆着的老物件：点一件带上，再点一下放下
func my_offer(body: Container) -> void:
	_mine_box = VBoxContainer.new()
	_mine_box.add_theme_constant_override("separation", 22)
	body.add_child(_mine_box)
	_fill_mine()


## 对门面前摆着的：只看，不能替 TA 挑
func their_offer(body: Container) -> void:
	_their_box = VBoxContainer.new()
	_their_box.add_theme_constant_override("separation", 12)
	body.add_child(_their_box)
	_fill_theirs()


## 两份抽卡状态，除了手里挑的东西以外是不是一样（一样就不用整页重画）
func same_cards(a: Variant, b: Variant) -> bool:
	if not a is Dictionary or not b is Dictionary:
		return false
	for r in ["qing", "mei"]:
		var x: Variant = a.get(r)
		var y: Variant = b.get(r)
		if not x is Dictionary or not y is Dictionary:
			return false
		for k in ["familyId", "talentId", "rerollsLeft", "confirmed", "house"]:
			if str(x.get(k)) != str(y.get(k)):
				return false
	return true


func refresh_roll() -> void:
	if _alive(_mine_box):
		_fill_mine()
	if _alive(_their_box):
		_fill_theirs()


func _fill_mine() -> void:
	m._clear(_mine_box)
	var mine: Dictionary = m.life.rolls[m.my_role]
	var offer: Array = mine.get("offer", []) if mine.get("offer") is Array else []
	var shown: Array = offer.filter(func(id): return not heirloom(id).is_empty())
	_mine_box.visible = not shown.is_empty()
	if shown.is_empty():
		return
	var picked: Variant = mine.get("heirloomId")
	var locked := bool(mine.get("confirmed", false))
	m._label(_mine_box, "河畔里留着的老物件", 36, P.INK)
	var hint := "带一件走，或者空着手。"
	if locked:
		hint = "空着手出生。" if picked == null else "带着「%s」出生。" % str(heirloom(picked).get("name", ""))
	m._label(_mine_box, hint, 30, P.INK_SOFT)
	for id in shown:
		_tag(_mine_box, heirloom(id), str(picked) == str(id), locked)


func _fill_theirs() -> void:
	m._clear(_their_box)
	var role: String = m._other()
	var theirs: Dictionary = m.life.rolls[role]
	var offer: Array = theirs.get("offer", []) if theirs.get("offer") is Array else []
	var shown: Array = []
	for id in offer:
		var h := heirloom(id)
		if not h.is_empty():
			shown.append(str(h.name))
	_their_box.visible = not shown.is_empty()
	if shown.is_empty():
		return
	m._label(_their_box, "TA 面前摆着：" + "、".join(shown), 30, P.INK_SOFT)
	var h := heirloom(theirs.get("heirloomId"))
	if not h.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		_their_box.add_child(row)
		Kit.chip(row, "带上了", P.role_color(role), 28)
		var l: Label = m._label(row, str(h.name), 34, P.INK)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER


## 一件老物件：一张打了孔的纸签。挑中的那张，自己的颜色整块印上去
func _tag(box: Container, h: Dictionary, picked: bool, locked: bool) -> void:
	var color := P.role_color(m.my_role)
	var panel := PanelContainer.new()
	var sb := RisoBox.make(color if picked else Color(color, 0.0), 9.0, 30.0)
	sb.line = 3.0
	sb.content_margin_left = 74.0
	panel.add_theme_stylebox_override("panel", sb)
	if locked and not picked:
		panel.modulate.a = 0.45
	box.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	# 名字和「带上它多了什么」一行，下面是物件本身的一句话
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var nm: Label = m._label(head, str(h.get("name", "")), 42, P.INK)
	nm.autowrap_mode = TextServer.AUTOWRAP_OFF
	nm.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var eff := effect_text(h)
	if eff != "":
		var e: Label = m._label(head, eff, 28, color)
		e.size_flags_vertical = Control.SIZE_SHRINK_END
	m._label(col, str(h.get("desc", "")), 30, P.INK_SOFT)
	if picked:
		var seal := Kit.chip(row, "带上", color, 30)
		seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_child(_TagHole.new(color, picked))
	if locked:
		return
	# 整张签都能点：盖一个透明的按钮在上面（滚动、按下的手感都跟别的按钮一样）
	var hit := Button.new()
	hit.name = "Heirloom_%s" % str(h.id)
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var id := str(h.id)
	hit.pressed.connect(func(): m.net.pick_heirloom("" if picked else id))
	panel.add_child(hit)


## 纸签左边打的孔。挑中的那张，孔里透出自己的颜色
class _TagHole extends Control:
	const P := preload("res://scripts/ui/palette.gd")
	var color := P.INK_SOFT
	var picked := false

	func _init(p_color: Color, p_picked: bool) -> void:
		color = p_color
		picked = p_picked
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(-38.0, size.y / 2.0)
		draw_circle(c, 12.0, color if picked else P.PAPER_DARK, true, -1.0, true)
		draw_arc(c, 12.0, 0, TAU, 32, P.INK, 2.5, true)


# ----------------------------------------------------------------------
# 结局页
# ----------------------------------------------------------------------

## 「留给河畔里」和「再来一世」。画了再来一世就返回 true（那样「回到标题」退成小字）
func ending(body: Container) -> bool:
	var left: Variant = m.life.get("left")
	var rows: Array = []
	if left is Dictionary:
		for r in ["qing", "mei"]:
			var h := heirloom(left.get(r))
			if not h.is_empty():
				rows.append([r, h])
	if not rows.is_empty():
		var card := Kit.card(P.INK_SOFT, 44.0)
		body.add_child(card)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 20)
		card.add_child(col)
		Kit.chip(col, "留给河畔里", P.INK, 32)
		for it in rows:
			var head := HBoxContainer.new()
			head.add_theme_constant_override("separation", 18)
			col.add_child(head)
			Kit.chip(head, _name(it[0]), P.role_color(it[0]), 30)
			var nm: Label = m._label(head, str(it[1].name), 42, P.INK)
			nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			m._label(col, str(it[1].get("desc", "")), 32, P.INK_SOFT)
	_again_box = VBoxContainer.new()
	_again_box.add_theme_constant_override("separation", 24)
	body.add_child(_again_box)
	return _fill_again()


func can_again() -> bool:
	return m.net != null and m.net.server_has_legacy() and str(m.life.get("phase", "")) == "ended"


func _fill_again() -> bool:
	m._clear(_again_box)
	_again_box.visible = can_again()
	if not can_again():
		return false
	var other: String = m._other()
	var again: Dictionary = m.life.get("again") if m.life.get("again") is Dictionary else {}
	var mine := bool(again.get(m.my_role, false))
	var theirs := bool(again.get(other, false))
	var their_protocol := int(protocols.get(other, 0))
	var here := their_protocol > 0
	Kit.gap(_again_box, 10)
	_again_box.add_child(_AgainMark.new({"qing": bool(again.get("qing", false)), "mei": bool(again.get("mei", false))}))
	if here and their_protocol < Op.LEGACY_SINCE:
		# TA 的安装包还不认识「再来一世」：点了也凑不齐，先说清楚
		m._label(_again_box, "TA 的安装包还是旧的。等 TA 更新了，才能一起再来一世。", 34, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
		var b: Button = m._primary(_again_box, "再来一世", func(): pass)
		b.disabled = true
	elif mine:
		var wait := "等 TA 也点头……" if here else "TA 不在。等 TA 上来点头。"
		m._label(_again_box, "这就走。" if theirs else "你点了头。" + wait, 36, P.INK, HORIZONTAL_ALIGNMENT_CENTER)
		if not theirs:
			m._quiet(_again_box, "再想想", func(): m.net.again(false))
	else:
		if theirs:
			m._label(_again_box, "%s 想再来一世。" % _name(other), 36, P.role_color(other), HORIZONTAL_ALIGNMENT_CENTER)
		else:
			m._label(_again_box, "两个人都点头，就在河畔里重新投胎。留下的东西，下一世各带一件。", 32, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
		m._primary(_again_box, "再来一世", func(): m.net.again(true))
	return true


## 两个圆：谁点了头，谁的那个就印上颜色；都点了就叠到一起
class _AgainMark extends Control:
	const P := preload("res://scripts/ui/palette.gd")
	const Kit := preload("res://scripts/ui/kit.gd")
	var votes: Dictionary = {}

	func _init(p_votes: Dictionary) -> void:
		votes = p_votes
		custom_minimum_size = Vector2(0, 150)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var mid := Vector2(size.x / 2.0, 75.0)
		var r := 46.0
		if votes.get("qing", false) and votes.get("mei", false):
			Kit.draw_pair(self, mid, r, 16.0, 1.0, 3.0)
			return
		for role in ["qing", "mei"]:
			var at := mid + Vector2(-70.0 if role == "qing" else 70.0, 0)
			if votes.get(role, false):
				draw_circle(at + Vector2(4, 4), r, P.role_color(role), true, -1.0, true)
				draw_arc(at, r, 0, TAU, 64, P.INK, 3.0, true)
			else:
				draw_arc(at, r, 0, TAU, 64, Color(P.INK_SOFT, 0.8), 2.0, true)


func on_again(data: Dictionary) -> void:
	if data.get("again") is Dictionary:
		m.life["again"] = data.again
	if _alive(_again_box):
		_fill_again()


func on_protocols(p: Variant) -> void:
	if not p is Dictionary:
		return
	protocols = p
	if _alive(_again_box):
		_fill_again()


# ----------------------------------------------------------------------
# 大厅
# ----------------------------------------------------------------------

## 人生线列表里：第二世起写上是第几世
func life_text(it: Dictionary) -> String:
	var n := int(it.get("life", 1))
	return "第 %d 世 · " % n if n > 1 else ""
