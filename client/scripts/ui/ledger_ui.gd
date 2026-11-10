extends Control
## 住户本：这条人生线上走完的每一世、街坊记住的事、河畔里留着的老物件。盖在当前页面上的一整页，合上就回去。
## 只是翻看：这里没有任何能点出数值的东西，没记住的事不占位置，也不写「还差几件」。设计见 docs/LEGACY.md。
##
## 数据两处来：
##   快照里的 life.legacy（最近几世的小传、记住的事、老物件）→ 打开就能画
##   服务器的 lifeline_past（net.fetch_past）→ 翻到某一世时再取那一页的全部回忆和几个数；更早的几世只有它有
## 取不到（老服务器、断线）就照小传画，不报错。
##
## 横竖屏都能排：宽大于高时左边是目录、右边是翻开的那一页；竖着拿时目录变成顶上的一排。

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")
const RisoBox := preload("res://scripts/ui/riso_box.gd")

const JOB_NAME := {"job_desk": "坐办公室", "job_teach": "教书", "job_trade": "做买卖", "job_craft": "手艺", "job_labor": "力气活", "job_odd": "打零工"}
const MAX_WIDTH := 2000.0  ## 横屏时整本最宽这么多
const TAB_REMEMBERED := "remembered"
const TAB_KEPT := "kept"

var m: Node  ## main.gd
var tab := ""  ## "life:3" / TAB_REMEMBERED / TAB_KEPT
## 服务器给的那一页：第几世 → Dictionary；取过但没有的记 false
var pages: Dictionary = {}
var _wide := false
var _built_width := 0.0
var _root: Control
var _page: VBoxContainer


func _init(main: Node) -> void:
	m = main
	name = "Ledger"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # 盖住底下的页面，点不穿


func _ready() -> void:
	var paper := ColorRect.new()
	paper.color = P.PAPER
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://shaders/paper.gdshader"):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/paper.gdshader")
		paper.material = mat
	add_child(paper)
	if m.net != null and m.net.has_signal("past_life"):
		m.net.past_life.connect(_on_past_life)
	var lives := life_numbers()
	tab = "life:%d" % lives[0] if not lives.is_empty() else TAB_REMEMBERED
	resized.connect(_on_resized)
	_build()
	_fetch()


func legacy() -> Dictionary:
	var lg: Variant = m.life.get("legacy")
	return lg if lg is Dictionary else {}


## 走完了的各世，新的在前
func life_numbers() -> Array:
	var out: Array = []
	for n in range(int(legacy().get("lives", 0)), 0, -1):
		out.append(n)
	return out


func close() -> void:
	queue_free()


func show_tab(id: String) -> void:
	if id == tab:
		return
	tab = id
	_build()
	_fetch()


# ----------------------------------------------------------------------
# 取数
# ----------------------------------------------------------------------

func _life_no() -> int:
	return int(tab.trim_prefix("life:")) if tab.begins_with("life:") else 0


func _fetch() -> void:
	var n := _life_no()
	if n <= 0 or pages.has(n) or m.net == null or not m.net.has_method("fetch_past"):
		return
	m.net.fetch_past(n)


func _on_past_life(life_no: int, page: Variant) -> void:
	pages[life_no] = page if page is Dictionary else false
	if _life_no() == life_no:
		_fill_page()


## 小传里的那一世（legacy.past 只留最近几世）
func _summary(n: int) -> Dictionary:
	var past: Variant = legacy().get("past")
	if past is Array:
		for it in past:
			if it is Dictionary and int(it.get("life", 0)) == n:
				return it
	return {}


## 这一世那一页：服务器给了就用服务器的，没有就拿小传凑成同一个样子。都没有返回空
func page_of(n: int) -> Dictionary:
	if pages.get(n) is Dictionary:
		return pages[n]
	var s := _summary(n)
	if s.is_empty():
		return {}
	var persons := {}
	var lives := {}
	var left := {}
	for r in ["qing", "mei"]:
		var p: Variant = s.get("persons", {}).get(r)
		if not p is Dictionary:
			persons[r] = null
			continue
		persons[r] = {"name": p.get("name", ""), "familyId": p.get("familyId"), "talentId": p.get("talentId"), "diedAtAge": p.get("diedAtAge"), "job": p.get("job"), "heirloomId": null}
		lives[r] = p.get("ending")
		left[r] = p.get("heirloom")
	var memories: Array = []
	for t in s.get("memories", []):
		memories.append({"title": str(t), "age": -1, "vivid": 1})
	return {"life": n, "ending": {"pair": s.get("pair"), "lives": lives}, "close": s.get("close", 0), "persons": persons,
		"memories": memories, "left": left, "noted": s.get("noted", []), "stats": null}


