extends Node
## 观察者：看着主场景（scripts/main.gd）和联机信号，把「发生了什么」翻译成声音导演的接口。
##
## 所有对主场景内部结构的依赖都关在这一个文件里，而且全部是「看」，不改任何东西：
##   - 读 main 的 world / life / last_world / my_role / screen / modal / toast / net
##   - 监听 net 的 snapshot / world_state / event_started / log_entries / presence / failed
##   - 场景树里新出现的按钮和输入框，自动接上按键音
## 主场景以后要是拆了，这个文件跟着改（或者删掉，由新代码直接调导演的接口）。
## 读属性一律用 get() 加默认值：对不上就不出声，不报错。

const LifeTime := preload("res://scripts/ui/life_time.gd")

var main: Node
var audio: Node

var _net: Object = null
var _scene := ""
var _ending_id := 0   ## 结局页第一个节点的 id：它还在，就还在结局页
var _page_id := 0
var _toast_alpha := 0.0
var _acts := {}
var _money := -1
var _other_chosen := false
var _partner_live := true
var _last_pos := {}
var _page_cool := 0.0


func attach(p_main: Node, p_audio: Node) -> void:
	main = p_main
	audio = p_audio
	get_tree().node_added.connect(_on_node_added)


func _other(role: String) -> String:
	return "mei" if role == "qing" else "qing"


func _role() -> String:
	return str(main.get("my_role")) if main.get("my_role") != null else "qing"


func _dict(key: String) -> Dictionary:
	var v: Variant = main.get(key)
	return v if v is Dictionary else {}


func _ctl(key: String) -> Control:
	var v: Variant = main.get(key)
	return v if v is Control and is_instance_valid(v) else null


static func _alive(id: int) -> bool:
	if id == 0:
		return false
	var o := instance_from_id(id)
	return o is Node and is_instance_valid(o) and (o as Node).is_inside_tree()


# ---------------------------------------------------------------- 按钮 ----

func _on_node_added(n: Node) -> void:
	if n is LineEdit:
		n.text_changed.connect(func(_t): audio.cue("type", 0.0, randf_range(0.92, 1.08)))
		return
	if not n is BaseButton:
		return
	var kind := "tap"
	var text: String = n.text if n is Button else ""
	var modal_body := _ctl("modal_body")
	var modal := _ctl("modal")
	if modal_body != null and modal != null and modal_body.is_ancestor_of(n) and modal.has_meta("waiting_event"):
		var events: Variant = main.get("events_by_id")
		var ev: Dictionary = events.get(modal.get_meta("waiting_event"), {}) if events is Dictionary else {}
		kind = "option_mirror" if str(ev.get("kind", "")) == "mirror" else "option"
	elif text.contains("重新投胎"):
		kind = "shake"
	elif text.contains("出生吧"):
		kind = "birth"
	elif text.begins_with("返回") or text.contains("回大厅"):
		kind = "back"
	n.pressed.connect(_on_pressed.bind(kind))


func _on_pressed(kind: String) -> void:
	match kind:
		"option_mirror":  # 默契事件：我先把我这半句说出去
			audio.cue("stamp")
			audio.sting("call_" + _role())
		"option":
			audio.cue("stamp")
		"shake":
			audio.cue("shake")
		"birth":
			audio.cue("birth")
		"back":
			audio.cue("tap", -2.0, 0.84)
		_:
			audio.cue("tap", 0.0, randf_range(0.96, 1.04))


# ---------------------------------------------------------------- 联机信号 ----

func _watch_net() -> void:
	var net: Variant = main.get("net")
	if net == _net or (net != null and not is_instance_valid(net)):
		return
	_net = net
	if net == null:
		return
	for pair in [["snapshot", _on_snapshot], ["world_state", _on_world_state], ["event_started", _on_event_started],
			["log_entries", _on_log_entries], ["presence", _on_presence], ["failed", _on_failed]]:
		if net.has_signal(pair[0]) and not net.is_connected(pair[0], pair[1]):
			net.connect(pair[0], pair[1])


func _on_failed(_text: String) -> void:
	audio.cue("error")


func _on_snapshot(data: Dictionary) -> void:
	var online: Variant = data.get("online")
	if online is Dictionary:
		_partner_live = bool(online.get(_other(str(data.get("you", "qing"))), true))
	_acts.clear()
	_money = -1
	var life: Variant = data.get("life")
	if life is Dictionary and str(life.get("phase", "")) == "ended":
		_mark_ending.call_deferred()


func _mark_ending() -> void:
	var body := _ctl("body")
	_ending_id = body.get_child(0).get_instance_id() if body != null and body.get_child_count() > 0 else 0


func _on_presence(data: Dictionary) -> void:
	var online: Variant = data.get("online")
	if not online is Dictionary:
		return
	var live := bool(online.get(_other(_role()), true))
	if live != _partner_live and _scene == "life":
		audio.cue("door_open" if live else "door_close")
	_partner_live = live


func _on_event_started(data: Dictionary) -> void:
	var pe: Variant = data.get("event")
	if not pe is Dictionary:
		return
	_other_chosen = false
	if (pe.get("roles", []) as Array).has(_role()):
		audio.cue("xingmu")  # 醒木一拍，开说


