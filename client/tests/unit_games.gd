extends SceneTree
## 搭伴小游戏的单测（不需要服务器）：godot --headless --path client -s res://tests/unit_games.gd
## 试玩用的本地物理、界面层的「问 → 玩 → 完」流程。

const KiteSim := preload("res://scripts/games/kite_sim.gd")
const GameLayer := preload("res://scripts/games/game_layer.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("✗ ", what)


func _init() -> void:
	# 试玩：不动手，线放不出去多少；跟着风口走，放得出去
	var idle := _run(false)
	var tracking := _run(true)
	check(idle < 40.0, "不动手得分应该低，实际 %.0f" % idle)
	check(tracking > 60.0, "跟着风口走得分应该高，实际 %.0f" % tracking)
	# 只认自己管的那一头
	var sim := KiteSim.new()
	sim.start("qing", true, 5)
	sim.tick(3.1)
	sim.input({"k": "run", "v": 0.9})
	check(is_equal_approx(float(sim.d.tx), 0.5) or float(sim.d.tx) != 0.9, "攥线的人改不了站位")
	sim.input({"k": "line", "v": 7})
	check(is_equal_approx(float(sim.d.tl), 1.0), "乱报的数会被夹住")
	check(sim.view().d.has("holder") and sim.view().phase == "play", "试玩的帧和服务器的同形")

	# 界面层：问 → 两边都点了 → 玩 → 结果
	var layer := GameLayer.new()
	root.add_child(layer)
	layer.my_role = "mei"
	var sent: Array = []
	layer.send.connect(func(body: Dictionary): sent.append(body))
	check(not layer.busy(), "一开始什么都不挡")
	layer.on_state({"game": {"gameId": "kite", "phase": "offer", "left": 8, "ready": {}, "t": -3.0, "d": null}})
	check(layer.busy(), "问的时候挡住地图")
	layer.on_state({"game": {"gameId": "kite", "phase": "offer", "left": 7, "ready": {"qing": true}, "t": -3.0, "d": null}})
	var frame := sim.view()
	layer.on_state({"game": frame})
	check(layer._game != null, "两边都点了就进小游戏")
	layer.on_state({"game": frame})
	layer.on_state({"game": null, "result": {"gameId": "kite", "score": 84, "boost": 1.72}})
	check(layer._game == null and layer._card.visible, "打完收起小游戏，说一句结果")
	# 没玩成（不了 / 超时 / 掉线）：安安静静收掉
	layer._card.visible = false
	layer.on_state({"game": {"gameId": "kite", "phase": "offer", "left": 8, "ready": {}, "t": -3.0, "d": null}})
	layer.on_state({"game": null, "result": null})
	check(not layer.busy(), "没玩成就当没问过")
	# 服务器没声了（比如刚好换了天）：自己收掉
	layer.on_state({"game": {"gameId": "kite", "phase": "offer", "left": 8, "ready": {}, "t": -3.0, "d": null}})
	layer._process(3.5)
	check(not layer.busy(), "三秒没消息就收掉")
	# 试玩
	layer.start_practice(true)
	check(layer.practicing() and layer.busy(), "试玩开得起来")
	layer.close()
	check(not layer.busy(), "离开河畔里时收干净")
	layer.free()

	if fails == 0:
		print("✓ 搭伴小游戏：试玩物理 / 各管一头 / 问→玩→完 / 没玩成不留痕 / 断了自己收")
	quit(1 if fails > 0 else 0)


## 跑一局试玩。tracking：我这一头盯着风口走
func _run(tracking: bool) -> float:
	var sim := KiteSim.new()
	sim.start("qing", true, 42)
	var score := -1.0
	var n := 0
	while score < 0.0 and n < 2000:
		if tracking:
			sim.input({"k": "line", "v": (float(sim.d.wh) - 0.06) / 0.9})
		score = sim.tick(0.1)
		n += 1
	return score
