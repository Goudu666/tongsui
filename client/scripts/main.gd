extends Node
## 《同岁》入口：界面流程 + 联机消息分发。
##   标题 → 联机大厅（创建/输入配对码）→ 抽卡（家庭、天赋、属性）→ 河畔里（实时走动）→ 一生
## 另有「先逛逛」：不联网，只能走动，用来调地图和美术。
## 界面全部用代码搭（M0），层级：
##   背景纸张（CanvasLayer -10）→ 世界（Node2D + Camera2D）→ UI（CanvasLayer 1：screen / hud / modal / toast）
## 横屏：设计稿 1920×1080，高固定、宽随手机变长（见 Kit.BASE）。菜单页用 _columns() 分左右两栏；
## 河畔里的 HUD 是「对门」构图（ui/hud.gd）；弹窗用 _open_modal(宽度)，选项用 _options() 并排。

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Fx := preload("res://scripts/ui/fx.gd")
const TitleArt := preload("res://scripts/ui/title_art.gd")
const Resonance := preload("res://scripts/ui/resonance.gd")
const GoalPanel := preload("res://scripts/ui/goal_panel.gd")
const GoalRow := preload("res://scripts/ui/goal_row.gd")
const LifeTime := preload("res://scripts/ui/life_time.gd")
const LifeScroll := preload("res://scripts/ui/life_scroll.gd")
const NetClient := preload("res://scripts/net/lifeline_client.gd")
const WorldView := preload("res://scripts/world/world_view.gd")
const ServerConfig := preload("res://scripts/net/config.gd")
const ServerSettings := preload("res://scripts/ui/server_settings.gd")
const ContentStore := preload("res://scripts/net/content_store.gd")
const DuetUI := preload("res://scripts/duet/duet_ui.gd")
const LegacyUI := preload("res://scripts/ui/legacy_ui.gd")
const Guide := preload("res://scripts/ui/guide.gd")

var content: Dictionary = {}
var events_by_id: Dictionary = {}
var families: Dictionary = {}
var talents: Dictionary = {}

var ui: Control
var fx: Fx               ## 转场（网点"印出来"、长大的过场卡）
var screen: Control      ## 全屏菜单页
var body: VBoxContainer  ## screen 里的内容（标题页没有）
var hud: Hud
var goal_panel: GoalPanel  ## 下一个人生关口（HUD 里日历牌下面那条纸带，点开看全部的线）
var action_btn: Button
var action_title: Label    ## 行动按钮上的大字：做什么
var action_sub: Label      ## 下面一行小字：多久、多少钱、搭不搭伴
var slot_btn: Button       ## 行动按钮左边的「就这么过」：这一段不做正经事
var slot_title: Label
var slot_sub: Label
var _action_dim: Variant = null  ## 行动按钮上的字现在是不是灰的（null：还没设过）
var modal: ColorRect
var modal_card: PanelContainer
var modal_scroll: ScrollContainer  ## 弹窗比屏幕高时，卡片里面滚
var modal_body: VBoxContainer
var toast: PanelContainer
var toast_label: Label
var _toast_tween: Tween
var _toast_box := Vector2.ZERO  ## 提示条这一回的大小
var _toast_over := false        ## 提示条是不是贴在顶上（开着弹窗）
var _toast_drop := 0.0
var _modal_tween: Tween
var _page_id := ""       ## 现在是哪一页；换页时才播转场
var _scroll_saving := false  ## 长卷正在存图，再点不重来
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
var duet: DuetUI  ## 「接话」的界面：猜 TA / 搭上了 / 回话（见 docs/DUET.md）
var legacy: LegacyUI  ## 传承的界面：投胎页的老物件、结局页的再来一世（见 docs/LEGACY.md）
var guide: Guide  ## 开局引导：章首卡、主线路标、头几天的小纸条（ui/guide.gd）
var _preview_minute := 390.0
const PAGE_WIDTH := 1560.0    ## 菜单页内容最宽这么多，再宽就居中（两栏）
const COLUMN_WIDTH := 1040.0  ## 只有一栏的页面
const MODAL_WIDTH := 1040.0   ## 普通弹窗
const MODAL_WIDE := 1500.0    ## 选项并排、左右分栏的弹窗
const ACTION_SIZE := Vector2(640, 128)
const SLOT_SIZE := Vector2(300, 128)
const TOAST_ANCHOR := 0.72  ## 提示条平时在屏高这么多的地方；开着弹窗时贴到顶上


