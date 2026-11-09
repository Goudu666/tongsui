extends Node
## 《同岁》入口：界面流程 + 联机消息分发。
##   标题 → 联机大厅（创建/输入配对码）→ 抽卡（家庭、天赋、属性）→ 河畔里（实时走动）→ 一生
## 另有「先逛逛」：不联网，只能走动，用来调地图和美术。
## 界面全部用代码搭（M0），层级：
##   背景纸张（CanvasLayer -10）→ 世界（Node2D + Camera2D）→ UI（CanvasLayer 1：screen / hud / modal / toast）

const P := preload("res://scripts/ui/palette.gd")
const LifeTime := preload("res://scripts/ui/life_time.gd")
const NetClient := preload("res://scripts/net/lifeline_client.gd")
const WorldView := preload("res://scripts/world/world_view.gd")
const ServerConfig := preload("res://scripts/net/config.gd")
const ServerSettings := preload("res://scripts/ui/server_settings.gd")

var content: Dictionary = {}
var events_by_id: Dictionary = {}
var families: Dictionary = {}
var talents: Dictionary = {}

var ui: Control
var screen: ColorRect    ## 全屏菜单页
var body: VBoxContainer  ## screen 里的内容
var hud: Control
var hud_time: Label
var hud_needs: Label
var hud_bond: Label
var action_btn: Button
var modal: ColorRect
var modal_body: VBoxContainer
var toast: Label
var _toast_tween: Tween

var world: WorldView
var net: NetClient
var names: Dictionary = {"qing": "青", "mei": "梅"}
var my_role := "qing"
var life: Dictionary = {}
var last_world: Dictionary = {}
var offline_preview := false
var _preview_minute := 390.0


func _ready() -> void:
	_load_content()
	_build_layers()
	_show_title()


func _load_content() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))
	if parsed is Dictionary:
		content = parsed
		for ev in content.events:
			events_by_id[ev.id] = ev
		for f in content.families:
			families[f.id] = f
		for t in content.talents:
			talents[t.id] = t


func _other() -> String:
	return "mei" if my_role == "qing" else "qing"


# ======================================================================
# 层级与小部件
# ======================================================================

func _build_layers() -> void:
	var bg := CanvasLayer.new()
	bg.layer = -10
	add_child(bg)
	var paper := ColorRect.new()
	paper.color = P.PAPER
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/paper.gdshader")
	paper.material = mat
	bg.add_child(paper)

	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = _make_theme()
	layer.add_child(ui)

	# 全屏菜单
	screen = ColorRect.new()
	screen.color = Color(0, 0, 0, 0)  # 透出底下带颗粒的纸
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(screen)
	body = _scroll_column(screen, 80, 160)

	# 世界里的 HUD（不挡点击）
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	ui.add_child(hud)
	var top := VBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.position = Vector2(48, 72)
	top.size = Vector2(984, 260)
	hud.add_child(top)
	hud_time = _label(top, "", 40)
	hud_needs = _label(top, "", 30, P.INK)
	hud_bond = _label(top, "", 28, P.INK_SOFT)
	action_btn = Button.new()
	action_btn.anchor_left = 0.5
	action_btn.anchor_right = 0.5
	action_btn.anchor_top = 1.0
	action_btn.anchor_bottom = 1.0
	action_btn.offset_left = -360
	action_btn.offset_right = 360
	action_btn.offset_top = -230
	action_btn.offset_bottom = -110
	action_btn.visible = false
	action_btn.pressed.connect(_on_action_pressed)
	hud.add_child(action_btn)

	# 弹窗（事件、结算、一天结束）
	modal = ColorRect.new()
	modal.color = Color(P.INK, 0.35)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.visible = false
	ui.add_child(modal)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = P.PAPER
	sb.border_color = P.INK
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(56)
	card.add_theme_stylebox_override("panel", sb)
	card.anchor_left = 0.0
	card.anchor_right = 1.0
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = 48
	card.offset_right = -48
	card.offset_top = -560
	card.offset_bottom = 560
	modal.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	modal_body = VBoxContainer.new()
	modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_body.add_theme_constant_override("separation", 28)
	scroll.add_child(modal_body)

	toast = Label.new()
	toast.anchor_left = 0.0
	toast.anchor_right = 1.0
	toast.anchor_top = 0.62
	toast.anchor_bottom = 0.62
	toast.offset_left = 80
	toast.offset_right = -80
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.add_theme_font_size_override("font_size", 36)
	toast.add_theme_color_override("font_color", P.OVERLAP)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.modulate.a = 0.0
	ui.add_child(toast)


