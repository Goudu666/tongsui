extends SceneTree
## 天气的单测（不需要服务器）：godot --headless --path client -s res://tests/unit_weather.gd
## 联机时 WORLD 一秒五回，每回都会把季节和回合再设一遍：没变就不该重撒粒子，不然雪片一直在跳。

const Weather := preload("res://scripts/world/weather.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("✗ ", what)


## 找一个冬天下雪、一个夏天不下雨的回合（撒数是固定的，找到的总是同一个）
func _day(w: Node, s: String, want: String) -> int:
	for d in 200:
		w.season = s
		w.day = d
		if w._pick() == want:
			return d
	return -1


func _initialize() -> void:
	_run()


func _run() -> void:
	var w: Node = Weather.new()
	root.add_child(w)
	await process_frame
	check(w._p != null, "进树以后有粒子节点")
	if w._p == null:
		quit(1)
		return
	var snowy := _day(w, "winter", "snow")
	var dry := _day(w, "summer", "")
	var rainy := _day(w, "summer", "rain")
	check(snowy >= 0 and dry >= 0 and rainy >= 0, "冬天有下雪的日子、夏天有下雨和不下的日子")
	w.season = "spring"
	w.day = 0
	w.set_scene("street")
	var n0: int = w.restarts
	w.set_season("winter", snowy)
	check(w.kind == "snow" and w._p.emitting, "冬天下雪的日子在下雪")
	check(w.restarts == n0 + 1, "换到冬天撒一回")
	for i in 10:
		w.set_season("winter", snowy)
		w.set_scene("street")
	check(w.restarts == n0 + 1 and w._p.emitting, "同一天、同一张图反复设十回，不重撒")
	check(w._p.preprocess == w._p.lifetime, "先空跑一整轮再开始，进图就是满屏的")
	w.set_season("summer", dry)
	check(w.kind == "" and not w._p.emitting, "夏天不下雨的日子停了")
	w.set_season("summer", rainy)
	check(w.kind == "rain" and w._p.emitting, "夏天下雨的日子在下雨")
	var n1: int = w.restarts
	w.set_scene("building")
	check(w.kind == "" and not w._p.emitting, "进楼里不下")
	w.set_scene("street")
	check(w.kind == "rain" and w.restarts == n1 + 1, "出来接着下（重撒一回）")
	w.free()
	if fails == 0:
		print("✓ 天气：四季该下什么 / 同一天反复设不重撒 / 进屋停、出来接着下")
	quit(1 if fails > 0 else 0)
