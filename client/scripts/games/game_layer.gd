extends CanvasLayer
## 搭伴小游戏的界面层：问一句「一起放？」→ 两人都点了就开小游戏 → 打完说一句结果。
## 状态全听服务器的（OP.GAME，见 server/src/games.ts）；这里不存规则。
## 不联网时可以 start_practice() 自己试玩一局，不算数。

signal send(body: Dictionary)   ## 要发给服务器的 OP.GAME_INPUT
signal closed                   ## 小游戏画面收起来了

const P := preload("res://scripts/ui/palette.gd")
const Kite := preload("res://scripts/games/kite.gd")
const KiteSim := preload("res://scripts/games/kite_sim.gd")
## 小游戏 id → 问的时候怎么说（系统字用普通话）
const OFFER := {
	"kite": {"title": "一起放风筝？", "text": "两个人各管一头。放得好，这回一起玩长得更多；不玩也照常。", "yes": "放", "no": "不了"},
}
const STALE_SECONDS := 3.0  ## 这么久没收到服务器的状态，就当这一局已经没了（比如刚好换了天）

var my_role := "qing"
var names := {"qing": "青", "mei": "梅"}

var _root: Control
var _game: Control            ## 正在玩的小游戏画面
var _card: PanelContainer     ## 底部的卡片（问 / 结果）
var _card_body: VBoxContainer
var _phase := ""              ## "" | offer | play
var _quiet := 0.0
var _sim: KiteSim             ## 试玩
var _result_timer := 0.0


func _init() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# 卡片贴着屏幕底边，内容多高它就多高
	var dock := MarginContainer.new()
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_theme_constant_override("margin_left", 48)
	dock.add_theme_constant_override("margin_right", 48)
	dock.add_theme_constant_override("margin_bottom", 96)
	_root.add_child(dock)
	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = P.PAPER
	sb.border_color = P.INK
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(44)
	_card.add_theme_stylebox_override("panel", sb)
	_card.size_flags_vertical = Control.SIZE_SHRINK_END
	_card.visible = false
	dock.add_child(_card)
	_card_body = VBoxContainer.new()
	_card_body.add_theme_constant_override("separation", 22)
	_card.add_child(_card_body)


func set_theme(theme: Theme) -> void:
	_root.theme = theme


## 有卡片或小游戏挡着的时候，地图不该响应点击
func busy() -> bool:
	return _phase != "" or _card.visible


func practicing() -> bool:
	return _sim != null


# ======================================================================
# 服务器来的状态
# ======================================================================

func on_state(data: Dictionary) -> void:
	if _sim != null:
		return
	var g: Variant = data.get("game")
	if g == null:
		_end(data.get("result"))
		return
	_quiet = 0.0
	var phase := str(g.get("phase", ""))
	if phase == "offer":
		_show_offer(g)
	elif phase == "play":
		_show_game(g)


func _process(delta: float) -> void:
	if _sim != null:
		var score := _sim.tick(delta)
		if _game != null:
			_game.apply(_sim.view())
		if score >= 0.0:
			_sim = null
			_end({"gameId": "kite", "score": int(round(score)), "practice": true})
		return
	if _phase != "":
		_quiet += delta
		if _quiet > STALE_SECONDS:
			_end(null)
	elif _card.visible and _result_timer > 0.0:
		_result_timer -= delta
		if _result_timer <= 0.0:
			_card.visible = false


# ======================================================================
# 问
# ======================================================================

func _show_offer(g: Dictionary) -> void:
	var first := _phase != "offer"
	_phase = "offer"
	var ready: Dictionary = g.get("ready", {})
	var other := "mei" if my_role == "qing" else "qing"
	var copy: Dictionary = OFFER.get(str(g.get("gameId", "")), OFFER.kite)
	var mine := bool(ready.get(my_role, false))
	var theirs := bool(ready.get(other, false))
	var key := "%s|%s|%s" % [mine, theirs, int(g.get("left", 0))]
	if not first and _card.get_meta("key", "") == key:
		return
	_card.set_meta("key", key)
	_clear_card()
	_result_timer = 0.0
	_label(str(copy.title), 52, P.INK)
	_label(str(copy.text), 32, P.INK_SOFT)
	var their_name := str(names.get(other, "TA"))
	if mine:
		_label("等%s……（%d）" % [their_name, int(g.get("left", 0))], 36, P.role_color(my_role))
	else:
		if theirs:
			_label("%s想一起放。" % their_name, 34, P.role_color(other))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
		_card_body.add_child(row)
		_button(row, "%s（%d）" % [str(copy.yes), int(g.get("left", 0))], func(): send.emit({"k": "ready"}))
		_button(row, str(copy.no), func(): send.emit({"k": "pass"}))
	_card.visible = true


# ======================================================================
# 玩
# ======================================================================

func _show_game(g: Dictionary) -> void:
	if _phase != "play" or _game == null:
		_phase = "play"
		_card.visible = false
		_open_game()
		_game.input.connect(func(body: Dictionary): send.emit(body))
	_game.apply(g)


func _open_game() -> void:
	if _game != null:
		_game.queue_free()
	_game = Kite.new()
	_root.add_child(_game)
	_root.move_child(_game, 0)
	_game.setup(my_role, names)
	var quit := Button.new()
	quit.text = "不玩了"
	quit.add_theme_font_size_override("font_size", 28)
	quit.anchor_top = 1.0
	quit.anchor_bottom = 1.0
	quit.offset_left = 36
	quit.offset_right = 206
	quit.offset_top = -104
	quit.offset_bottom = -36
	quit.pressed.connect(_on_quit)
	_game.add_child(quit)


func _on_quit() -> void:
	if _sim != null:
		_sim = null
		_end(null)
	else:
		send.emit({"k": "quit"})


## 不联网时试玩一局。i_hold：我攥线（管高低）还是牵着线跑（管左右）
func start_practice(i_hold: bool) -> void:
	if _phase != "":
		return
	_sim = KiteSim.new()
	_sim.start(my_role, i_hold, int(Time.get_ticks_msec()) + 1)
	_phase = "play"
	_card.visible = false
	_open_game()
	_game.input.connect(_practice_input)
	_game.apply(_sim.view())


func _practice_input(body: Dictionary) -> void:
	if _sim != null:
		_sim.input(body)


# ======================================================================
# 完
# ======================================================================

func _end(result: Variant) -> void:
	var was := _phase
	_phase = ""
	_quiet = 0.0
	if _game != null:
		_game.queue_free()
		_game = null
	_card.visible = false
	if was != "":
		closed.emit()
	if not (result is Dictionary):
		return
	# 打完了说一句：线放出去多少，这回一起玩多长了多少
	var score := int(result.get("score", 0))
	_clear_card()
	_label("线放到头了" if score >= 100 else "线放出去 %d%%" % score, 52, P.OVERLAP)
	if bool(result.get("practice", false)):
		_label("试玩不算数。联网后两个人一起放，才算进这一天。", 32, P.INK_SOFT)
	else:
		_label("这回一起放风筝，长得比平时多：×%.2f" % float(result.get("boost", 1.0)), 34, P.INK)
	_button(_card_body, "好", func(): _card.visible = false)
	_card.visible = true
	_result_timer = 5.0


func close() -> void:
	_sim = null
	_end(null)


# ======================================================================
# 小部件
# ======================================================================

func _clear_card() -> void:
	for c in _card_body.get_children():
		_card_body.remove_child(c)
		c.queue_free()


func _label(text: String, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_body.add_child(l)


func _button(parent: Container, text: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_press)
	parent.add_child(b)