func _ready() -> void:
	duet = DuetUI.new(self)
	legacy = LegacyUI.new(self)
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
	# 主线（content/story.yaml）：七章，每章三件一定会发生的事。和随机的事走同一套弹窗
	for ev in _dict(content.get("story")).get("events", []):
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
	guide = Guide.new()
	guide.main = self
	add_child(guide)
	fx.card_hook = guide.card_lines

	# 全屏菜单（透明，透出底下带颗粒的纸）
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(screen)

	# 世界里的 HUD（不挡点击）
	hud = Hud.new()
	hud.visible = false
	ui.add_child(hud)
	goal_panel = GoalPanel.new()
	goal_panel.visible = false
	goal_panel.pressed.connect(_show_goal_detail)
	hud.add_child(goal_panel)
	# 行动按钮：右下角，右手拇指够得着。两行字自己摆（按钮本身不带字）
	action_btn = Button.new()
	action_btn.anchor_left = 1.0
	action_btn.anchor_right = 1.0
	action_btn.anchor_top = 1.0
	action_btn.anchor_bottom = 1.0
	action_btn.visible = false
	action_btn.pressed.connect(_on_action_pressed)
	Kit.make_primary(action_btn)
	hud.add_child(action_btn)
	var lines := VBoxContainer.new()
	lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lines.offset_left = 28
	lines.offset_right = -28
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", 0)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_btn.add_child(lines)
	action_title = Kit.label(lines, "", 40, P.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	action_sub = Kit.label(lines, "", 26, Color(P.PAPER, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	for l in [action_title, action_sub]:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.clip_text = true
	# 「就这么过」：纸色的次要按钮，贴在行动按钮左边
	slot_btn = Button.new()
	slot_btn.anchor_left = 1.0
	slot_btn.anchor_right = 1.0
	slot_btn.anchor_top = 1.0
	slot_btn.anchor_bottom = 1.0
	slot_btn.visible = false
	slot_btn.pressed.connect(_on_slot_pressed)
	hud.add_child(slot_btn)
	var slot_lines := VBoxContainer.new()
	slot_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot_lines.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_lines.add_theme_constant_override("separation", 0)
	slot_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_btn.add_child(slot_lines)
	slot_title = Kit.label(slot_lines, "", 36, P.INK, HORIZONTAL_ALIGNMENT_CENTER)
	slot_sub = Kit.label(slot_lines, "", 24, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	for l in [slot_title, slot_sub]:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.clip_text = true

	# 弹窗（事件、结算、一天结束）：一张纸卡片，高度跟着内容走
	modal = ColorRect.new()
	modal.color = Color(P.INK, 0.5)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.visible = false
	ui.add_child(modal)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	modal_card = Kit.card(Kit.accent, 52.0)
	Kit._accent_boxes.append(modal_card.get_theme_stylebox("panel"))
	modal_card.custom_minimum_size = Vector2(MODAL_WIDTH, 0)
	center.add_child(modal_card)
	# 横屏只有 1080 高：内容比屏幕高的时候，卡片不再长，里面滚
	modal_scroll = ScrollContainer.new()
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_card.add_child(modal_scroll)
	modal_body = VBoxContainer.new()
	modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_body.add_theme_constant_override("separation", 22)
	modal_scroll.add_child(modal_body)
	modal_body.minimum_size_changed.connect(_fit_modal)
	ui.resized.connect(_fit_modal)

	# 提示条：一张贴歪的小纸条
	toast = Kit.card(Kit.accent, 26.0, false, 6.0)
	Kit._accent_boxes.append(toast.get_theme_stylebox("panel"))
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.anchor_top = TOAST_ANCHOR
	toast.anchor_bottom = TOAST_ANCHOR
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.grow_vertical = Control.GROW_DIRECTION_BOTH
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.modulate.a = 0.0
	toast.rotation = -0.012
	ui.add_child(toast)
	toast_label = Kit.label(toast, "", 34, P.INK, HORIZONTAL_ALIGNMENT_CENTER)

	# 断线提示：左下角一条（顶上是 HUD，右下是行动按钮）
	banner = Label.new()
	banner.anchor_top = 1.0
	banner.anchor_bottom = 1.0
	banner.offset_left = 40
	banner.offset_right = 780
	banner.offset_top = -104
	banner.offset_bottom = -40
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
	ui.resized.connect(_layout_hud)
	_layout_hud()


## 菜单页的内容区：可以上下滚，内容最宽 width，宽屏上居中；比一屏矮的时候上下也居中
func _scroll_column(parent: Control, width: float) -> VBoxContainer:
	var inset := Kit.safe_sides(ui)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(56 + inset.x) - 16)
	margin.add_theme_constant_override("margin_right", int(56 + inset.y) - 24)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
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
	col.custom_minimum_size.x = minf(width, ui.size.x - 112.0 - inset.x - inset.y)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 26)
	pad.add_child(col)
	return col


## 左右两栏（横屏的菜单页大多是：左边是「这是什么」，右边是「要你做什么」）。
## 返回 [左栏, 右栏]；ratio 是两栏的宽度比
func _columns(parent: Container, left_ratio := 1.0, right_ratio := 1.0, gap := 80) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", gap)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var out: Array = []
	for ratio in [left_ratio, right_ratio]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_stretch_ratio = ratio
		col.add_theme_constant_override("separation", 26)
		row.add_child(col)
		out.append(col)
	return out


## 并排的选项（事件、关口、猜 TA）：三个以内排一行，四个 2×2，再多三列。往返回的格子里加按钮就行
func _options(parent: Container, count: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = count if count <= 3 else (2 if count == 4 else 3)
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 22)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)
	return grid


## 选项那张票：和普通按钮一个框，字居中，几张票一样高
func _option(grid: Container, text: String, on_press: Callable) -> Button:
	var b := Kit.button(grid, text, on_press)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 132
	b.add_theme_font_size_override("font_size", 36)
	return b


## 选项并排的弹窗该多宽：两个选项不用太宽，三个以上用宽卡
static func _options_width(count: int) -> float:
	return MODAL_WIDTH if count <= 1 else (1240.0 if count == 2 or count == 4 else MODAL_WIDE)


## HUD 上位置跟着屏幕宽度和刘海走的几样东西
func _layout_hud() -> void:
	if hud == null or goal_panel == null:
		return
	var inset := Kit.safe_sides(ui)
	hud.inset = inset
	var strip := hud.strip_rect()
	goal_panel.position = strip.position
	goal_panel.size = strip.size
	action_btn.offset_right = -40 - inset.y
	action_btn.offset_left = action_btn.offset_right - ACTION_SIZE.x
	action_btn.offset_bottom = -44
	action_btn.offset_top = action_btn.offset_bottom - ACTION_SIZE.y
	slot_btn.offset_right = action_btn.offset_left - 28
	slot_btn.offset_left = slot_btn.offset_right - SLOT_SIZE.x
	slot_btn.offset_bottom = action_btn.offset_bottom
	slot_btn.offset_top = action_btn.offset_top
	banner.offset_left = 40 + inset.x
	banner.offset_right = banner.offset_left + 740


## 弹窗卡片的高：跟着内容走，但不超过屏幕
func _fit_modal() -> void:
	if modal_scroll == null:
		return
	var room := ui.size.y - 64.0 - 104.0  # 上下各留 32，再去掉卡片自己的留白
	modal_scroll.custom_minimum_size.y = minf(modal_body.get_combined_minimum_size().y, room)


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
	# 分了栏以后「Status」不一定直接挂在 body 下面
	var s := body.find_child("Status", true, false) as Label
	if s == null:
		s = _status(body)
	s.text = text


## 提示条摆在哪：平时在屏幕下半截；开着弹窗时那里正是弹窗的按钮，纸条贴到屏幕顶上。drop 是落下来那一下还差多少
func _toast_place(drop: float) -> void:
	_toast_drop = drop
	toast.anchor_top = 0.0 if _toast_over else TOAST_ANCHOR
	toast.anchor_bottom = toast.anchor_top
	var mid := maxf(64.0, _toast_box.y / 2.0 + 8.0) if _toast_over else 0.0
	toast.offset_top = mid + drop - _toast_box.y / 2.0
	toast.offset_bottom = mid + drop + _toast_box.y / 2.0


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
	_toast_box = box
	_toast_over = modal.visible
	_toast_place(40.0)
	_toast_tween = create_tween()
	_toast_tween.set_parallel(true)
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_method(_toast_place, 40.0, 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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


func _show_screen(id: String, scroll := true, width := PAGE_WIDTH) -> void:
	_page(id)
	screen.visible = true
	hud.visible = false
	modal.visible = false
	for c in screen.get_children():
		screen.remove_child(c)
		c.queue_free()
	body = _scroll_column(screen, width) if scroll else null


# ======================================================================
# 标题
# ======================================================================

func _show_title() -> void:
	_leave_world()
	if net != null:
		net.go_offline()
	banner.visible = false
	_show_screen("title", false)
	var art := TitleArt.new()
	screen.add_child(art)
	# 左边是标志和按钮，右边是那扇窗（title_art.gd 定版面）
	var col := VBoxContainer.new()
	var slot := art.buttons_rect()
	col.position = slot.position
	col.size = Vector2(slot.size.x, 0)
	col.add_theme_constant_override("separation", 30)
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
	world.controllable = not modal.visible and not screen.visible and not world.playing
	_refresh_partner()
	if modal.visible:
		action_btn.visible = false
		slot_btn.visible = false
		return
	match _slot_state():
		"playing":
			# 这一段正在眼前过：什么都不用点
			action_btn.visible = false
			slot_btn.visible = false
		"decided":
			# 定下了还能改：按钮变成「改主意」，底下写定了什么、在等谁
			_set_action("cancel", "改主意", _decided_text(), false)
			slot_btn.visible = false
		"busy":
			# 前几段就开始的事（上学、上班）：撤不回，只等这一段过去
			_set_action("", _decided_text(), "等 TA 定这一段" if not _ready_of(_other()) else "", true)
			slot_btn.visible = false
		_:
			_show_spot_action()
			_set_slot_btn()


## 这一段我这边的状态："preview" 离线逛逛 / "playing" 正在过 / "decided" 定了还能改 / "busy" 定了撤不回 / "open" 还没定
func _slot_state() -> String:
	if offline_preview:
		return "preview"
	if bool(last_world.get("playing", false)):
		return "playing"
	if not _ready_of(my_role):
		return "open"
	var me: Dictionary = _dict(_dict(last_world.get("actors")).get(my_role))
	var fr: Variant = me.get("fr")
	if (me.get("act") != null or bool(me.get("sleep", false))) and fr != null and int(fr) < int(last_world.get("slot", 0)):
		return "busy"
	return "decided"


func _ready_of(role: String) -> bool:
	return bool(_dict(last_world.get("ready")).get(role, false))


## 我这一段定了什么：「这一段：念书」/「这一段歇着」/「睡下了」
func _decided_text() -> String:
	var a = world.me()
	if a == null:
		return ""
	if a.asleep:
		return "睡下了"
	if a.action_label != "":
		return a.action_label + ("，和 TA 一起" if a.together else "")
	return "这一段歇着"


## 行动按钮：mode 是按下去做什么（act / cancel / ""），sub 是底下那行小字
func _set_action(mode: String, title: String, sub: String, dim: bool) -> void:
	action_btn.set_meta("mode", mode)
	action_title.text = title
	action_sub.text = sub
	action_sub.visible = sub != ""
	action_btn.disabled = dim
	# 字的颜色跟着按钮灰不灰走。只在变的时候设：同一个颜色再设一遍也会触发主题变更和重排，这里每帧都跑
	if _action_dim != action_btn.disabled:
		_action_dim = action_btn.disabled
		action_title.add_theme_color_override("font_color", P.INK_SOFT if _action_dim else P.PAPER)
		action_sub.add_theme_color_override("font_color", P.INK_SOFT if _action_dim else Color(P.PAPER, 0.8))
	action_btn.visible = true


## 还没定的时候：走近一个点位，按钮上写在这儿能做什么、占多久；站在门口、楼梯口，按钮是「下楼」「去海河边」
func _show_spot_action() -> void:
	var spot := world.nearest_spot()
	var ex := world.nearest_exit()
	var me = world.me()
	if not ex.is_empty() and (spot.is_empty() or absf(float(ex.at[0]) - me.position.x) < absf(float(spot.at[0]) - me.position.x)):
		action_btn.set_meta("exit", str(ex.id))
		var to: Dictionary = world.scenes.get(str(ex.to), {})
		_set_action("exit", str(ex.label), "去" + str(to.get("name", "")) if str(ex.to) != str(world.scene.get("id", "")) else "", false)
		return
	if spot.is_empty():
		action_btn.visible = false
		return
	var act := world.action_of(spot)
	var cost: Array = []
	if bool(act.get("sleep", false)):
		# 一睁眼就站在床边：大按钮写着「睡觉」，头一回玩的人一按，这一天就没了。天还亮着就说清楚，按两下才睡
		cost.append("睡到明天" if world.slot >= SLEEP_EARLY_BEFORE else ("再按一下，今天就过完了" if _sleep_armed() else "天还亮着，今天就过完了"))
	elif bool(act.get("duty", false)):
		cost.append("到 %s" % P.clock(float(act.get("until", 930))))
	elif bool(act.get("quick", false)):
		cost.append("顺手的事")
	else:
		cost.append("做到 %s" % P.clock(float(WorldView.SLOTS[world.slot][1])))
	if int(act.get("money", 0)) < 0:
		cost.append("%d 块" % -int(act.money))
	# TA 这一段也定了在这儿做同一件事：现在定下就是搭伴，两个人都长得快
	if world.partner_doing(spot, act):
		cost.append("和 TA 搭伴")
	action_btn.set_meta("spot", spot.id)
	if offline_preview:
		cost = ["联网之后才能做"]
	_set_action("act", str(act.get("label", "")), " · ".join(cost), offline_preview)


## 「就这么过」：这一段不做正经事。TA 已经定了的话写一句，别让人干等
func _set_slot_btn() -> void:
	if offline_preview or world.me() == null or not world.me().visible:
		slot_btn.visible = false
		return
	slot_title.text = "就这么过"
	slot_sub.text = "TA 定了，在等你" if _ready_of(_other()) else "这一段歇着"
	slot_btn.visible = true


func _ping_text() -> String:
	if net == null or offline_preview or net.rtt_ms < 0.0:
		return ""
	return "%d ms" % int(net.rtt_ms)


func _on_action_pressed() -> void:
	if offline_preview and str(action_btn.get_meta("mode", "")) == "exit":
		world.walk_through(str(action_btn.get_meta("exit")))  # 不联网也能楼上楼下、街上河边逛
		return
	if net == null or offline_preview:
		return
	match str(action_btn.get_meta("mode", "")):
		"act":
			if action_btn.has_meta("spot"):
				var sp := str(action_btn.get_meta("spot"))
				if _sleep_early(sp) and not _sleep_armed():
					_sleep_armed_at = Time.get_ticks_msec()
					_toast("还早呢。真要睡，再按一下")
					return
				_sleep_armed_at = -1
				net.act(sp)
		"cancel":
			net.cancel_slot()
		"exit":
			if action_btn.has_meta("exit"):
				world.begin_exit()
				net.exit(str(action_btn.get_meta("exit")))


const SLEEP_EARLY_BEFORE := 3  ## 傍晚以前睡下算「早」：要按两下
var _sleep_armed_at := -1


## 这个点位现在是不是「天还亮着就去睡」
func _sleep_early(spot_id: String) -> bool:
	if world == null or world.slot >= SLEEP_EARLY_BEFORE:
		return false
	for sp in world.map.spots:
		if str(sp.id) == spot_id:
			return bool(world.action_of(sp).get("sleep", false))
	return false


## 按过一下「睡觉」，四秒内再按就真睡
func _sleep_armed() -> bool:
	return _sleep_armed_at >= 0 and Time.get_ticks_msec() - _sleep_armed_at < 4000


func _on_slot_pressed() -> void:
	if net != null and not offline_preview:
		net.pass_slot()


func _on_move_report(pos: Vector2) -> void:
	if net != null and not offline_preview:
		net.move(pos)


# ======================================================================
# 联机大厅
# ======================================================================

func _show_online() -> void:
	_show_screen("online", true, COLUMN_WIDTH)
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
		net.again_state.connect(legacy.on_again)
	_status(body)
	var ok: bool = await net.connect_server()
	if not ok:
		_server_row(body)
		_primary(body, "重试", _show_online)
		_quiet(body, "返回", _show_title)
		return
	# 连上了：左边是「接着过」，右边是「新开一条 / 加入 TA 的」
	_show_screen("online")
	var cols := _columns(body, 1.0, 1.0)
	var left: VBoxContainer = cols[0]
	var right: VBoxContainer = cols[1]
	_label(left, "联机", 96)
	_label(left, "一个人开一条人生线，把配对码发给另一个人。", 32, P.INK_SOFT)

	# 继续之前的人生线
	lobby_list = VBoxContainer.new()
	lobby_list.add_theme_constant_override("separation", 20)
	left.add_child(lobby_list)
	net.list_lifelines()
	Kit.rule(left, Color(P.INK, 0.25))
	_label(left, "服务器：%s" % ServerConfig.url(), 28, P.INK_SOFT)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 26)
	left.add_child(tools)
	_button(tools, "换手机找回", _show_recovery)
	_button(tools, "服务器设置", _show_server_settings)
	_quiet(left, "返回", _show_title)

	_gap(right, 24)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "你的名字（最多 12 个字）"
	name_edit.max_length = 12
	right.add_child(name_edit)
	Kit.tint(_primary(right, "开一条新的人生线（我是青）", func(): net.create_lifeline(name_edit.text)), P.QING)
	_gap(right, 10)
	Kit.rule(right, Color(P.INK, 0.25))
	var code_edit := LineEdit.new()
	code_edit.placeholder_text = "输入 TA 发给你的 6 位配对码"
	code_edit.max_length = 6
	right.add_child(code_edit)
	Kit.tint(_primary(right, "加入（我是梅）", func(): net.join_lifeline(code_edit.text.strip_edges(), name_edit.text)), P.MEI)
	_status(right)


func _show_server_settings() -> void:
	_show_screen("server", true, COLUMN_WIDTH)
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
	var cols := _columns(body, 1.0, 1.0)
	var left: VBoxContainer = cols[0]
	var right: VBoxContainer = cols[1]
	_label(left, "换手机找回", 72)
	_label(left, "把下面的找回码记下来。换手机、卸载重装之后，在新手机上输入它，就能回到你们的人生线。", 34, P.INK_SOFT)
	# 和配对码一样，印在一张票上
	var ticket := Kit.card(Kit.accent, 40.0)
	left.add_child(ticket)
	var code_label := _label(ticket, "生成中……", 84, P.INK, HORIZONTAL_ALIGNMENT_CENTER)
	var copy_slot := VBoxContainer.new()
	left.add_child(copy_slot)
	_gap(right, 30)
	_label(right, "我是从旧手机过来的", 44)
	var edit := LineEdit.new()
	edit.placeholder_text = "输入旧手机上的 10 位找回码"
	edit.max_length = 12
	right.add_child(edit)
	_primary(right, "找回", func(): net.recover(edit.text))
	_status(right)
	_quiet(right, "返回", _show_online)
	var code: String = await net.recovery_code()
	if not is_instance_valid(code_label):
		return
	code_label.text = code if code != "" else "（生成失败）"
	if code != "":
		_button(copy_slot, "复制找回码", func():
			DisplayServer.clipboard_set(code)
			_set_status("已复制，存到备忘录里"))


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
			text = "%s & %s · %s%s" % [me, str(nm.get(other_role, "")), legacy.life_text(it), where]
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
	var cols := _columns(body, 1.15, 1.0)
	var left: VBoxContainer = cols[0]
	var right: VBoxContainer = cols[1]
	_label(left, "把配对码发给 TA", 44, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	# 配对码印在一张票上
	var ticket := Kit.card(P.QING, 40.0)
	left.add_child(ticket)
	_label(ticket, " ".join(code.split("")), 130, P.QING, HORIZONTAL_ALIGNMENT_CENTER)
	_label(left, "TA 输入之后，这里会自己进屋", 34, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	_primary(right, "复制配对码", func():
		DisplayServer.clipboard_set(code)
		_set_status("已复制，去微信粘贴给 TA"))
	_button(right, "TA 已经输好了，进去", func(): net.open_lifeline(lifeline_id))
	_status(right)
	_quiet(right, "先回大厅", _show_online)


var _partner_online: Variant = null


func _on_presence(data: Dictionary) -> void:
	legacy.on_protocols(data.get("protocols"))
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
	legacy.on_protocols(data.get("protocols"))
	match str(life.phase):
		"roll":
			_leave_world()
			last_world = {}  # 再来一世：上一世的属性、关口都不作数了
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
				last_world["rest"] = w.get("rest", false)
				_resume_event(w.get("event"))
			_refresh_hud()
			duet.on_snapshot()  # 我不在的时候影子替我选过的，现在问我
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
		_pick_shown(str(mine), _option_text(pe.eventId, mine), pe.roles.has(_other()))


# ======================================================================
# 抽卡：家庭、天赋、属性
# ======================================================================

func _on_roll_state(data: Dictionary) -> void:
	# 只是谁换了手里的老物件：原地改那几行，不整页重画（不然页面会跳回顶上，出生证也会再落一回）
	var same: bool = _page_id == "roll" and legacy.same_cards(life.get("rolls"), data.rolls)
	life.rolls = data.rolls
	if str(life.get("phase", "")) != "roll":
		return
	if same:
		legacy.refresh_roll()
	else:
		_show_roll()


func _show_roll() -> void:
	_show_screen("roll")
	var mine: Dictionary = life.rolls[my_role]
	var theirs: Dictionary = life.rolls[_other()]
	# 对门：我的出生证在左，TA 的在右
	var cols := _columns(body, 1.25, 1.0)
	var left: VBoxContainer = cols[0]
	var right: VBoxContainer = cols[1]
	legacy.roll_head(left)
	var card := _roll_card(left, my_role, mine, true)
	_drop_in(card)  # 每抽一次，新卡片"啪"地落下来
	_label(right, "对门是", 40, P.INK_SOFT)
	_roll_card(right, _other(), theirs, false)
	legacy.their_offer(right)
	_label(right, "TA 已经定下来了" if bool(theirs.confirmed) else "TA 还在犹豫", 30, P.INK_SOFT)
	_status(right)
	# 第二世起，我面前摆着的老物件在两栏下面通栏排开，定下来的按钮跟到它下面；头一世按钮就在出生证下面
	legacy.my_offer(body)
	var foot: Container = left
	if legacy.has_offer():
		foot = _columns(body, 1.25, 1.0)[0]  # 和出生证一样宽，对齐在我这一边
	if bool(mine.confirmed):
		_label(foot, "就这样了。等 TA 也定下来……", 36, P.INK_SOFT)
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 30)
		foot.add_child(row)
		var b := _button(row, "重新投胎 · 剩 %d 次" % int(mine.rerollsLeft), func(): net.reroll())
		b.disabled = int(mine.rerollsLeft) <= 0
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		_primary(row, "就这样，出生吧", func(): net.confirm_roll())

## 卡片从上面一点落到它本来的位置。等容器排好版再动：位置是相对它自己该在的地方算的，
## 不然会把卡片挪到页面最顶上，盖住页头
func _drop_in(card: Control) -> void:
	card.modulate.a = 0.0
	await get_tree().process_frame
	if not is_instance_valid(card) or not card.is_inside_tree():
		return
	var y0 := card.position.y
	var box := card.get_parent() as Container
	var tw := card.create_tween().set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.2)
	tw.tween_method(func(v: float): card.position.y = y0 + v, -28.0, 0.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func(): box.queue_sort())  # 落的时候版面要是又变了，最后按容器的摆


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
	legacy.house_line(col, r)
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
	world.age = int(t.age)
	world.net = null if offline_preview else net
	world.move_report.connect(_on_move_report)
	_layout_hud()
	_refresh_hud()
	if not offline_preview:
		guide.enter()


func _leave_world() -> void:
	offline_preview = false
	if world != null:
		world.queue_free()
		world = null
	hud.visible = false
	hud.partner = {}
	hud.pointer = {}


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
	if world != null:
		world.age = int(t.age)
	if offline_preview:
		hud.tag = "预览"
		hud.needs = {}
		hud.bond = {}
		hud.money = -1
		hud.note = ""
		hud.story = {}
		goal_panel.visible = false
		return
	hud.minute = float(last_world.get("minute", 390))
	hud.slot_name = str(WorldView.SLOTS[world.slot][2]) if world != null else ""
	hud.playing = bool(last_world.get("playing", false))
	# 日历牌色条上的那个词：今天要去哪（上学 / 上班 / 出摊），不用去就是休息
	var my_track: Dictionary = _dict(_dict(last_world.get("tracks")).get(my_role))
	var duty: Dictionary = _dict(my_track.get("duty"))
	hud.tag = str(duty.get("label", "")) if not duty.is_empty() else ("休息" if bool(last_world.get("rest", false)) and int(t.age) >= 6 else "")
	_refresh_goal(my_track)
	hud.note = _ping_text()
	var needs: Dictionary = last_world.get("needs", {}).get(my_role, {})
	if needs.is_empty() and life.get("persons") != null:
		needs = life.persons[my_role].needs
	hud.needs = needs
	hud.money = int(last_world.get("money", {}).get(my_role, 0))
	hud.bond = last_world.get("bond", life.get("bond", {}))
	var st: Dictionary = _dict(last_world.get("story"))
	hud.story = {} if st.is_empty() else {"chapter": st.get("chapter", 0), "title": st.get("title", ""), "next": _dict(st.get("next")).get(my_role), "force": st.get("force", false)}


## 对门的牌（HUD 右上）和屏幕边上的箭头：TA 在哪、在做什么；走出画面了就指个方向。每帧算一次
func _refresh_partner() -> void:
	var other: Variant = world.actors.get(_other())
	if offline_preview or other == null or not other.visible:
		hud.partner = {}
		hud.pointer = {}
		return
	var online: bool = _partner_online == true
	var where := world.place_name(other.position, _other())
	var big := where
	var small := "闲着" if online else "影子替 TA 过着"
	var decided := _ready_of(_other()) and not world.playing
	if decided and other.action_label == "" and not other.asleep:
		big = "这一段歇着"
		small = where
	elif other.asleep:
		big = "睡着了"
		small = where
	elif other.action_label != "":
		big = other.action_label
		small = ("和你搭伴 · " if other.together else "") + where
	if decided:
		small = "定了 · " + small
	var color := P.role_color(_other())
	var their_name := str(names.get(_other(), "TA"))
	hud.partner = {"name": their_name, "color": color, "online": online, "big": big, "small": small}
	# 走出画面了：沿着「屏幕中心 → TA」这条线，贴到边上
	var at: Vector2 = world.get_canvas_transform() * other.global_position
	var view := Rect2(Vector2.ZERO, ui.size)
	if view.grow(-20.0).has_point(at) or modal.visible:
		hud.pointer = {}
		return
	var box := Rect2(70.0 + hud.inset.x, 300.0, ui.size.x - 140.0 - hud.inset.x - hud.inset.y, ui.size.y - 370.0)
	var c := view.get_center()
	var d := at - c
	var k := 1.0
	if absf(d.x) > 0.01:
		k = minf(k, ((box.end.x if d.x > 0.0 else box.position.x) - c.x) / d.x)
	if absf(d.y) > 0.01:
		k = minf(k, ((box.end.y if d.y > 0.0 else box.position.y) - c.y) / d.y)
	var edge := c + d * k
	# 别钻到行动按钮底下
	var corner_x := slot_btn.position.x if slot_btn.visible else action_btn.position.x
	if action_btn.visible and edge.x > corner_x - 70.0 and edge.y > action_btn.position.y - 70.0:
		edge.y = action_btn.position.y - 70.0
	hud.pointer = {"at": edge.round(), "dir": d.normalized().snappedf(0.02), "color": color, "name": their_name}


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


## 属性按百分制给人看（服务器里是 0~10，关口的线也是这么换的：sim.ts → lifePoints）
static func _points(v: Variant) -> int:
	return int(floor(float(v) * 10.0 + 0.001))


func _refresh_goal(my_track: Dictionary) -> void:
	var goals: Dictionary = _dict(last_world.get("goals"))
	goal_panel.visible = last_world.has("goals") and hud.visible
	goal_panel.goal = goals.get(my_role)
	goal_panel.their_goal = goals.get(_other())
	goal_panel.my_color = P.role_color(my_role)
	goal_panel.their_color = P.role_color(_other())
	goal_panel.their_name = str(names.get(_other(), "TA"))
	goal_panel.eff = float(_dict(last_world.get("eff")).get(my_role, 1.0))
	goal_panel.track = str(my_track.get("label", ""))
	goal_panel.stats = _dict(_dict(last_world.get("stats")).get(my_role))


## 点开目标纸带：这一关所有的线，两个人各在哪；下面是三项属性和「怎么长得快」
func _show_goal_detail() -> void:
	if modal.visible or world == null:
		return
	var goals: Dictionary = _dict(last_world.get("goals"))
	var mine: Variant = goals.get(my_role)
	var theirs: Variant = goals.get(_other())
	var stats: Dictionary = _dict(last_world.get("stats"))
	var my_c := P.role_color(my_role)
	var their_c := P.role_color(_other())
	# 左边是这一关所有的线，右边是三项属性和「怎么长得快」
	_open_modal(MODAL_WIDE)
	var cols := _columns(modal_body, 1.2, 1.0, 64)
	var left: VBoxContainer = cols[0]
	var right: VBoxContainer = cols[1]
	left.add_theme_constant_override("separation", 14)
	right.add_theme_constant_override("separation", 14)
	if mine is Dictionary:
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 16)
		left.add_child(head)
		Kit.chip(head, "下一个关口", my_c)
		var when := _label(head, "%d 岁 · %s" % [int(mine.age), GoalPanel.turns_text(int(mine.turns))], 30, P.INK_SOFT)
		when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_label(left, str(mine.title), 64)
		Kit.rule(left)
		for l in mine.lines:
			left.add_child(GoalRow.new(l, GoalPanel.their_have(theirs if theirs is Dictionary and theirs.id == mine.id else null, str(l.id)), my_c, their_c))
		if theirs is Dictionary and theirs.id != mine.id:
			_label(left, "%s 要过的是另一关：%s。" % [_role_text(_other()), str(theirs.title)], 30, P.INK_SOFT)
	else:
		Kit.chip(left, "往后的日子", my_c)
		_label(left, "没有非过不可的关了", 56)
	var mine_stats: Dictionary = _dict(stats.get(my_role))
	var their_stats: Dictionary = _dict(stats.get(_other()))
	Kit.chip(right, "现在的本事", P.INK)
	for k in ["body", "mind", "charm"]:
		if not mine_stats.has(k):
			continue
		var row := {"id": k, "text": P.STAT_NAME[k], "by": "", "unit": "分", "have": _points(mine_stats[k]), "need": 0, "ok": true}
		right.add_child(GoalRow.new(row, float(_points(their_stats[k])) if their_stats.has(k) else -1.0, my_c, their_c))
	_label(right, "实心的点是你，空心的是 %s。两个人在同一个地方做同一件事，都长得快一半；心情好的时候学得快，饿着困着学不进去。" % str(names.get(_other(), "TA")), 28, P.INK_SOFT)
	_gap(right, 6)
	_primary(right, "知道了", _close_modal)
	_gap(modal_body, 4)


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
	if pe.kind == "milestone":
		_show_milestone(pe, ev, _dict(data.get("locks", pe.get("locks"))))
		return
	# 主线的选项有门槛：家里给不了的那条不摆出来，积蓄不够的灰着写差多少（服务器在 locks 里说）
	var my_locks: Dictionary = _dict(_dict(data.get("locks", pe.get("locks"))).get(my_role))
	var opts: Array = story_options(ev, my_locks)
	_open_modal(_options_width(opts.size()))
	modal.set_meta("waiting_event", pe.eventId)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	modal_body.add_child(head)
	if ev.has("chapter"):
		var ch: Dictionary = _list_at(_dict(content.get("story")).get("chapters", []), int(ev.chapter) - 1)
		Kit.chip(head, "%s · %s" % [Hud.story_text({"chapter": ev.chapter})[0], str(ch.get("title", ""))], P.INK)
	if mirror:
		Kit.chip(head, "默契时刻 · 不要商量", P.role_color(my_role))
	_label(modal_body, str(ev.get("title", "")), 68)
	Kit.rule(modal_body)
	_label(modal_body, str(ev.get("text", "")), 40)
	_gap(modal_body, 4)
	# 选项并排：一张张票摆在正文下面
	var grid := _options(modal_body, opts.size())
	for o in opts:
		var oid: String = o.id
		var otext: String = o.text
		if my_locks.has(oid):
			var b := _option(grid, "%s\n%s" % [otext, str(my_locks[oid])], func(): pass)
			b.disabled = true
		else:
			_option(grid, otext, _pick.bind(oid, otext, mirror))
	_gap(modal_body, 4)


