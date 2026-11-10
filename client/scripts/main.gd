extends Node
## 《同岁》入口：界面流程 + 联机消息分发。
##   标题 → 联机大厅（创建/输入配对码）→ 抽卡（家庭、天赋、属性）→ 河畔里（实时走动）→ 一生
## 另有「先逛逛」：不联网，只能走动，用来调地图和美术。
## 界面全部用代码搭（M0），层级：
##   背景纸张（CanvasLayer -10）→ 世界（Node2D + Camera2D）→ UI（CanvasLayer 1：screen / hud / modal / toast）

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Fx := preload("res://scripts/ui/fx.gd")
const TitleArt := preload("res://scripts/ui/title_art.gd")
const Resonance := preload("res://scripts/ui/resonance.gd")
const LifeTime := preload("res://scripts/ui/life_time.gd")
const NetClient := preload("res://scripts/net/lifeline_client.gd")
const WorldView := preload("res://scripts/world/world_view.gd")
const ServerConfig := preload("res://scripts/net/config.gd")
const ServerSettings := preload("res://scripts/ui/server_settings.gd")
const ContentStore := preload("res://scripts/net/content_store.gd")

var content: Dictionary = {}
var events_by_id: Dictionary = {}
var families: Dictionary = {}
var talents: Dictionary = {}

var ui: Control
var fx: Fx               ## 转场（网点"印出来"、长大的过场卡）
var screen: Control      ## 全屏菜单页
var body: VBoxContainer  ## screen 里的内容（标题页没有）
var hud: Hud
var action_btn: Button
var modal: ColorRect
var modal_card: PanelContainer
var modal_body: VBoxContainer
var toast: PanelContainer
var toast_label: Label
var _toast_tween: Tween
var _modal_tween: Tween
var _page_id := ""       ## 现在是哪一页；换页时才播转场
var _stage_shown := ""   ## 河畔里现在显示的人生阶段
var banner: Label        ## 顶部「连接断了，正在重连」
var lobby_list: VBoxContainer  ## 大厅里「继续」的人生线列表

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
	_apply_content(ContentStore.load_bundled())


## 换一份内容：开机时用安装包里带的；联机后服务器的内容不一样，就换成服务器下发的那一版
func _apply_content(c: Dictionary) -> void:
	if c.is_empty():
		return
	content = c
	events_by_id.clear()
	families.clear()
	talents.clear()
	for ev in content.events:
		events_by_id[ev.id] = ev
	for f in content.families:
		families[f.id] = f
	for t in content.talents:
		talents[t.id] = t
	if net != null:
		net.content_version = ContentStore.version_of(content)
	if world != null and not offline_preview:
		_leave_world()  # 地图和行动表可能也变了：下一个快照到了按新内容重建


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
	ui.theme = Kit.theme()
	layer.add_child(ui)
	fx = Fx.new()
	add_child(fx)

	# 全屏菜单（透明，透出底下带颗粒的纸）
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(screen)

	# 世界里的 HUD（不挡点击）
	hud = Hud.new()
	hud.visible = false
	ui.add_child(hud)
	action_btn = Button.new()
	action_btn.anchor_left = 0.5
	action_btn.anchor_right = 0.5
	action_btn.anchor_top = 1.0
	action_btn.anchor_bottom = 1.0
	action_btn.offset_left = -400
	action_btn.offset_right = 400
	action_btn.offset_top = -236
	action_btn.offset_bottom = -116
	action_btn.visible = false
	action_btn.pressed.connect(_on_action_pressed)
	Kit.make_primary(action_btn)
	hud.add_child(action_btn)

	# 弹窗（事件、结算、一天结束）：一张纸卡片，高度跟着内容走
	modal = ColorRect.new()
	modal.color = Color(P.INK, 0.5)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.visible = false
	ui.add_child(modal)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	modal_card = Kit.card(Kit.accent, 56.0)
	Kit._accent_boxes.append(modal_card.get_theme_stylebox("panel"))
	modal_card.custom_minimum_size = Vector2(960, 0)
	center.add_child(modal_card)
	modal_body = VBoxContainer.new()
	modal_body.add_theme_constant_override("separation", 26)
	modal_card.add_child(modal_body)

	# 提示条：一张贴歪的小纸条
	toast = Kit.card(Kit.accent, 26.0, false, 6.0)
	Kit._accent_boxes.append(toast.get_theme_stylebox("panel"))
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.anchor_top = 0.74
	toast.anchor_bottom = 0.74
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.grow_vertical = Control.GROW_DIRECTION_BOTH
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.modulate.a = 0.0
	toast.rotation = -0.012
	ui.add_child(toast)
	toast_label = Kit.label(toast, "", 34, P.INK, HORIZONTAL_ALIGNMENT_CENTER)

	banner = Label.new()
	banner.anchor_left = 0.0
	banner.anchor_right = 1.0
	banner.offset_top = 0
	banner.offset_bottom = 64
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 30)
	banner.add_theme_color_override("font_color", P.PAPER)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(P.MEI, 0.92)
	banner.add_theme_stylebox_override("normal", bsb)
	banner.text = "连接断了，正在重连……你的影子先替你过着"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.visible = false
	ui.add_child(banner)