func _scroll_column(parent: Control, side: int, top: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", side)
	margin.add_theme_constant_override("margin_right", side)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_bottom", 120)
	parent.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 30)
	scroll.add_child(col)
	return col


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = P.font()
	th.default_font_size = 40
	var normal := StyleBoxFlat.new()
	normal.bg_color = P.PAPER
	normal.border_color = P.INK
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 40
	normal.content_margin_right = 40
	normal.content_margin_top = 26
	normal.content_margin_bottom = 26
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = P.PAPER.darkened(0.06)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = P.INK
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.border_color = P.INK_SOFT
	th.set_stylebox("normal", "Button", normal)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", pressed)
	th.set_stylebox("disabled", "Button", disabled)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		th.set_color(c, "Button", P.INK)
	th.set_color("font_pressed_color", "Button", P.PAPER)
	th.set_color("font_disabled_color", "Button", P.INK_SOFT)
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


func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)  # 立刻移除，避免与新节点重名
		c.queue_free()


func _label(parent: Container, text: String, font_size := 40, color := P.INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _button(parent: Container, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _gap(parent: Container, h := 40) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)


func _status(parent: Container) -> Label:
	var l := _label(parent, "", 32, P.INK_SOFT)
	l.name = "Status"
	return l


func _set_status(text: String) -> void:
	var s := body.get_node_or_null("Status") as Label
	if s == null:
		s = _status(body)
	s.text = text


func _toast(text: String) -> void:
	toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.4)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.8)


func _bar(v: float) -> String:
	var n := clampi(int(round(v / 10.0)), 0, 10)
	return "■".repeat(n) + "□".repeat(10 - n)


func _role_text(role: String) -> String:
	return "「%s」" % str(names.get(role, P.ROLE_NAME[role]))


func _show_screen() -> void:
	screen.visible = true
	hud.visible = false
	modal.visible = false
	_clear(body)


# ======================================================================
# 标题
# ======================================================================

