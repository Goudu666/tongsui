extends SceneTree
## 侧视横版的一段演示：同一个人走过几张图、几个年纪、四季和昼夜。
##   bash tools/shots/side_reel.sh <输出.mp4>
## --write-movie 逐帧渲染，和机器快慢无关。

var main: Node
var _lapse := false
var _lapse_t := 0.0
var _lapse_len := 1.0
var _from := 0.0
var _to := 0.0

## [图, 从哪儿走, 走到哪儿, 几点, 到几点, 阶段, 季节, 回合（定下不下雨雪）, 秒]
const CUTS := [
	["street", 260, 1560, 430, 520, "childhood", "spring", 0, 4.6],
	["street", 1560, 2900, 1040, 1150, "childhood", "summer", 1, 4.4],
	["street", 2900, 3300, 1180, 1300, "teen", "winter", 0, 3.6],
	["river", 500, 1700, 640, 700, "young", "summer", 0, 4.2],
	["river", 1700, 2700, 1060, 1130, "young", "autumn", 2, 3.8],
	["park", 700, 1600, 700, 760, "old", "winter", 0, 4.4],
	["across", 3200, 4100, 1200, 1280, "middle", "summer", 1, 3.6],
]


func _initialize() -> void:
	_run()


func _process(delta: float) -> bool:
	if _lapse and main != null:
		_lapse_t = minf(_lapse_t + delta, _lapse_len)
		main._preview_minute = lerpf(_from, _to, _lapse_t / _lapse_len)
	return false


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.3)
	main = current_scene
	await _wait(0.5)
	main._start_preview()
	main.names = {"qing": "小满", "mei": "阿蘅"}
	var w: Node = main.world
	for r in ["qing", "mei"]:
		w.actors[r].display_name = main.names[r]
	await _wait(0.2)
	main.hud.visible = false
	if main.toast is CanvasItem:
		main.toast.visible = false
	for c in CUTS:
		var sc: Dictionary = w.scenes.get(str(c[0]), {})
		var y := float(sc.floors[0])
		var me: Node2D = w.me()
		var other: Node2D = w.actors.mei
		me.position = Vector2(float(c[1]), y)
		me.walk_target = me.position
		other.visible = true
		other.position = Vector2(float(c[1]) - 110.0, y)
		other.net_target = other.position
		w.set_stage(str(c[5]))
		w.set_season(str(c[6]), int(c[7]))
		main._preview_minute = float(c[3])
		await _wait(0.05)
		me.walk_target = Vector2(float(c[2]), y)
		_from = float(c[3])
		_to = float(c[4])
		_lapse_t = 0.0
		_lapse_len = float(c[8])
		_lapse = true
		# 对门跟在后头走：只给 net_target，让她自己插值过去（直接改 position 不算走路，腿不动）
		var fx := other.position.x
		var t := 0.0
		while t < float(c[8]):
			await process_frame
			var d := 1.0 / 30.0  ## --fixed-fps 30
			t += d
			var target := me.position.x - 120.0
			if absf(fx - target) > 8.0:
				fx = move_toward(fx, target, 300.0 * d)
			other.net_target = Vector2(fx, y)
		_lapse = false
	quit()