# ----------------------------------------------------------------------
# 内容表里查名字
# ----------------------------------------------------------------------

func _find(list: Variant, id: Variant) -> Dictionary:
	if id == null or not list is Array:
		return {}
	for it in list:
		if it is Dictionary and str(it.get("id", "")) == str(id):
			return it
	return {}


func _ending_title(kind: String, id: Variant) -> String:
	var endings: Variant = m.content.get("endings")
	return str(_find(endings.get(kind) if endings is Dictionary else null, id).get("title", ""))


func remembered(id: Variant) -> Dictionary:
	return _find(m.content.get("remembered"), id)


func _heirloom(id: Variant) -> Dictionary:
	return _find(m.content.get("heirlooms"), id)


## 这条人生线上街坊记住的事：[内容里的那一条, 第几世记住的]，先记住的在前
func remembered_list() -> Array:
	var got: Variant = legacy().get("remembered")
	var out: Array = []
	if not got is Dictionary:
		return out
	for a in m.content.get("remembered", []):
		if got.has(a.id):
			out.append([a, int(got[a.id])])
	out.sort_custom(func(x, y): return x[1] < y[1])
	return out


func kept_list() -> Array:
	var out: Array = []
	var ids: Variant = legacy().get("heirlooms")
	if ids is Array:
		for id in ids:
			var h := _heirloom(id)
			if not h.is_empty():
				out.append(h)
	return out


# ----------------------------------------------------------------------
# 版面
# ----------------------------------------------------------------------

func _on_resized() -> void:
	if (size.x > size.y) != _wide or absf(size.x - _built_width) > 1.0:
		_build()


## 横屏时刘海在左右两边（kit.gd 的 safe_sides，有就用）
func _safe() -> Vector2:
	var kit: Script = Kit
	for md in kit.get_script_method_list():
		if md.name == "safe_sides":
			var v: Variant = kit.call("safe_sides", self)
			return v if v is Vector2 else Vector2.ZERO
	return Vector2.ZERO


func _build() -> void:
	if _root != null:
		remove_child(_root)
		_root.queue_free()
	_wide = size.x > size.y
	_built_width = size.x
	var safe := _safe()
	# 长屏手机（20:9）比设计稿宽出来的那一截留在两边，翻开的那一页不跟着拉长
	var extra := maxf(0.0, size.x - safe.x - safe.y - MAX_WIDTH) if _wide else 0.0
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int((96 if _wide else 64) + safe.x + extra * 0.4))
	margin.add_theme_constant_override("margin_right", int((96 if _wide else 64) + safe.y + extra * 0.6))
	margin.add_theme_constant_override("margin_top", 72 if _wide else 130)
	margin.add_theme_constant_override("margin_bottom", 56 if _wide else 80)
	add_child(margin)
	_root = margin
	var split: BoxContainer = HBoxContainer.new() if _wide else VBoxContainer.new()
	split.add_theme_constant_override("separation", 72 if _wide else 30)
	margin.add_child(split)
	if _wide:
		_nav_column(split)
	else:
		_nav_row(split)
	var scroll := ScrollContainer.new()
	scroll.name = "PageScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 28)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 40)
	scroll.add_child(pad)
	_page = VBoxContainer.new()
	_page.name = "Page"
	_page.add_theme_constant_override("separation", 28)
	pad.add_child(_page)
	_fill_page()


func _title(box: Container) -> void:
	var t := Kit.label(box, "住户本", 96 if _wide else 84, P.INK)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