## 摆出来的选项：带标记门槛、又走不了的（不是给这户人家留的）不摆；只是钱不够的摆着，灰的
static func story_options(ev: Dictionary, locks: Dictionary) -> Array:
	var out: Array = []
	for o in ev.get("options", []):
		var rq: Dictionary = o.get("requires", {}) if o.get("requires") is Dictionary else {}
		var by_flag: bool = not (rq.get("flags", []) as Array).is_empty() or not (rq.get("notFlags", []) as Array).is_empty()
		if locks.has(str(o.id)) and by_flag:
			continue
		out.append(o)
	return out


static func _list_at(list: Variant, i: int) -> Dictionary:
	if list is Array and i >= 0 and i < list.size() and list[i] is Dictionary:
		return list[i]
	return {}


## 人生关口：够不着的路是灰的，写着差多少；够得着的路上写着对门走不走得了。
## 这是整个游戏里最重的一次选择：分数是平时一天天攒的，路是自己挑的，可以为了对门走低的那条。
func _show_milestone(pe: Dictionary, ev: Dictionary, locks: Dictionary) -> void:
	var both: bool = pe.roles.has(_other())
	var opts: Array = ev.get("options", [])
	_open_modal(_options_width(opts.size()))
	modal.set_meta("waiting_event", pe.eventId)
	# 只有一条路可走的人，服务器已经替他定了：直接显示结果，等对门
	var fixed: Variant = _dict(pe.get("choices")).get(my_role, pe.get("mine"))
	if fixed != null:
		_pick_shown(str(fixed), _option_text(pe.eventId, fixed), both)
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	modal_body.add_child(head)
	Kit.chip(head, "人生关口", P.INK)
	var sub := _label(head, "各选各的，可以商量" if both else "这一关只有你过", 30, P.INK_SOFT)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label(modal_body, str(ev.get("title", "")), 68)
	Kit.rule(modal_body)
	_label(modal_body, str(ev.get("text", "")), 40)
	var luck := float(_dict(pe.get("swing")).get(my_role, 0.0))
	var swing := int(round(luck * 10.0))
	if swing != 0:
		_label(modal_body, "今天发挥得%s，%s %d 分。" % ["不错" if swing > 0 else "不大好", "多了" if swing > 0 else "少了", absi(swing)], 30, P.INK_SOFT)
	# 默契托住的分：已经算在上面的数里了，这里只是告诉他是谁托的
	var steady := int(round(float(_dict(pe.get("steady")).get(my_role, 0.0)) * 10.0))
	if steady > 0:
		_label(modal_body, "知道%s就在外头等着，心里踏实，少丢了 %d 分。" % [str(names.get(_other(), "TA")), steady], 30, P.INK_SOFT)
	_gap(modal_body, 4)
	var my_locks: Dictionary = _dict(locks.get(my_role))
	var their_locks: Dictionary = _dict(locks.get(_other()))
	var their_name := str(names.get(_other(), "TA"))
	# 几条路并排摆着：够不着的是灰的，写着差多少；够得着的下面写对门走不走得了
	var grid := _options(modal_body, opts.size())
	for o in opts:
		var oid: String = o.id
		var otext: String = o.text
		var gated: bool = o.has("min") or o.has("cost")
		if my_locks.has(oid):
			var b := _option(grid, "%s\n%s" % [otext, str(my_locks[oid])], func(): pass)
			b.disabled = true
		else:
			var note := ""
			if both and gated:
				note = ("\n%s 够不着这条" if their_locks.has(oid) else "\n%s 也走得了") % their_name
			_option(grid, otext + note, _pick_path.bind(oid, otext, both))
	_gap(modal_body, 4)