func _show_title() -> void:
	_leave_world()
	_show_screen()
	_gap(body, 240)
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
	_label(body, "同一栋楼，同一年出生，同一生。", 40, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(body, "天津 · 河畔里", 32, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_gap(body, 200)
	if content.is_empty():
		_label(body, "没有找到 data/content.json，请先在仓库根目录运行 npm run content", 32, P.MEI)
		return
	_button(body, "联机 · 和 TA 一起过一辈子", _show_online)
	_button(body, "先逛逛河畔里（不联网）", _start_preview)


# ======================================================================
# 离线逛逛：只能走动，用来看地图
# ======================================================================

func _start_preview() -> void:
	offline_preview = true
	my_role = "qing"
	names = {"qing": "青", "mei": "梅"}
	life = {"turn": 0}
	last_world = {}
	_enter_world()
	_preview_minute = 390.0
	_toast("点哪儿走哪儿。联网之后才能做事情、遇到事。")


func _process(delta: float) -> void:
	if world == null:
		return
	if offline_preview:
		_preview_minute = fmod(_preview_minute + delta * 4.0 - 390.0, 930.0) + 390.0
		hud_time.text = "%s · %s · 预览" % [LifeTime.at(0).label, P.clock(_preview_minute)]
	world.controllable = not modal.visible and not screen.visible
	var spot := world.nearest_spot()
	if spot.is_empty() or modal.visible:
		action_btn.visible = false
		return
	var act := world.action_of(spot)
	var cost := ""
	if bool(act.get("sleep", false)):
		cost = "（结束这一天）"
	elif bool(act.get("school", false)):
		cost = "（到 15:30）"
	elif int(act.get("minutes", 0)) > 0:
		cost = " · %d 分钟" % int(act.minutes)
	if int(act.get("money", 0)) < 0:
		cost += " · %d 块" % -int(act.money)
	action_btn.text = str(act.get("label", "")) + cost
	action_btn.set_meta("spot", spot.id)
	action_btn.disabled = offline_preview
	action_btn.visible = true


func _on_action_pressed() -> void:
	if net != null and action_btn.has_meta("spot"):
		net.act(str(action_btn.get_meta("spot")))


func _on_move_report(pos: Vector2) -> void:
	if net != null and not offline_preview:
		net.move(pos)


# ======================================================================
# 联机大厅
# ======================================================================

func _show_online() -> void:
	_show_screen()
	_gap(body, 120)
	_label(body, "联机", 96)
	if not NetClient.addon_available():
		_label(body, "还没有安装 nakama-godot 插件。\n在仓库根目录运行 tools/fetch_addons.sh，然后用 Godot 重新打开项目。", 36, P.MEI)
		_button(body, "返回", _show_title)
		return
	if net != null and (net.socket == null or not net.socket.is_connected_to_host()):
		_drop_net()  # 没连上或者断线了（比如手机锁屏太久）：重新连
	if net == null:
		net = NetClient.new()
		add_child(net)
		net.status.connect(_set_status)
		net.failed.connect(_on_net_failed)
		net.created.connect(_on_net_created)
		net.snapshot.connect(_on_snapshot)
		net.roll_state.connect(_on_roll_state)
		net.world_state.connect(_on_world_state)
		net.event_started.connect(_on_event_started)
		net.log_entries.connect(_on_log_entries)
		net.presence.connect(_on_presence)
		_label(body, "服务器：%s" % ServerConfig.url(), 28, P.INK_SOFT)
		_status(body)
		_button(body, "服务器设置", _show_server_settings)
		_button(body, "返回", _show_title)
		var connecting := net
		var ok: bool = await net.connect_server()
		if net != connecting:
			return  # 连接期间改了服务器设置，这次的结果作废
		if not ok:
			_drop_net()  # 停在这一页，状态栏显示失败原因；可以去改服务器设置
			return
		if body.get_node_or_null("Status") != null:  # 还停在联机页才刷新
			_show_online()
		return

	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "你的名字（最多 12 个字）"
	name_edit.max_length = 12
	body.add_child(name_edit)
	_button(body, "开一条人生线（我是青）", func(): net.create_lifeline(name_edit.text))
	_gap(body, 20)
	var code_edit := LineEdit.new()
	code_edit.placeholder_text = "输入 TA 发给你的 6 位配对码"
	code_edit.max_length = 6
	body.add_child(code_edit)
	_button(body, "加入（我是梅）", func(): net.join_lifeline(code_edit.text.strip_edges(), name_edit.text))
	_gap(body, 20)
	_status(body)
	_label(body, "服务器：%s" % ServerConfig.url(), 28, P.INK_SOFT)
	_button(body, "服务器设置", _show_server_settings)
	_button(body, "返回", _show_title)


func _show_server_settings() -> void:
	_show_screen()
	_gap(body, 120)
	var panel := ServerSettings.new()
	panel.done.connect(func(changed: bool):
		if changed:
			_drop_net()
		_show_online())
	body.add_child(panel)


func _drop_net() -> void:
	if net != null:
		if net.socket != null:
			net.socket.close()
		net.queue_free()
		net = null


func _on_net_failed(text: String) -> void:
	if screen.visible:
		_set_status(text)
	else:
		_toast(text)


func _on_net_created(code: String, lifeline_id: String) -> void:
	_show_screen()
	_gap(body, 240)
	_label(body, "把配对码发给 TA", 40, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(body, code, 140, P.QING, HORIZONTAL_ALIGNMENT_CENTER)
	_label(body, "TA 加入后，点下面进入", 34, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_gap(body, 80)
	_button(body, "进入", func(): net.open_lifeline(lifeline_id))
	_status(body)


func _on_presence(data: Dictionary) -> void:
	if world != null and not offline_preview:
		_toast("TA 上线了" if data.online[_other()] else "TA 下线了，TA 的影子会替 TA 过日子")


# ======================================================================
# 快照：决定现在该显示哪一页
# ======================================================================

func _on_snapshot(data: Dictionary) -> void:
	names = data.names
	my_role = str(data.you)
	life = data.life
	match str(life.phase):
		"roll":
			_show_roll()
		"life":
			if world == null:
				_enter_world()
			_refresh_hud()
		"ended":
			_show_ending()


# ======================================================================
# 抽卡：家庭、天赋、属性
# ======================================================================

func _on_roll_state(data: Dictionary) -> void:
	life.rolls = data.rolls
	if str(life.get("phase", "")) == "roll":
		_show_roll()


func _show_roll() -> void:
	_show_screen()
	var mine: Dictionary = life.rolls[my_role]
	var theirs: Dictionary = life.rolls[_other()]
	_label(body, "你出生在……", 40, P.INK_SOFT)
	_roll_card(body, my_role, mine, true)
	if bool(mine.confirmed):
		_label(body, "就这样了。等 TA 也定下来……", 36, P.INK_SOFT)
	else:
		var b := _button(body, "重新投胎（还剩 %d 次）" % int(mine.rerollsLeft), func(): net.reroll())
		b.disabled = int(mine.rerollsLeft) <= 0
		_button(body, "就这样，出生吧", func(): net.confirm_roll())
	_gap(body, 30)
	_label(body, "对门是", 32, P.INK_SOFT)
	_roll_card(body, _other(), theirs, false)
	_label(body, "TA 已经定下来了" if bool(theirs.confirmed) else "TA 还在犹豫", 30, P.INK_SOFT)
	_status(body)


func _roll_card(parent: Container, role: String, r: Dictionary, full: bool) -> void:
	var fam: Dictionary = families.get(r.familyId, {})
	var tal: Dictionary = talents.get(r.talentId, {})
	_label(parent, "%s %s" % [_role_text(role), str(fam.get("name", r.familyId))], 56 if full else 40, P.role_color(role))
	_label(parent, "%s · 零花钱 %d 块" % [P.WEALTH_NAME[int(fam.get("wealth", 1))], int(fam.get("money", 0))], 30, P.INK_SOFT)
	if full:
		_label(parent, str(fam.get("desc", "")), 36)
	var talent_line := "天赋：%s" % str(tal.get("name", r.talentId))
	if full:
		talent_line += "　" + str(tal.get("desc", ""))
	_label(parent, talent_line, 34 if full else 30, P.OVERLAP)
	var lines: PackedStringArray = []
	for k in ["body", "mind", "charm", "luck"]:
		var v := float(r.stats[k])
		lines.append("%s %s %d" % [P.STAT_NAME[k], _bar(v * 10.0), int(v)])
	_label(parent, "\n".join(lines), 34 if full else 28, P.INK)


# ======================================================================
# 河畔里
# ======================================================================

func _enter_world() -> void:
	screen.visible = false
	modal.visible = false
	hud.visible = true
	world = WorldView.new()
	add_child(world)
	world.setup(content, my_role, names)
	world.move_report.connect(_on_move_report)
	_refresh_hud()


func _leave_world() -> void:
	offline_preview = false
	if world != null:
		world.queue_free()
		world = null
	hud.visible = false


func _refresh_hud() -> void:
	if offline_preview:
		hud_needs.text = ""
		hud_bond.text = ""
		return
	var t := LifeTime.at(int(life.get("turn", 0)))
	var minute := float(last_world.get("minute", 390))
	var school := " · 上学日" if bool(last_world.get("schoolDay", false)) else ""
	hud_time.text = "%s · %s%s" % [t.label, P.clock(minute), school]
	var needs: Dictionary = last_world.get("needs", {}).get(my_role, {})
	if needs.is_empty() and life.get("persons") != null:
		needs = life.persons[my_role].needs
	var parts: PackedStringArray = []
	for k in ["hunger", "energy", "mood", "clean"]:
		parts.append("%s %s" % [P.NEED_NAME[k], _bar(float(needs.get(k, 0)))])
	var money := int(last_world.get("money", {}).get(my_role, 0))
	hud_needs.text = "  ".join(parts.slice(0, 2)) + "\n" + "  ".join(parts.slice(2, 4)) + "\n零花钱 %d 块" % money
	var bond: Dictionary = last_world.get("bond", life.get("bond", {}))
	hud_bond.text = "默契 %d   亲近 %d" % [int(bond.get("sync", 0)), int(bond.get("close", 0))]


func _on_world_state(data: Dictionary) -> void:
	last_world = data
	if world != null:
		world.apply_world(data)
		_refresh_hud()
	var ev: Variant = data.get("event")
	if ev != null and modal.visible and modal.has_meta("waiting_event"):
		var s := modal_body.get_node_or_null("Status") as Label
		if s != null and ev.roles.has(_other()):
			s.text = "TA 已经选好了" if ev.chosen[_other()] else "TA 还在想……"


# ======================================================================
# 事件
# ======================================================================

func _on_event_started(data: Dictionary) -> void:
	var pe: Dictionary = data.event
	if not pe.roles.has(my_role):
		_toast("TA 那边好像遇到了一件事……")
		return
	var ev: Dictionary = events_by_id.get(pe.eventId, {})
	var mirror: bool = pe.kind == "mirror"
	_open_modal()
	modal.set_meta("waiting_event", pe.eventId)
	if mirror:
		_label(modal_body, "默契时刻 · 不要商量", 30, P.role_color(my_role))
	_label(modal_body, str(ev.get("title", "")), 68)
	_label(modal_body, str(ev.get("text", "")), 40)
	_gap(modal_body, 20)
	for o in ev.get("options", []):
		var oid: String = o.id
		var otext: String = o.text
		_button(modal_body, otext, _pick.bind(oid, otext, mirror))


func _pick(option_id: String, option_text: String, mirror: bool) -> void:
	net.choose(option_id)
	_clear(modal_body)
	_label(modal_body, "你选了", 32, P.INK_SOFT)
	_label(modal_body, option_text, 48, P.role_color(my_role))
	if mirror:
		_label(modal_body, "等 TA……", 36, P.INK_SOFT)
		var s := _status(modal_body)
		s.text = "TA 还在想……"


func _open_modal() -> void:
	_clear(modal_body)
	if modal.has_meta("waiting_event"):
		modal.remove_meta("waiting_event")
	modal.visible = true
	action_btn.visible = false


func _close_modal() -> void:
	modal.visible = false
	if modal.has_meta("waiting_event"):
		modal.remove_meta("waiting_event")


func _option_text(event_id: Variant, option_id: Variant) -> String:
	if event_id == null or option_id == null:
		return ""
	var ev: Dictionary = events_by_id.get(event_id, {})
	for o in ev.get("options", []):
		if o.id == option_id:
			return str(o.text)
	return str(option_id)


func _on_log_entries(data: Dictionary) -> void:
	for e in data.entries:
		var kind := str(e.kind)
		if kind == "together":
			_toast("同框 · " + str(e.text))
		elif kind == "mirror":
			_show_mirror_result(e)
		elif kind == "solo":
			if e.events[my_role] != null:
				_close_modal()
			else:
				var other := _other()
				var ev: Dictionary = events_by_id.get(e.events[other], {})
				_toast("TA 遇到了「%s」，选了：%s" % [str(ev.get("title", "")), _option_text(e.events[other], e.choices[other])])
		elif kind == "day":
			_open_modal()
			_label(modal_body, str(e.label), 34, P.INK_SOFT)
			_label(modal_body, str(e.text), 44)
			_label(modal_body, "日子一天天过去……", 32, P.INK_SOFT)
			_button(modal_body, "下一个被记住的日子", _close_modal)
		elif kind == "death":
			_open_modal()
			_label(modal_body, str(e.text), 52, P.OVERLAP)
			_button(modal_body, "……", _close_modal)


func _show_mirror_result(e: Dictionary) -> void:
	_open_modal()
	var ev: Dictionary = events_by_id.get(e.events.qing, {})
	_label(modal_body, str(e.label), 30, P.INK_SOFT)
	_label(modal_body, str(ev.get("title", "")), 64)
	for r in ["qing", "mei"]:
		var mark := "（影子）" if e.shadow.has(r) else ""
		_label(modal_body, "%s %s%s" % [_role_text(r), _option_text(e.events[r], e.choices[r]), mark], 38, P.role_color(r))
	var hit := bool(e.resonance)
	_label(modal_body, ("共鸣 · " if hit else "错位 · ") + str(e.text), 44, P.OVERLAP if hit else P.INK_SOFT)
	_button(modal_body, "嗯", _close_modal)


# ======================================================================
# 一生
# ======================================================================

func _show_ending() -> void:
	_leave_world()
	_show_screen()
	_gap(body, 80)
	_label(body, "一生", 96, P.OVERLAP, HORIZONTAL_ALIGNMENT_CENTER)
	for e in life.get("log", []):
		if e.kind == "end":
			_label(body, str(e.text), 40, P.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_gap(body, 40)
	_label(body, "共同回忆", 48)
	var memories: Array = life.get("memories", [])
	if memories.is_empty():
		_label(body, "（你们没有在同一件事上选到一起过）", 36, P.INK_SOFT)
	for m in memories:
		var vivid := int(m.vivid) > 0
		_label(body, "%d 岁 · %s%s" % [int(m.age), str(m.title), "" if vivid else "（已褪色）"], 38, P.OVERLAP if vivid else P.INK_SOFT)
	_gap(body, 40)
	_label(body, "人生长卷（M3）会在这里生成一张双色长图。", 30, P.INK_SOFT)
	_button(body, "回到标题", _show_title)