func _on_world_state(data: Dictionary) -> void:
	var me := _role()
	var other := _other(me)
	var actors: Variant = data.get("actors")
	if actors is Dictionary:
		for r in [me, other]:
			var a: Variant = actors.get(r)
			var act: Variant = a.get("act") if a is Dictionary else null
			if act != null and _acts.get(r) != act and _acts.has(r):
				audio.act(str(act), r == me, _near())
			_acts[r] = act
	var money: Variant = data.get("money")
	if money is Dictionary:
		var m := int(money.get(me, 0))
		if _money >= 0 and m > _money:
			audio.cue("coin")
		_money = m
	# 默契事件里对方选好了：听得见 TA 开了口，听不出 TA 说的是什么
	var ev: Variant = data.get("event")
	if ev is Dictionary and str(ev.get("kind", "")) == "mirror" and ev.get("chosen") is Dictionary:
		var chosen := bool(ev.chosen.get(other, false))
		if chosen and not _other_chosen and (ev.get("roles", []) as Array).has(me):
			audio.sting("call_" + other, -7.0)
		_other_chosen = chosen
	elif ev == null:
		_other_chosen = false


func _on_log_entries(data: Dictionary) -> void:
	for e in data.get("entries", []):
		match str(e.get("kind", "")):
			"together":
				audio.cue("bell_duet")
			"mirror":
				audio.sting("resonance" if bool(e.get("resonance", false)) else "mismatch", 0.0)
			"day":
				audio.hush(7.0)
				audio.cue("day_end")
			"death":
				audio.hush(600.0)
				audio.cue("death")


# ---------------------------------------------------------------- 每帧 ----

func _near() -> float:
	var world: Variant = main.get("world")
	if world == null or not is_instance_valid(world):
		return 0.0
	var actors: Dictionary = world.get("actors") if world.get("actors") is Dictionary else {}
	var a: Variant = actors.get(_role())
	var b: Variant = actors.get(_other(_role()))
	if a == null or b == null or not b.visible:
		return 0.0
	return 1.0 - smoothstep(260.0, 1300.0, a.position.distance_to(b.position))


func _process(delta: float) -> void:
	if main == null or not is_instance_valid(main):
		return
	_watch_net()
	var world: Variant = main.get("world")
	var screen := _ctl("screen")
	var modal := _ctl("modal")
	var life := _dict("life")
	var in_world: bool = world != null and is_instance_valid(world) and (screen == null or not screen.visible)

	# 现在是哪一场
	var scene := "title"
	if in_world:
		scene = "life"
		_ending_id = 0
	elif _alive(_ending_id):
		scene = "ending"
	elif str(life.get("phase", "")) == "roll" and _net != null and is_instance_valid(_net) and str(_net.get("match_id")) != "":
		scene = "roll"
	if scene != _scene:
		_scene = scene
		audio.set_scene(scene)
		_last_pos.clear()

	_watch_pages(delta, screen)
	_watch_toast()

	if not in_world:
		audio.idle()
		return
	var me := _role()
	var actors: Dictionary = world.get("actors") if world.get("actors") is Dictionary else {}
	var a: Variant = actors.get(me)
	if a == null:
		return
	var b: Variant = actors.get(_other(me))
	var preview := bool(main.get("offline_preview"))
	var last := _dict("last_world")
	var turn := int(life.get("turn", 0))
	var minute := float(main.get("_preview_minute")) if preview else float(last.get("minute", 390.0))
	var bond: Variant = last.get("bond", life.get("bond", {}))
	var sync := float(bond.get("sync", 0.0)) if bond is Dictionary else 0.0
	var other_pos: Variant = b.position if b != null and b.visible else null
	audio.set_life(_dict("content").get("map", {}), me, a.position, other_pos, _partner_live or preview, turn,
		str(LifeTime.at(turn).stage), LifeTime.SEASONS[turn % 4], minute, bool(last.get("schoolDay", false)),
		sync if not preview else 30.0, modal != null and modal.visible)

	# 脚步
	for r in actors:
		var actor: Variant = actors[r]
		var pos: Vector2 = actor.position
		var moved: float = pos.distance_to(_last_pos.get(r, pos))
		_last_pos[r] = pos
		if moved > 0.0 and moved < 80.0 and bool(actor.get("walking")) and actor.visible:
			var gain := 1.0 if r == me else 1.0 - smoothstep(150.0, 900.0, pos.distance_to(a.position))
			audio.step(str(r), pos, moved, r == me, gain)


## 整页换了（标题 → 大厅 → 投胎……）：抽一张纸的声音
func _watch_pages(delta: float, screen: Control) -> void:
	_page_cool = maxf(0.0, _page_cool - delta)
	var body := _ctl("body")
	if body == null or screen == null or not screen.visible or body.get_child_count() == 0:
		return
	var first := body.get_child(0).get_instance_id()
	if first != _page_id:
		if _page_id != 0 and _page_cool <= 0.0:
			audio.cue("page")
			_page_cool = 0.35
		_page_id = first


func _watch_toast() -> void:
	var toast := _ctl("toast")
	if toast == null:
		return
	var a := toast.modulate.a
	if a > 0.99 and _toast_alpha < 0.99:
		audio.cue("toast")
	_toast_alpha = a