## 关口上选路：不走默契事件的「猜 TA」（可以商量，没什么可猜的）。waiting：对门也过这一关，选完要等 TA
func _pick_path(option_id: String, option_text: String, waiting: bool) -> void:
	net.choose(option_id)
	_pick_shown(option_id, option_text, waiting)


func _pick(option_id: String, option_text: String, mirror: bool) -> void:
	if mirror:
		# 默契事件：选完自己的，再猜 TA 选了哪个，两样一起发
		duet.ask_guess(str(modal.get_meta("waiting_event", "")), option_id, option_text)
		return
	net.choose(option_id)
	_pick_shown(option_id, option_text, mirror)


func _pick_send(option_id: String, option_text: String, guess: String) -> void:
	net.choose(option_id, guess)
	_pick_shown(option_id, option_text, true)


func _pick_shown(_option_id: String, option_text: String, mirror: bool) -> void:
	_clear(modal_body)
	modal_card.custom_minimum_size.x = MODAL_WIDTH
	_label(modal_body, "你选了", 32, P.INK_SOFT)
	_label(modal_body, option_text, 48, P.role_color(my_role))
	if mirror:
		Kit.rule(modal_body, Color(P.INK, 0.25))
		var s := _status(modal_body)
		s.text = "TA 还在想……"


