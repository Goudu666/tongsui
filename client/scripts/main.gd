extends Control
## 《同岁》入口。M0 原型：界面全部用代码搭，方便早期快速改。
## 两种模式：
##   同屏双人：一台手机两个人轮流选（默契时刻会先遮住屏幕再交给对方）
##   联机：两台手机，服务器权威结算（需要 nakama-godot 插件与服务器）

const Life := preload("res://scripts/sim/local_life.gd")
const P := preload("res://scripts/ui/palette.gd")
const NetClient := preload("res://scripts/net/lifeline_client.gd")

const FONT_PATH := "res://fonts/LXGWWenKai-Regular.ttf"

var body: VBoxContainer
var events: Array = []
var events_by_id: Dictionary = {}

# 同屏模式
var life: Life
var pending: Dictionary = {}
var queue: Array = []

# 联机模式
var net: NetClient
var net_state: Dictionary = {}
var net_role := ""


func _ready() -> void:
	theme = _make_theme()
	events = Life.load_events()
	for ev in events:
		events_by_id[ev.id] = ev
	events_by_id["_ordinary"] = Life.ordinary_event()

	var paper := ColorRect.new()
	paper.color = P.PAPER
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/paper.gdshader")
	paper.material = mat
	add_child(paper)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 160)
	margin.add_theme_constant_override("margin_bottom", 120)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 32)
	scroll.add_child(body)

	_show_title()


# ======================================================================
# 主题与小部件
# ======================================================================

func _make_theme() -> Theme:
	var th := Theme.new()
	if ResourceLoader.exists(FONT_PATH):
		th.default_font = load(FONT_PATH)
	th.default_font_size = 40

	var normal := StyleBoxFlat.new()
	normal.bg_color = P.PAPER
	normal.border_color = P.INK
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 40
	normal.content_margin_right = 40
	normal.content_margin_top = 28
	normal.content_margin_bottom = 28
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = P.PAPER.darkened(0.06)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = P.INK
	th.set_stylebox("normal", "Button", normal)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", pressed)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		th.set_color(c, "Button", P.INK)
	th.set_color("font_pressed_color", "Button", P.PAPER)

	var edit := normal.duplicate() as StyleBoxFlat
	edit.border_width_top = 0
	edit.border_width_left = 0
	edit.border_width_right = 0
	th.set_stylebox("normal", "LineEdit", edit)
	th.set_stylebox("focus", "LineEdit", edit)
	th.set_color("font_color", "LineEdit", P.INK)
	th.set_color("font_placeholder_color", "LineEdit", P.INK_SOFT)
	th.set_color("caret_color", "LineEdit", P.INK)

	th.set_color("font_color", "Label", P.INK)
	return th


func _clear() -> void:
	for c in body.get_children():
		body.remove_child(c)  # 立刻移除，避免与新节点重名（如 Status）
		c.queue_free()


func _label(text: String, font_size := 40, color := P.INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(l)
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_press)
	body.add_child(b)
	return b


func _gap(h := 40) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	body.add_child(c)


func _status_label() -> Label:
	var l := _label("", 32, P.INK_SOFT)
	l.name = "Status"
	return l


func _role_text(role: String, names: Dictionary) -> String:
	var n: String = str(names.get(role, P.ROLE_NAME[role]))
	return "「%s」" % n


# ======================================================================
# 标题
# ======================================================================