func _scroll_column(parent: Control, side: int, top: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", side - 16)
	margin.add_theme_constant_override("margin_right", side - 24)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_bottom", 100)
	parent.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	# 里面再留一圈边，框的出头线和错位色块才不会被滚动区裁掉
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 30)
	pad.add_child(col)
	return col


func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)  # 立刻移除，避免与新节点重名
		c.queue_free()


func _label(parent: Container, text: String, font_size := 40, color := P.INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return Kit.label(parent, text, font_size, color, align)


func _button(parent: Container, text: String, on_press: Callable) -> Button:
	return Kit.button(parent, text, on_press)


func _primary(parent: Container, text: String, on_press: Callable) -> Button:
	var b := Kit.button(parent, text, on_press)
	Kit.make_primary(b)
	return b


func _quiet(parent: Container, text: String, on_press: Callable) -> Button:
	var b := Kit.button(parent, text, on_press)
	Kit.make_quiet(b)
	return b


func _gap(parent: Container, h := 40) -> void:
	Kit.gap(parent, h)


func _status(parent: Container) -> Label:
	var l := _label(parent, "", 32, P.INK_SOFT)
	l.name = "Status"
	return l


func _set_status(text: String) -> void:
	if body == null:
		return
	var s := body.get_node_or_null("Status") as Label
	if s == null:
		s = _status(body)
	s.text = text


func _toast(text: String) -> void:
	toast_label.text = text
	# 短的一行写完；长的折行，纸条的大小自己算（自动换行的 Label 报不准最小尺寸）
	var f := P.font()
	var text_size := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34)
	var wrap := text_size.x > 860.0
	if wrap:
		text_size = f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, 860.0, 34)
		text_size.x = 860.0
		text_size.y *= 1.28
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	var box := text_size + Vector2(64, 60)
	toast.offset_left = -box.x / 2.0
	toast.offset_right = box.x / 2.0
	toast.pivot_offset = box / 2.0
	if _toast_tween:
		_toast_tween.kill()
	toast.modulate.a = 0.0
	toast.offset_top = 40 - box.y / 2.0
	toast.offset_bottom = 40 + box.y / 2.0
	_toast_tween = create_tween()
	_toast_tween.set_parallel(true)
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_property(toast, "offset_top", -box.y / 2.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_property(toast, "offset_bottom", box.y / 2.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.set_parallel(false)
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.6)


func _role_text(role: String) -> String:
	return "「%s」" % str(names.get(role, P.ROLE_NAME[role]))


## 换页：页面种类变了才播"印出来"的转场（同一页刷新不播）
func _page(id: String) -> void:
	if id != _page_id:
		_page_id = id
		fx.print_in()


func _set_role(role: String) -> void:
	my_role = role
	Kit.set_accent(P.role_color(role))


func _show_screen(id: String, scroll := true) -> void:
	_page(id)
	screen.visible = true
	hud.visible = false
	modal.visible = false
	for c in screen.get_children():
		screen.remove_child(c)
		c.queue_free()
	body = _scroll_column(screen, 72, 150) if scroll else null


# ======================================================================
# 标题
# ======================================================================

func _show_title() -> void:
	_leave_world()
	if net != null:
		net.go_offline()
	banner.visible = false
	_show_screen("title", false)
	screen.add_child(TitleArt.new())
	var col := VBoxContainer.new()
	col.position = Vector2(88, 1440 + TitleArt.drop(screen.size.y))
	col.size = Vector2(900, 0)
	col.add_theme_constant_override("separation", 34)
	screen.add_child(col)
	if content.is_empty():
		_label(col, "没有找到 data/content.json，请先在仓库根目录运行 npm run content", 32, P.MEI)
		return
	_primary(col, "联机 · 和 TA 一起过一辈子", _show_online)
	_button(col, "先逛逛河畔里（不联网）", _start_preview)


# ======================================================================
# 离线逛逛：只能走动，用来看地图
# ======================================================================

func _start_preview() -> void:
	offline_preview = true
	_set_role("qing")
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
		hud.minute = _preview_minute
		world.set_minute(_preview_minute)
	world.controllable = not modal.visible and not screen.visible
	var spot := world.nearest_spot()
	if spot.is_empty() or modal.visible:
		action_btn.visible = false
		return
	var act := world.action_of(spot)
	var cost := ""
	if bool(act.get("sleep", false)):
		cost = " · 结束这一天"
	elif bool(act.get("school", false)):
		cost = " · 到 15:30"
	elif int(act.get("minutes", 0)) > 0:
		cost = " · %d 分钟" % int(act.minutes)
	if int(act.get("money", 0)) < 0:
		cost += " · %d 块" % -int(act.money)
	action_btn.text = str(act.get("label", "")) + cost
	action_btn.set_meta("spot", spot.id)
	action_btn.disabled = offline_preview
	action_btn.visible = true


func _ping_text() -> String:
	if net == null or offline_preview or net.rtt_ms < 0.0:
		return ""
	return "%d ms" % int(net.rtt_ms)


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
	_show_screen("online")
	_gap(body, 60)
	_label(body, "联机", 96)
	if not NetClient.addon_available():
		_label(body, "没有找到 nakama-godot 插件（client/addons/com.heroiclabs.nakama）。\n确认 project.godot 里注册了 autoload「Nakama」，然后用 Godot 重新打开项目。", 36, P.MEI)
		_quiet(body, "返回", _show_title)
		return
	if net == null:
		net = NetClient.new()
		add_child(net)
		net.status.connect(_set_status)
		net.failed.connect(_on_net_failed)
		net.created.connect(_on_net_created)
		net.opened.connect(_on_net_opened)
		net.lifelines.connect(_on_lifelines)
		net.partner_joined.connect(_on_partner_joined)
		net.connection_changed.connect(_on_connection_changed)
		net.recovered.connect(_on_recovered)
		net.content_updated.connect(_apply_content)
		net.content_version = ContentStore.version_of(content)
		net.snapshot.connect(_on_snapshot)
		net.roll_state.connect(_on_roll_state)
		net.world_state.connect(_on_world_state)
		net.event_started.connect(_on_event_started)
		net.log_entries.connect(_on_log_entries)
		net.presence.connect(_on_presence)
	_status(body)
	var ok: bool = await net.connect_server()
	if not ok:
		_server_row(body)
		_primary(body, "重试", _show_online)
		_quiet(body, "返回", _show_title)
		return
	_clear(body)
	_gap(body, 60)
	_label(body, "联机", 96)
	_label(body, "一个人开一条人生线，把配对码发给另一个人。", 32, P.INK_SOFT)

	# 继续之前的人生线
	lobby_list = VBoxContainer.new()
	lobby_list.add_theme_constant_override("separation", 20)
	body.add_child(lobby_list)
	net.list_lifelines()

	_gap(body, 20)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "你的名字（最多 12 个字）"
	name_edit.max_length = 12
	body.add_child(name_edit)
	Kit.tint(_primary(body, "开一条新的人生线（我是青）", func(): net.create_lifeline(name_edit.text)), P.QING)
	_gap(body, 10)
	Kit.rule(body, Color(P.INK, 0.25))
	var code_edit := LineEdit.new()
	code_edit.placeholder_text = "输入 TA 发给你的 6 位配对码"
	code_edit.max_length = 6
	body.add_child(code_edit)
	Kit.tint(_primary(body, "加入（我是梅）", func(): net.join_lifeline(code_edit.text.strip_edges(), name_edit.text)), P.MEI)
	_status(body)
	Kit.rule(body, Color(P.INK, 0.25))
	_button(body, "换手机找回", _show_recovery)
	_server_row(body)
	_quiet(body, "返回", _show_title)


func _show_server_settings() -> void:
	_show_screen("server")
	_gap(body, 60)
	var panel := ServerSettings.new()
	panel.done.connect(func(changed: bool):
		if changed:
			_drop_net()
		_show_online())
	body.add_child(panel)


func _drop_net() -> void:
	if net != null:
		net.go_offline()
		net.queue_free()
		net = null


## 服务器地址 + 设置入口（大厅和连不上时都显示）
func _server_row(parent: Container) -> void:
	_label(parent, "服务器：%s" % ServerConfig.url(), 28, P.INK_SOFT)
	_button(parent, "服务器设置", _show_server_settings)


## 换手机找回：显示这台手机的找回码；或者输入旧手机的找回码
func _show_recovery() -> void:
	_show_screen("recovery")
	_gap(body, 60)
	_label(body, "换手机找回", 72)
	_label(body, "把下面的找回码记下来。换手机、卸载重装之后，在新手机上输入它，就能回到你们的人生线。", 34, P.INK_SOFT)
	# 和配对码一样，印在一张票上
	var ticket := Kit.card(Kit.accent, 40.0)
	body.add_child(ticket)
	var code_label := _label(ticket, "生成中……", 84, P.INK, HORIZONTAL_ALIGNMENT_CENTER)
	var code: String = await net.recovery_code()
	if not is_instance_valid(code_label):
		return
	code_label.text = code if code != "" else "（生成失败）"
	if code != "":
		_button(body, "复制找回码", func():
			DisplayServer.clipboard_set(code)
			_set_status("已复制，存到备忘录里"))
	_gap(body, 40)
	_label(body, "我是从旧手机过来的", 36)
	var edit := LineEdit.new()
	edit.placeholder_text = "输入旧手机上的 10 位找回码"
	edit.max_length = 12
	body.add_child(edit)
	_primary(body, "找回", func(): net.recover(edit.text))
	_status(body)
	_quiet(body, "返回", _show_online)


func _on_recovered(ok: bool, text: String) -> void:
	_set_status(text)
	if ok:
		_show_online()


func _on_lifelines(items: Array) -> void:
	if lobby_list == null or not is_instance_valid(lobby_list):
		return
	_clear(lobby_list)
	if items.is_empty():
		return
	_label(lobby_list, "继续", 40, P.INK_SOFT)
	var last := net.last_lifeline()
	# 上次玩的放最上面
	items.sort_custom(func(a, b): return str(a.lifelineId) == last and str(b.lifelineId) != last)
	for it in items:
		var role := str(it.role)
		var nm: Dictionary = it.names if it.names is Dictionary else {}
		var me := str(nm.get(role, P.ROLE_NAME.get(role, role)))
		var other_role := "mei" if role == "qing" else "qing"
		var text := ""
		if not bool(it.paired):
			text = "%s · 等 TA 输入配对码 %s" % [me, str(it.code)]
		else:
			var where := "投胎中"
			if str(it.phase) == "life":
				where = str(it.label)
			elif str(it.phase) == "ended":
				where = "一生已经过完"
			text = "%s & %s · %s" % [me, str(nm.get(other_role, "")), where]
		var id := str(it.lifelineId)
		# 色块用这条人生线里自己的颜色：一眼看出当时是青还是梅
		Kit.tint(_button(lobby_list, text, func(): net.open_lifeline(id)), P.role_color(role))


func _on_net_opened(info: Dictionary) -> void:
	if info.get("matchId") == null and info.has("code"):
		_on_net_created(str(info.code), str(info.lifelineId))


func _on_partner_joined(_lifeline_id: String, partner_name: String) -> void:
	_set_status("%s 来了，正在进屋……" % (partner_name if partner_name != "" else "TA"))


func _on_connection_changed(is_online: bool) -> void:
	banner.visible = not is_online
	if is_online and world != null:
		_toast("连回来了")


func _on_net_failed(text: String) -> void:
	if screen.visible:
		_set_status(text)
	else:
		_toast(text)


func _on_net_created(code: String, lifeline_id: String) -> void:
	_show_screen("code")
	_gap(body, 160)
	_label(body, "把配对码发给 TA", 40, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	# 配对码印在一张票上
	var ticket := Kit.card(P.QING, 40.0)
	body.add_child(ticket)
	_label(ticket, " ".join(code.split("")), 130, P.QING, HORIZONTAL_ALIGNMENT_CENTER)
	_label(body, "TA 输入之后，这里会自己进屋", 34, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_gap(body, 40)
	_primary(body, "复制配对码", func():
		DisplayServer.clipboard_set(code)
		_set_status("已复制，去微信粘贴给 TA"))
	_button(body, "TA 已经输好了，进去", func(): net.open_lifeline(lifeline_id))
	_status(body)
	_quiet(body, "先回大厅", _show_online)


var _partner_online: Variant = null


func _on_presence(data: Dictionary) -> void:
	var now_online := bool(data.online[_other()])
	# PRESENCE 每次有人进出房间都会广播，只在 TA 的状态真的变了时提示
	if _partner_online != null and now_online == _partner_online:
		return
	var first := _partner_online == null
	_partner_online = now_online
	if world != null and not offline_preview and not (first and now_online):
		_toast("TA 上线了" if now_online else "TA 下线了，TA 的影子会替 TA 过日子")


# ======================================================================
# 快照：决定现在该显示哪一页
# ======================================================================

func _on_snapshot(data: Dictionary) -> void:
	names = data.names
	_set_role(str(data.you))
	life = data.life
	_partner_online = bool(data.online[_other()])
	match str(life.phase):
		"roll":
			_leave_world()
			_show_roll()
		"life":
			if world == null:
				_enter_world()
			else:
				_grow_up(LifeTime.at(int(life.get("turn", 0))))
			var w: Variant = life.get("world")
			if w is Dictionary:
				world.apply_snapshot_actors(w.get("actors"))
				last_world["minute"] = w.get("minute", 390)
				last_world["schoolDay"] = w.get("schoolDay", false)
				_resume_event(w.get("event"))
			_refresh_hud()
		"ended":
			_show_ending()


## 重连时如果正卡在一件事里：把选择框弹回来（选过了就显示「等 TA」）
func _resume_event(pe: Variant) -> void:
	if not pe is Dictionary or not pe.roles.has(my_role):
		if modal.has_meta("waiting_event"):
			_close_modal()
		return
	if modal.visible and str(modal.get_meta("waiting_event", "")) == str(pe.eventId):
		return
	var mine: Variant = pe.get("mine")
	if mine == null:
		_on_event_started({"event": pe})
	else:
		_open_modal()
		modal.set_meta("waiting_event", pe.eventId)
		_pick_shown(str(mine), _option_text(pe.eventId, mine), pe.kind == "mirror")


# ======================================================================
# 抽卡：家庭、天赋、属性
# ======================================================================

func _on_roll_state(data: Dictionary) -> void:
	life.rolls = data.rolls
	if str(life.get("phase", "")) == "roll":
		_show_roll()


func _show_roll() -> void:
	_show_screen("roll")
	var mine: Dictionary = life.rolls[my_role]
	var theirs: Dictionary = life.rolls[_other()]
	_label(body, "你出生在……", 40, P.INK_SOFT)
	var card := _roll_card(body, my_role, mine, true)
	# 每抽一次，新卡片"啪"地落下来
	card.modulate.a = 0.0
	var tw := card.create_tween().set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.2)
	tw.tween_method(func(v: float): card.position.y = v, -28.0, 0.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if bool(mine.confirmed):
		_label(body, "就这样了。等 TA 也定下来……", 36, P.INK_SOFT)
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 30)
		body.add_child(row)
		var b := _button(row, "重新投胎 · 剩 %d 次" % int(mine.rerollsLeft), func(): net.reroll())
		b.disabled = int(mine.rerollsLeft) <= 0
		_primary(row, "就这样，出生吧", func(): net.confirm_roll())
	_gap(body, 6)
	_label(body, "对门是", 32, P.INK_SOFT)
	_roll_card(body, _other(), theirs, false)
	_label(body, "TA 已经定下来了" if bool(theirs.confirmed) else "TA 还在犹豫", 30, P.INK_SOFT)
	_status(body)


## 一张"出生证"：色条上是名字和人家，下面是家境、天赋（盖的章）、四项属性
func _roll_card(parent: Container, role: String, r: Dictionary, full: bool) -> Control:
	var fam: Dictionary = families.get(r.familyId, {})
	var tal: Dictionary = talents.get(r.talentId, {})
	var color := P.role_color(role)
	var card := Kit.card(color, 44.0 if full else 34.0, true, 12.0 if full else 9.0)
	parent.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22 if full else 14)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	col.add_child(head)
	Kit.chip(head, str(names.get(role, P.ROLE_NAME[role])), color, 40 if full else 30)
	var fam_label := _label(head, str(fam.get("name", r.familyId)), 50 if full else 36)
	fam_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label(col, "%s · 零花钱 %d 块" % [P.WEALTH_NAME[int(fam.get("wealth", 1))], int(fam.get("money", 0))], 30, P.INK_SOFT)
	if full:
		_label(col, str(fam.get("desc", "")), 36)
		Kit.rule(col, Color(P.INK, 0.25))
	# 天赋：一枚梅红的章
	var stamp := HBoxContainer.new()
	stamp.add_theme_constant_override("separation", 20)
	col.add_child(stamp)
	var seal := Label.new()
	seal.text = str(tal.get("name", r.talentId))
	seal.add_theme_font_size_override("font_size", 34 if full else 28)
	seal.add_theme_color_override("font_color", P.MEI)
	var seal_box := StyleBoxFlat.new()
	seal_box.bg_color = Color(P.MEI, 0.08)
	seal_box.border_color = P.MEI
	seal_box.set_border_width_all(3)
	seal_box.set_corner_radius_all(4)
	seal_box.content_margin_left = 16
	seal_box.content_margin_right = 16
	seal_box.content_margin_top = 6
	seal_box.content_margin_bottom = 8
	seal.add_theme_stylebox_override("normal", seal_box)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seal.rotation = -0.035
	stamp.add_child(seal)
	if full:
		var tal_desc := _label(stamp, str(tal.get("desc", "")), 30, P.INK_SOFT)
		tal_desc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(Kit.StatDots.new(r.stats, color, not full))
	return card


# ======================================================================
# 河畔里
# ======================================================================

func _enter_world() -> void:
	_page("world")
	screen.visible = false
	modal.visible = false
	hud.visible = true
	world = WorldView.new()
	add_child(world)
	world.setup(content, my_role, names)
	var t := LifeTime.at(int(life.get("turn", 0)))
	_stage_shown = str(t.stage)
	world.set_stage(_stage_shown)
	world.net = null if offline_preview else net
	world.move_report.connect(_on_move_report)
	_refresh_hud()


func _leave_world() -> void:
	offline_preview = false
	if world != null:
		world.queue_free()
		world = null
	hud.visible = false


## 人生阶段变了：整版墨盖下来，写上年纪，盖住的时候换外观和纸色
func _grow_up(t: Dictionary) -> void:
	var stage := str(t.stage)
	if world == null or stage == _stage_shown:
		return
	_stage_shown = stage
	fx.stage_card("%d 岁" % int(t.age), _era_name(stage), P.INK, func():
		if world != null:
			world.set_stage(stage))


## 过场卡上的小字。地标线程的 data/street.json 里有五个年代的名字就用它，没有就写人生阶段
func _era_name(stage: String) -> String:
	var path := "res://data/street.json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.has("eras"):
			var eras: Variant = parsed.eras
			var era: Variant = null
			if eras is Dictionary:
				era = eras.get(stage)
			elif eras is Array:
				for e in eras:
					if e is Dictionary and (e.get("stage") == stage or e.get("id") == stage):
						era = e
			if era is Dictionary and era.has("name"):
				return str(era.name)
			if era is String:
				return era
	return str(Hud.STAGE_NAME.get(stage, ""))


func _refresh_hud() -> void:
	var t := LifeTime.at(int(life.get("turn", 0)))
	hud.time_label = str(t.label)
	hud.stage = str(t.stage)
	if offline_preview:
		hud.tag = "预览"
		hud.needs = {}
		hud.bond = {}
		hud.money = -1
		hud.note = ""
		return
	hud.minute = float(last_world.get("minute", 390))
	hud.tag = "上学日" if bool(last_world.get("schoolDay", false)) else ""
	hud.note = _ping_text()
	var needs: Dictionary = last_world.get("needs", {}).get(my_role, {})
	if needs.is_empty() and life.get("persons") != null:
		needs = life.persons[my_role].needs
	hud.needs = needs
	hud.money = int(last_world.get("money", {}).get(my_role, 0))
	hud.bond = last_world.get("bond", life.get("bond", {}))


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
		Kit.chip(modal_body, "默契时刻 · 不要商量", P.role_color(my_role))
	_label(modal_body, str(ev.get("title", "")), 68)
	Kit.rule(modal_body)
	_label(modal_body, str(ev.get("text", "")), 40)
	_gap(modal_body, 8)
	for o in ev.get("options", []):
		var oid: String = o.id
		var otext: String = o.text
		_button(modal_body, otext, _pick.bind(oid, otext, mirror))
	_gap(modal_body, 4)


func _pick(option_id: String, option_text: String, mirror: bool) -> void:
	net.choose(option_id)
	_pick_shown(option_id, option_text, mirror)


func _pick_shown(_option_id: String, option_text: String, mirror: bool) -> void:
	_clear(modal_body)
	_label(modal_body, "你选了", 32, P.INK_SOFT)
	_label(modal_body, option_text, 48, P.role_color(my_role))
	if mirror:
		Kit.rule(modal_body, Color(P.INK, 0.25))
		var s := _status(modal_body)
		s.text = "TA 还在想……"


func _open_modal() -> void:
	_clear(modal_body)
	if modal.has_meta("waiting_event"):
		modal.remove_meta("waiting_event")
	modal.visible = true
	action_btn.visible = false
	# 卡片像一张纸落在桌上：先歪一点、小一点，再放正
	if _modal_tween:
		_modal_tween.kill()
	modal.color.a = 0.0
	modal_card.modulate.a = 0.0
	modal_card.scale = Vector2.ONE * 0.94
	modal_card.rotation = -0.02
	await get_tree().process_frame
	modal_card.pivot_offset = modal_card.size / 2.0
	_modal_tween = create_tween().set_parallel(true)
	_modal_tween.tween_property(modal, "color:a", 0.5, 0.25)
	_modal_tween.tween_property(modal_card, "modulate:a", 1.0, 0.16)
	_modal_tween.tween_property(modal_card, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_modal_tween.tween_property(modal_card, "rotation", 0.0, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
			# 一天过完：撕下来的一页日历
			_open_modal()
			Kit.chip(modal_body, str(e.label), P.role_color(my_role))
			_label(modal_body, str(e.text), 44)
			Kit.rule(modal_body, Color(P.INK, 0.25))
			_label(modal_body, "日子一天天过去……", 32, P.INK_SOFT)
			_primary(modal_body, "下一个被记住的日子", _close_modal)
			_gap(modal_body, 4)
		elif kind == "death":
			_open_modal()
			_label(modal_body, str(e.text), 52, P.OVERLAP)
			_button(modal_body, "……", _close_modal)
			_gap(modal_body, 4)


func _show_mirror_result(e: Dictionary) -> void:
	_open_modal()
	var ev: Dictionary = events_by_id.get(e.events.qing, {})
	var hit := bool(e.resonance)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	modal_body.add_child(head)
	Kit.chip(head, "共鸣" if hit else "错位", P.OVERLAP if hit else P.INK_SOFT)
	var when := _label(head, "%s · %s" % [str(e.label), str(ev.get("title", ""))], 30, P.INK_SOFT)
	when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 两个圆靠拢：叠住 = 共鸣，错开 = 错位
	modal_body.add_child(Resonance.new(hit))
	for r in ["qing", "mei"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		modal_body.add_child(row)
		Kit.chip(row, str(names.get(r, P.ROLE_NAME[r])), P.role_color(r), 30)
		var mark := "（影子）" if e.shadow.has(r) else ""
		var pick := _label(row, _option_text(e.events[r], e.choices[r]) + mark, 38, P.INK)
		pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Kit.rule(modal_body, Color(P.INK, 0.25))
	_label(modal_body, str(e.text), 44, P.OVERLAP if hit else P.INK)
	_primary(modal_body, "嗯", _close_modal)
	_gap(modal_body, 4)


# ======================================================================
# 一生
# ======================================================================

func _show_ending() -> void:
	_leave_world()
	_show_screen("ending")
	_gap(body, 20)
	body.add_child(_EndMark.new())
	_label(body, "一生", 110, P.INK, HORIZONTAL_ALIGNMENT_CENTER)
	for e in life.get("log", []):
		if e.kind == "end":
			_label(body, str(e.text), 40, P.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_gap(body, 30)
	var memories: Array = life.get("memories", [])
	var card := Kit.card(P.OVERLAP, 44.0)
	body.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	card.add_child(col)
	Kit.chip(col, "共同回忆", P.OVERLAP, 32)
	if memories.is_empty():
		_label(col, "（你们没有在同一件事上选到一起过）", 36, P.INK_SOFT)
	else:
		col.add_child(_MemoryLine.new(memories))
	_gap(body, 20)
	_label(body, "人生长卷（M3）会在这里生成一张双色长图。", 30, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_primary(body, "回到标题", _show_title)


## 结局页顶上：两个圆完全叠在一起
class _EndMark extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(0, 190)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Kit.draw_pair(self, Vector2(size.x / 2.0, 100), 78.0, 26.0, 1.0, 3.0)


## 共同回忆：一条时间线。记得清的是实心叠印色，褪色的只剩一个空圈和灰字
class _MemoryLine extends Control:
	const ROW := 76.0
	var memories: Array = []

	func _init(p_memories: Array) -> void:
		memories = p_memories
		custom_minimum_size = Vector2(0, memories.size() * ROW + 8.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := P.font()
		var x := 22.0
		draw_line(Vector2(x, ROW * 0.5), Vector2(x, (memories.size() - 0.5) * ROW), Color(P.INK, 0.5), 2.0)
		for i in memories.size():
			var m: Dictionary = memories[i]
			var vivid := int(m.vivid) > 0
			var c := Vector2(x, (i + 0.5) * ROW)
			draw_circle(c, 14.0, P.PAPER, true, -1.0, true)
			if vivid:
				draw_circle(c + Vector2(2, 2), 11.0, P.MEI, true, -1.0, true)
				draw_circle(c, 11.0, P.OVERLAP, true, -1.0, true)
			else:
				draw_arc(c, 10.0, 0, TAU, 20, P.INK_SOFT, 2.0, true)
			var age := "%d 岁" % int(m.age)
			draw_string(f, c + Vector2(34, 13), age, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, P.INK_SOFT)
			var text := str(m.title) + ("" if vivid else "（已褪色）")
			draw_string(f, c + Vector2(150, 14), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, P.INK if vivid else P.INK_SOFT)