## width：卡片多宽。普通的 MODAL_WIDTH；选项并排或左右分栏的用 MODAL_WIDE / _options_width()
func _open_modal(width := MODAL_WIDTH) -> void:
	_clear(modal_body)
	modal_card.custom_minimum_size.x = minf(width, ui.size.x - 96.0)
	modal_card.size = Vector2.ZERO  # 上一张卡要是更宽更高，别把这张撑着
	modal_scroll.scroll_vertical = 0
	if modal.has_meta("waiting_event"):
		modal.remove_meta("waiting_event")
	modal.visible = true
	action_btn.visible = false
	slot_btn.visible = false
	if not _toast_over:  # 还挂着的提示条让到顶上去，别压住这张卡的按钮
		_toast_over = true
		_toast_place(_toast_drop)
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
	duet.check_owed()  # 还有欠着的话就接着问


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
		elif kind == "milestone":
			_show_milestone_result(e)
		elif kind == "solo" and e.get("duet") is Dictionary and e.duet.get("echo") == true:
			duet.show_echo(e)
		elif kind == "solo":
			if e.events[my_role] != null:
				_close_modal()
				var mine: Variant = e.get("checks", {}).get(my_role)
				if mine != null:
					_show_check_result(e, mine)
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
			var grew := _gains_text(_dict(_dict(e.get("gains")).get(my_role)))
			_label(modal_body, ("这一天你长了：" + grew) if grew != "" else "日子一天天过去……", 32, P.INK_SOFT)
			_primary(modal_body, "下一个被记住的日子", _close_modal)
			_gap(modal_body, 4)
		elif kind == "death":
			_open_modal()
			_label(modal_body, str(e.text), 52, P.OVERLAP)
			_button(modal_body, "……", _close_modal)
			_gap(modal_body, 4)


