extends SceneTree
## 录一段演示：标题 → 印出河畔里 → 天黑亮灯 → 默契时刻 → 共鸣 → 长大。
##   bash tools/shots/reel.sh <输出.mp4>
## 用 Godot 的 --write-movie 逐帧渲染，和机器快慢无关。

var main: Node
var _lapse := false
var _lapse_t := 0.0
var _lapse_len := 1.0
var _from := 0.0
var _to := 0.0


func _initialize() -> void:
	_run()


func _process(delta: float) -> bool:
	if _lapse and main != null:
		_lapse_t = minf(_lapse_t + delta, _lapse_len)
		main._preview_minute = lerpf(_from, _to, _lapse_t / _lapse_len)
	return false


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _time_lapse(from: float, to: float, sec: float) -> void:
	_from = from
	_to = to
	_lapse_t = 0.0
	_lapse_len = sec
	_lapse = true
	await _wait(sec)
	_lapse = false


func _walk(to: Vector2) -> void:
	var w: Node = main.world
	var a: Node2D = w.me()
	a.set_path(w.nav.path(a.position, w.nav.snap(to)))


func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.2)
	main = current_scene
	await _wait(4.0)

	main._start_preview()
	main.names = {"qing": "小满", "mei": "阿蘅"}
	for r in ["qing", "mei"]:
		main.world.actors[r].display_name = main.names[r]
	main._preview_minute = 930.0
	await _wait(1.6)
	_walk(Vector2(1160, 1010))
	await _wait(3.2)
	await _time_lapse(960.0, 1290.0, 6.0)
	_walk(Vector2(1300, 900))
	await _time_lapse(1290.0, 1296.0, 2.0)

	var ev: Dictionary = main.content.events[0]
	main.offline_preview = false
	main._on_event_started({"event": {"roles": ["qing", "mei"], "eventId": ev.id, "kind": "mirror"}})
	await _wait(2.6)
	main._show_mirror_result({"label": "7 岁 · 立夏", "events": {"qing": ev.id, "mei": ev.id},
		"choices": {"qing": ev.options[0].id, "mei": ev.options[0].id}, "shadow": [], "resonance": true,
		"text": str(ev.resonance[ev.options[0].id].text)})
	await _wait(3.8)
	main._close_modal()

	main.offline_preview = true
	main.life = {"turn": 50}
	main._preview_minute = 620.0
	main._refresh_hud()
	main._grow_up(main.LifeTime.at(50))
	await _wait(3.6)
	_walk(Vector2(1700, 900))
	await _wait(3.0)
	quit()