## 横屏：左边一栏目录
func _nav_column(split: Container) -> void:
	var col := VBoxContainer.new()
	col.name = "Nav"
	col.custom_minimum_size = Vector2(520, 0)
	col.add_theme_constant_override("separation", 10)
	split.add_child(col)
	_title(col)
	Kit.label(col, "这两扇门里住过的人。", 30, P.INK_SOFT)
	Kit.gap(col, 18)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for n in life_numbers():
		_nav_item(list, "life:%d" % n, "第 %d 世" % n, _life_line(n))
	Kit.gap(list, 10)
	_nav_item(list, TAB_REMEMBERED, "街坊记住的事", "")
	_nav_item(list, TAB_KEPT, "留着的老物件", "")
	var back := Kit.button(col, "合上", close)
	back.name = "Close"
	Kit.make_quiet(back)
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT


## 竖屏：顶上一行书名和「合上」，下面一排可以横着划的目录
func _nav_row(split: Container) -> void:
	var head := HBoxContainer.new()
	split.add_child(head)
	_title(head)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var back := Kit.button(head, "合上", close)
	back.name = "Close"
	Kit.make_quiet(back)
	back.autowrap_mode = TextServer.AUTOWRAP_OFF  # 收到最窄的时候不能把字折没了
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.size_flags_vertical = Control.SIZE_SHRINK_END
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.custom_minimum_size = Vector2(0, 104)
	split.add_child(scroll)
	var row := HBoxContainer.new()
	row.name = "Nav"
	row.add_theme_constant_override("separation", 14)
	scroll.add_child(row)
	for n in life_numbers():
		_nav_item(row, "life:%d" % n, "第 %d 世" % n, "")
	_nav_item(row, TAB_REMEMBERED, "记住的事", "")
	_nav_item(row, TAB_KEPT, "老物件", "")


## 目录里一世那一行的小字：结局的名字，两个人的名字
func _life_line(n: int) -> String:
	var s := _summary(n)
	if s.is_empty():
		return ""
	var parts: Array = []
	var title := _ending_title("pair", s.get("pair"))
	if title != "":
		parts.append("「%s」" % title)
	var who: Array = []
	for r in ["qing", "mei"]:
		var p: Variant = s.get("persons", {}).get(r)
		if p is Dictionary and str(p.get("name", "")) != "":
			who.append(str(p.name))
	if not who.is_empty():
		parts.append("、".join(who))
	return " ".join(parts)


## 目录里的一项。翻开的那一项是一张压着叠印色的纸签，别的只有字
func _nav_item(box: Container, id: String, text: String, sub: String) -> void:
	var on := id == tab
	var b := Button.new()
	b.name = "Tab_%s" % id.replace(":", "_")
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _wide else Control.SIZE_SHRINK_BEGIN
	var sb: StyleBox
	if on:
		var box_on := RisoBox.make(P.OVERLAP, 7.0, 0.0)
		box_on.line = 3.0
		sb = box_on
	else:
		sb = StyleBoxEmpty.new()
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 16
	sb.content_margin_bottom = 18
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	b.text = text if sub == "" else "%s\n%s" % [text, sub]
	b.add_theme_font_size_override("font_size", 38 if sub == "" else 34)
	b.add_theme_constant_override("line_spacing", 6)
	for c in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, P.INK if on else P.INK_SOFT)
	b.add_theme_color_override("font_hover_color", P.INK)
	b.pressed.connect(show_tab.bind(id))
	box.add_child(b)


# ----------------------------------------------------------------------
# 翻开的那一页
# ----------------------------------------------------------------------

func _fill_page() -> void:
	if _page == null:
		return
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()
	if tab == TAB_REMEMBERED:
		_page_remembered()
	elif tab == TAB_KEPT:
		_page_kept()
	else:
		_page_life(_life_no())