## 一天下来长了多少（百分制，不到 1 分的写「一点」）
func _gains_text(gains: Dictionary) -> String:
	var parts: Array = []
	for k in ["body", "mind", "charm"]:
		var v := float(gains.get(k, 0.0)) * 10.0
		if v >= 0.95:
			parts.append("%s +%d" % [P.STAT_NAME[k], int(round(v))])
		elif v >= 0.15:
			parts.append("%s 一点" % P.STAT_NAME[k])
	return "　".join(parts)


## 关口揭晓：每个人考了多少、走上了哪条路；两个人都过这一关时，同路是两个圆叠住，分开走是各在一边
func _show_milestone_result(e: Dictionary) -> void:
	var results: Dictionary = _dict(e.get("results"))
	if not results.has(my_role):
		var theirs: Dictionary = _dict(results.get(_other()))
		if not theirs.is_empty():
			_toast("%s 过了一关：%s" % [_role_text(_other()), _option_text(e.events[_other()], theirs.get("option"))])
		return
	var ev: Dictionary = events_by_id.get(e.events[my_role], {})
	var both := results.size() == 2
	var same := bool(e.get("resonance", false))
	var has_line := false
	for o in ev.get("options", []):
		if o.has("min"):
			has_line = true
	# 只有一条路、也没有成绩可说的关（上小学、退休）：不弹卡，一行字带过
	if ev.get("options", []).size() <= 1:
		_close_modal()
		_toast("%s：%s" % [str(ev.get("title", "")), _option_text(e.events[my_role], results[my_role].get("option"))])
		return
	# 两个人都过这一关：两个圆在左，各自考了多少、走了哪条路在右
	var box := modal_body
	if both:
		_open_modal(MODAL_WIDE - 160.0)
		var cols := _columns(modal_body, 0.62, 1.0, 56)
		var emblem: VBoxContainer = cols[0]
		emblem.alignment = BoxContainer.ALIGNMENT_CENTER
		emblem.add_child(Resonance.new(same))
		box = cols[1]
		box.add_theme_constant_override("separation", 20)
	else:
		_open_modal()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	box.add_child(head)
	Kit.chip(head, ("同路" if same else "各走各的") if both else "人生关口", P.OVERLAP if same else P.INK)
	var when := _label(head, "%s · %s" % [str(e.label), str(ev.get("title", ""))], 30, P.INK_SOFT)
	when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for r in ["qing", "mei"]:
		if not results.has(r):
			continue
		var res: Dictionary = results[r]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		box.add_child(row)
		Kit.chip(row, str(names.get(r, P.ROLE_NAME[r])), P.role_color(r), 30)
		var mark := "（影子）" if e.get("shadow", []).has(r) else ""
		var pick := _label(row, _option_text(e.events[r], res.get("option")) + mark, 38, P.INK)
		pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if has_line and bool(res.get("scored", true)):
			var score := "%d %s" % [int(res.get("score", 0)), str(res.get("unit", "分"))]
			if res.get("grade") != null:
				score += " · " + str(res.grade)
			var sl := _label(row, score, 30, P.INK_SOFT, HORIZONTAL_ALIGNMENT_RIGHT)
			sl.autowrap_mode = TextServer.AUTOWRAP_OFF
			sl.size_flags_horizontal = Control.SIZE_SHRINK_END
			sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track_label := ""
	for tr in content.get("tracks", []):
		if tr.id == results[my_role].get("track"):
			track_label = str(tr.label)
	if str(e.get("text", "")) != "":
		Kit.rule(box, Color(P.INK, 0.25))
		_label(box, str(e.text), 44, P.OVERLAP if same else P.INK)
	if track_label != "":
		_label(box, "从今天起：%s。" % track_label, 30, P.INK_SOFT)
	_primary(box, "往下过", _close_modal)
	_gap(modal_body, 4)