func _show_title() -> void:
	_clear()
	_gap(260)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	for pair in [["同", P.QING], ["岁", P.MEI]]:
		var l := Label.new()
		l.text = pair[0]
		l.add_theme_font_size_override("font_size", 200)
		l.add_theme_color_override("font_color", pair[1])
		row.add_child(l)
	body.add_child(row)
	_label("同一条巷子，同一年出生，同一生。", 40, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_gap(240)
	if events.is_empty():
		_label("没有找到 data/events.json，请先在仓库根目录运行 npm run content", 32, P.MEI)
		return
	_button("同屏双人 · 一台手机，轮流选择", _start_local)
	_button("联机 · 两台手机", _show_online)


# ======================================================================
# 同屏双人
# ======================================================================

func _start_local() -> void:
	life = Life.new({"qing": "青", "mei": "梅"}, randi(), events)
	_start_turn()


func _start_turn() -> void:
	if life.ended:
		_show_ending(life.history, life.memories)
		return
	pending = {}
	queue = life.required_roles()
	_next_in_queue()


func _next_in_queue() -> void:
	if queue.is_empty():
		_show_result(life.resolve(pending), {"qing": "青", "mei": "梅"}, _start_turn)
		return
	var role: String = queue.pop_front()
	var needs_cover := life.required_roles().size() > 1
	if needs_cover:
		_show_cover(role)
	else:
		_show_local_choice(role)


func _show_cover(role: String) -> void:
	_clear()
	_gap(360)
	_label("把手机交给", 44, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_role_text(role, {}), 120, P.role_color(role), HORIZONTAL_ALIGNMENT_CENTER)
	_label("另一个人请先别看", 36, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_gap(160)
	_button("我是%s，开始" % P.ROLE_NAME[role], func(): _show_local_choice(role))


func _show_local_choice(role: String) -> void:
	var ev := life.event_for(role)
	_render_choice(role, ev, life.now().label, life.bond, _on_local_pick.bind(role))


func _on_local_pick(option_id: String, role: String) -> void:
	pending[role] = option_id
	_next_in_queue()


# ======================================================================
# 通用渲染：选择 / 结果 / 结局（同屏与联机共用）
# ======================================================================

func _render_header(label: String, bond: Dictionary) -> void:
	_label(label, 36, P.INK_SOFT)
	_label("默契 %d   亲近 %d   距离 %d" % [int(bond.sync), int(bond.close), int(bond.distance)], 30, P.INK_SOFT)
	_gap(24)


func _render_choice(role: String, ev: Dictionary, label: String, bond: Dictionary, on_pick: Callable) -> void:
	_clear()
	_render_header(label, bond)
	var tag := "%s的回合" % _role_text(role, {})
	if ev.kind == "mirror":
		tag += "  ·  默契时刻，不要商量"
	_label(tag, 32, P.role_color(role))
	_label(str(ev.title), 72)
	_label(str(ev.text), 42)
	_gap(40)
	for o in ev.options:
		var oid: String = o.id
		_button(str(o.text), func(): on_pick.call(oid))


func _option_text(event_id: Variant, option_id: Variant) -> String:
	if event_id == null or option_id == null:
		return ""
	var ev: Dictionary = events_by_id.get(event_id, {})
	for o in ev.get("options", []):
		if o.id == option_id:
			return str(o.text)
	return str(option_id)


func _event_title(event_id: Variant) -> String:
	var ev: Dictionary = events_by_id.get(event_id, {})
	return str(ev.get("title", ""))


func _show_result(entries: Array, names: Dictionary, on_next: Callable) -> void:
	_clear()
	for e in entries:
		_label(str(e.label), 36, P.INK_SOFT)
		if e.kind == "mirror":
			_label(_event_title(e.events.qing), 64)
			for r in ["qing", "mei"]:
				var shadow_mark := "（影子）" if e.get("shadow", []).has(r) else ""
				_label("%s %s%s" % [_role_text(r, names), _option_text(e.events[r], e.choices[r]), shadow_mark], 38, P.role_color(r))
			var tone := P.OVERLAP if e.resonance else P.INK_SOFT
			_label(("共鸣 · " if e.resonance else "错位 · ") + str(e.text), 44, tone)
		elif e.kind == "solo":
			for r in ["qing", "mei"]:
				if e.events[r] == null:
					continue
				_label("%s %s：%s" % [_role_text(r, names), _event_title(e.events[r]), _option_text(e.events[r], e.choices[r])], 38, P.role_color(r))
		else:
			_label(str(e.text), 48, P.INK)
		_gap(24)
	_gap(40)
	_button("继续", on_next)


func _show_ending(history: Array, memories: Array) -> void:
	_clear()
	_gap(120)
	_label("一生", 96, P.OVERLAP, HORIZONTAL_ALIGNMENT_CENTER)
	for e in history:
		if e.kind == "end":
			_label(str(e.text), 40, P.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_gap(40)
	_label("共同回忆", 48)
	if memories.is_empty():
		_label("（你们没有在同一件事上选到一起过）", 36, P.INK_SOFT)
	for m in memories:
		var faded := "" if int(m.vivid) > 0 else "（已褪色）"
		_label("%d 岁 · %s%s" % [int(m.age), m.title, faded], 38, P.OVERLAP if int(m.vivid) > 0 else P.INK_SOFT)
	_gap(60)
	_button("回到巷口", _show_title)


# ======================================================================
# 联机
# ======================================================================

func _show_online() -> void:
	_clear()
	_gap(120)
	_label("联机", 96)
	if not NetClient.addon_available():
		_label("还没有安装 nakama-godot 插件。\n在仓库根目录运行 tools/fetch_addons.sh，再在 项目设置 → 插件 中启用 Nakama。", 36, P.MEI)
		_button("返回", _show_title)
		return
	if net == null:
		net = NetClient.new()
		add_child(net)
		net.status.connect(_on_net_status)
		net.failed.connect(_on_net_status)
		net.created.connect(_on_net_created)
		net.snapshot.connect(_on_net_snapshot)
		net.resolved.connect(_on_net_resolved)
		net.progress.connect(_on_net_progress)
		var ok: bool = await net.connect_server()
		if not ok:
			_button("返回", _show_title)
			return

	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "你的名字（最多 12 个字）"
	name_edit.max_length = 12
	body.add_child(name_edit)
	_button("创建一条人生线（我是青）", func(): net.create_lifeline(name_edit.text))
	_gap(20)
	var code_edit := LineEdit.new()
	code_edit.placeholder_text = "输入 TA 发给你的 6 位配对码"
	code_edit.max_length = 6
	body.add_child(code_edit)
	_button("加入（我是梅）", func(): net.join_lifeline(code_edit.text.strip_edges(), name_edit.text))
	_gap(20)
	_status_label()
	_button("返回", _show_title)


func _on_net_status(text: String) -> void:
	var s := body.get_node_or_null("Status") as Label
	if s:
		s.text = text
	else:
		var sl := _status_label()
		sl.text = text


func _on_net_created(code: String, lifeline_id: String) -> void:
	_clear()
	_gap(240)
	_label("把这串配对码发给 TA", 40, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(code, 140, P.QING, HORIZONTAL_ALIGNMENT_CENTER)
	_label("TA 加入后，点下面的按钮进入", 34, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_gap(80)
	_button("进入人生线", func(): net.open_lifeline(lifeline_id))
	_status_label()


func _on_net_snapshot(data: Dictionary) -> void:
	net_state = data
	net_role = str(data.you)
	_render_net_turn()


func _on_net_resolved(data: Dictionary) -> void:
	var st: Dictionary = data.state
	net_state.life = st.life
	net_state.names = st.names
	_show_result(data.entries, st.names, _render_net_turn)


func _on_net_progress(data: Dictionary) -> void:
	net_state.progress = data
	var s := body.get_node_or_null("Status") as Label
	if s:
		var other := Life.other(net_role)
		var parts: PackedStringArray = []
		if not data.online[other]:
			parts.append("TA 不在线，30 秒后由 TA 的影子替 TA 选择")
		elif data.chosen[other]:
			parts.append("TA 已经选好了")
		s.text = "，".join(parts)


func _render_net_turn() -> void:
	var lf: Dictionary = net_state.life
	if lf.ended:
		_show_ending(lf.log, lf.memories)
		return
	var event_id: Variant = lf.scene.events[net_role]
	var label: String = Life.time_at(int(lf.turn)).label
	if event_id == null:
		_clear()
		_render_header(label, lf.bond)
		_label("你已经离开了。你在看着 TA 走完剩下的路。", 44, P.INK_SOFT)
		_status_label()
		return
	var ev: Dictionary = events_by_id.get(event_id, {})
	_render_choice(net_role, ev, label, lf.bond, _on_net_pick.bind(event_id, label, lf.bond))


func _on_net_pick(option_id: String, event_id: Variant, label: String, bond: Dictionary) -> void:
	net.choose(option_id)
	_clear()
	_render_header(label, bond)
	_label("你选了：%s" % _option_text(event_id, option_id), 44, P.role_color(net_role))
	_label("等 TA……", 40, P.INK_SOFT)
	_status_label()