func _head(text: String, sub := "") -> void:
	var l := Kit.label(_page, text, 64, P.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	if sub != "":
		Kit.label(_page, sub, 30, P.INK_SOFT)
	Kit.rule(_page, P.INK, 3.0)


func _page_life(n: int) -> void:
	var pg := page_of(n)
	if pg.is_empty():
		_head("第 %d 世" % n)
		# 更早的几世只在服务器上：还没取回来是在翻，取过了没有就是没留下来
		Kit.label(_page, "这一页没有留下来。" if pages.has(n) else "正在翻……", 36, P.INK_SOFT)
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	_page.add_child(head)
	var chip := Kit.chip(head, "第 %d 世" % n, P.OVERLAP, 32)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ending: Dictionary = pg.get("ending") if pg.get("ending") is Dictionary else {}
	var title := _ending_title("pair", ending.get("pair"))
	var t := Kit.label(head, title if title != "" else "一生", 64, P.INK)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	Kit.rule(_page, P.INK, 3.0)

	# 两个人：横着拿并排，竖着拿上下
	var pair: BoxContainer = HBoxContainer.new() if _wide else VBoxContainer.new()
	pair.add_theme_constant_override("separation", 56 if _wide else 36)
	_page.add_child(pair)
	var lives: Dictionary = ending.get("lives") if ending.get("lives") is Dictionary else {}
	var left: Dictionary = pg.get("left") if pg.get("left") is Dictionary else {}
	for r in ["qing", "mei"]:
		var p: Variant = pg.get("persons", {}).get(r)
		if p is Dictionary:
			_person(pair, r, p, lives.get(r), left.get(r))

	var memories: Array = pg.get("memories") if pg.get("memories") is Array else []
	if not memories.is_empty():
		Kit.rule(_page, Color(P.INK, 0.5), 2.0)
		var mh := HBoxContainer.new()
		mh.add_theme_constant_override("separation", 20)
		_page.add_child(mh)
		Kit.chip(mh, "共同回忆", P.OVERLAP, 28).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var st: Variant = pg.get("stats")
		if st is Dictionary and int(st.get("mirrors", 0)) > 0:
			var sl := Kit.label(mh, rate_line(float(st.get("rate", 0))), 28, P.INK_SOFT)
			sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var flow := HFlowContainer.new()
		flow.name = "Memories"
		flow.add_theme_constant_override("h_separation", 36)
		flow.add_theme_constant_override("v_separation", 14)
		_page.add_child(flow)
		for mem in memories:
			_memory(flow, mem)

	var noted: Array = pg.get("noted") if pg.get("noted") is Array else []
	var shown: Array = noted.filter(func(id): return not remembered(id).is_empty())
	if not shown.is_empty():
		Kit.rule(_page, Color(P.INK, 0.5), 2.0)
		Kit.chip(_page, "这一世，街坊记住了", P.INK, 28)
		for id in shown:
			seal_row(_page, remembered(id), "")


## 默契率写成一句话：十回里有几回（数字写汉字，不和「十回」混排）
static func rate_line(rate: float) -> String:
	var n := clampi(int(round(rate / 10.0)), 0, 10)
	if n >= 10:
		return "遇到的事，回回都想到了一起"
	if n <= 0:
		return "遇到的事，没有一回想到一起"
	return "遇到的事，十回有%s回想到了一起" % "一二三四五六七八九"[n - 1]


func _person(box: Container, role: String, p: Dictionary, life_ending: Variant, left_id: Variant) -> void:
	var col := VBoxContainer.new()
	col.name = "Person_%s" % role
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	box.add_child(col)
	var color := P.role_color(role)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	col.add_child(head)
	var nm := str(p.get("name", ""))
	Kit.chip(head, nm if nm != "" else P.ROLE_NAME[role], color, 34).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if p.get("diedAtAge") != null:
		var age := Kit.label(head, "活到 %d 岁" % int(p.diedAtAge), 34, P.INK)
		age.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var born: Array = []
	var fam: Dictionary = m.families.get(str(p.get("familyId", "")), {})
	if not fam.is_empty():
		born.append(str(fam.get("name", "")))
	var tal: Dictionary = m.talents.get(str(p.get("talentId", "")), {})
	if not tal.is_empty():
		born.append(str(tal.get("name", "")))
	if not born.is_empty():
		_field(col, "生在", " · ".join(born))
	var job := str(JOB_NAME.get(str(p.get("job", "")), ""))
	if job != "":
		_field(col, "营生", job)
	var title := _ending_title("lives", life_ending)
	if title != "":
		_field(col, "一生", title, color)
	var brought := _heirloom(p.get("heirloomId"))
	if not brought.is_empty():
		_field(col, "带来", str(brought.get("name", "")))
	var left := _heirloom(left_id)
	if not left.is_empty():
		_field(col, "留下", str(left.get("name", "")))


## 表格里的一栏：前面一个小字的栏名，后面是填的内容
func _field(box: Container, key: String, value: String, color := P.INK) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	var k := Kit.label(row, key, 28, P.INK_SOFT)
	k.autowrap_mode = TextServer.AUTOWRAP_OFF
	k.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	k.custom_minimum_size = Vector2(72, 0)
	k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Kit.label(row, value, 36, color)


func _memory(flow: Container, mem: Variant) -> void:
	if not mem is Dictionary:
		return
	var vivid := int(mem.get("vivid", 0)) > 0
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	flow.add_child(row)
	row.add_child(_Dot.new(vivid))
	var age := int(mem.get("age", -1))
	var text := str(mem.get("title", ""))
	if age >= 0:
		text = "%d 岁 %s" % [age, text]
	var l := Kit.label(row, text, 32, P.INK if vivid else P.INK_SOFT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func _page_remembered() -> void:
	_head("街坊记住的事", "这两扇门里出过的事。")
	var list := remembered_list()
	if list.is_empty():
		Kit.label(_page, "街坊还没有记住什么。", 36, P.INK_SOFT)
		return
	for it in list:
		seal_row(_page, it[0], "第 %d 世" % it[1])


func _page_kept() -> void:
	_head("留着的老物件", "走的人留下的。下一世可以各带一件。")
	var list := kept_list()
	if list.is_empty():
		Kit.label(_page, "河畔里还没有留下什么。", 36, P.INK_SOFT)
		return
	var grid := GridContainer.new()
	grid.columns = 2 if _wide else 1
	grid.add_theme_constant_override("h_separation", 64)
	grid.add_theme_constant_override("v_separation", 30)
	_page.add_child(grid)
	for h in list:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 6)
		grid.add_child(col)
		Kit.label(col, str(h.get("name", "")), 42, P.INK)
		Kit.label(col, str(h.get("desc", "")), 30, P.INK_SOFT)


## 一枚章和旁边的一句话。结局页（legacy_ui.gd）也用它
static func seal_row(box: Container, a: Dictionary, tail: String) -> void:
	var row := HBoxContainer.new()
	row.name = "Seal_%s" % str(a.get("id", ""))
	row.add_theme_constant_override("separation", 30)
	box.add_child(row)
	row.add_child(Seal.new(str(a.get("title", ""))))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	Kit.label(col, str(a.get("desc", "")), 34, P.INK)
	if tail != "":
		Kit.label(col, tail, 26, P.INK_SOFT)


## 街坊盖的章：一个印歪了一点的方框，里面是那件事的名字。每枚歪的角度由名字定，不会每次重画都变
class Seal extends Control:
	const P := preload("res://scripts/ui/palette.gd")
	const SIZE := 40
	var text := ""

	func _init(p_text: String) -> void:
		text = p_text
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w := P.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
		custom_minimum_size = Vector2(maxf(w + 56.0, 216.0), 92.0)  # 四个字以内的一样宽，旁边的话才对得齐
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var f := P.font()
		var tilt := (float(text.hash() % 7) - 3.0) * 0.012
		draw_set_transform(size / 2.0, tilt, Vector2.ONE)
		var half := size / 2.0 - Vector2(8, 10)
		var box := Rect2(-half, half * 2.0)
		# 印泥没蘸匀：先印一层错开的淡色，再印框和字
		draw_rect(Rect2(box.position + Vector2(4, 4), box.size), Color(P.MEI, 0.16), true)
		draw_rect(box, P.MEI, false, 4.0, true)
		draw_rect(box.grow(-7.0), Color(P.MEI, 0.7), false, 1.5, true)
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
		draw_string(f, Vector2(-w / 2.0, SIZE * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, P.MEI)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 回忆前面的小圆点：记得清的是实心叠印色，褪了色的只剩一个圈（和结局页的时间线一个画法）
class _Dot extends Control:
	const P := preload("res://scripts/ui/palette.gd")
	var vivid := true

	func _init(p_vivid: bool) -> void:
		vivid = p_vivid
		custom_minimum_size = Vector2(22, 22)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		if vivid:
			draw_circle(c + Vector2(2, 2), 8.0, P.MEI, true, -1.0, true)
			draw_circle(c, 8.0, P.OVERLAP, true, -1.0, true)
		else:
			draw_arc(c, 7.0, 0, TAU, 20, P.INK_SOFT, 2.0, true)