## 默契事件的结算卡：共鸣 / 搭上了 / 错位（画在 duet_ui.gd 里）
func _show_mirror_result(e: Dictionary) -> void:
	duet.show_result(e)


## 检定：有些选项成不成要看本事和运气（服务端 growth.ts 掷的，结果跟着日志过来）。
## 两个人在默契事件里选了同一项，就是搭把手：按本事大的那个算。
const STAT_TEXT := {"body": "体魄", "mind": "心智", "charm": "魅力", "luck": "运气"}


func _check_verdict(c: Dictionary) -> String:
	var how := "没成"
	if bool(c.get("ok", false)):
		how = "搭把手，成了" if bool(c.get("help", false)) else "成了"
	return "%s · %s" % [str(STAT_TEXT.get(str(c.get("stat", "")), "")), how]


## 各自的事里挂着检定的选项：选完弹一张小卡，说成没成
func _show_check_result(e: Dictionary, c: Dictionary) -> void:
	_open_modal()
	var ev: Dictionary = events_by_id.get(e.events[my_role], {})
	var ok := bool(c.get("ok", false))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	modal_body.add_child(head)
	Kit.chip(head, _check_verdict(c), P.role_color(my_role) if ok else P.INK_SOFT)
	var when := _label(head, "%s · %s" % [str(e.label), str(ev.get("title", ""))], 30, P.INK_SOFT)
	when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Kit.rule(modal_body, Color(P.INK, 0.25))
	_label(modal_body, str(c.get("text", "")), 44, P.INK)
	_primary(modal_body, "嗯", _close_modal)
	_gap(modal_body, 4)


# ======================================================================
# 一生
# ======================================================================

## 一生走完：先看长卷，再翻到「一生」那一页。已经翻过去了就留在那页（再来一世的票变了会重画它）
func _show_ending() -> void:
	if _page_id == "scroll":
		return
	if _page_id == "ending" or not _has_scroll():
		_show_ending_page()
	else:
		_show_scroll()


## 长卷要有关口才画得出来（很旧的存档、只拿到半截日志的时候没有）
func _has_scroll() -> bool:
	for e in life.get("log", []):
		if e is Dictionary and str(e.get("kind", "")) == "milestone":
			return true
	return false


## 人生长卷：整屏只有这一张纸，手指拖着看（ui/life_scroll.gd）
func _show_scroll() -> void:
	_leave_world()
	_show_screen("scroll", false)
	_scroll_saving = false
	var sides := Kit.safe_sides(screen)
	var view := LifeScroll.view(life, content, names)
	# 纸和底栏当一组，对着屏幕的竖向正中摆：1080 高时和原来一样，更高的屏（平板）上下的白平分
	view.set_anchors_preset(Control.PRESET_HCENTER_WIDE)
	view.offset_left = sides.x
	view.offset_right = -sides.y
	view.offset_top = -500.0
	view.offset_bottom = -500.0 + LifeScroll.HEIGHT
	screen.add_child(view)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_HCENTER_WIDE)
	bar.offset_left = sides.x + 70.0
	bar.offset_right = -sides.y - 70.0
	bar.offset_top = 404.0
	bar.offset_bottom = 504.0
	bar.add_theme_constant_override("separation", 26)
	bar.alignment = BoxContainer.ALIGNMENT_END
	screen.add_child(bar)
	var hint := _label(bar, "拖着看。两条线并成一条的地方，是你们走了同一条路。", 30, P.INK_SOFT)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_quiet(bar, "存成一张图", func(): _save_scroll(view.get_meta("scroll")))
	_primary(bar, "往下看", _show_ending_page)


## 把整张长卷存进相册。桌面版相册写不进去就放游戏自己的目录；
## 手机上那是玩家翻不到的私有目录，不算存好，直说没存进去
func _save_scroll(scroll: Control) -> void:
	if _scroll_saving:
		return
	_scroll_saving = true
	_toast("正在存……")
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(scroll) or not scroll.is_inside_tree():
		_scroll_saving = false
		return
	var name := "同岁_长卷_%s.png" % Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var err := ERR_CANT_CREATE
	var path := ""
	var pictures := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pictures != "":
		var dir := pictures.path_join("同岁")
		if DirAccess.make_dir_recursive_absolute(dir) == OK:
			path = dir.path_join(name)
			err = await scroll.save_png(path)
	if err != OK and not OS.has_feature("mobile"):
		err = await scroll.save_png("user://" + name)
		path = ProjectSettings.globalize_path("user://" + name)
	_scroll_saving = false
	if _page_id == "scroll":
		_toast("长卷存好了：%s" % path if err == OK else "没能存进相册，截个屏吧。")


func _show_ending_page() -> void:
	_leave_world()
	_show_screen("ending")
	# 左边是这一生怎么收的尾，右边是两个人的共同回忆
	var cols := _columns(body, 1.0, 1.1)
	var left: VBoxContainer = cols[0]
	var right: VBoxContainer = cols[1]
	left.add_child(_EndMark.new())
	_label(left, "一生", 110, P.INK, HORIZONTAL_ALIGNMENT_CENTER)
	for e in life.get("log", []):
		if e.kind == "end":
			_label(left, str(e.text), 40, P.INK, HORIZONTAL_ALIGNMENT_CENTER)
	for line in duet.ending_lines():
		_label(left, str(line), 34, P.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_gap(left, 10)
	var memories: Array = life.get("memories", [])
	var card := Kit.card(P.OVERLAP, 44.0)
	right.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	card.add_child(col)
	Kit.chip(col, "共同回忆", P.OVERLAP, 32)
	if memories.is_empty():
		_label(col, "（你们没有在同一件事上选到一起过）", 36, P.INK_SOFT)
	else:
		col.add_child(_MemoryLine.new(memories))
	# 各自留给河畔里的老物件，跟共同回忆放一栏：都是这一世剩下的东西
	legacy.left_behind(right)
	if _has_scroll():
		_quiet(right, "再看一眼长卷", _show_scroll)
	# 服务器支持的话，再来一世；那样「回到标题」退成小字
	if legacy.again(left):
		_quiet(left, "回到标题", _show_title)
	else:
		_primary(left, "回到标题", _show_title)


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
