extends SceneTree
## 人际圈子的飘字：做完一回攒门路的事，人头上冒「帮老师 3/6」；攒够了认下门路，盖一张墨色的「门路 · 老师记住你了」。
##   godot --path client --rendering-driver opengl3 --resolution 1920x1080 --script res://../tools/shots/circle.gd -- --out=<目录>
## 不联网：往 main.gd 里喂和服务器一样结构的 WORLD（actors[role].did 上带 tie / tp，见 server/src/circle.ts）。

var out_dir := "user://shots_circle"
var main: Node
var _stats := {"qing": {"body": 4.6, "mind": 5.2, "charm": 4.1, "luck": 5.0}, "mei": {"body": 5.0, "mind": 4.8, "charm": 5.6, "luck": 4.0}}
var _money := {"qing": 12, "mei": 9}
var _bond := {"close": 46, "sync": 31}
var _tick := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name)


func _world(acts: Dictionary, did: Dictionary = {}) -> void:
	_tick += 2
	var actors := {}
	for r in ["qing", "mei"]:
		var a: Node2D = main.world.actors[r]
		actors[r] = {"x": a.position.x, "y": a.position.y, "act": acts.get(r), "spot": null, "sleep": false, "seq": 0, "tg": false, "fr": 1, "rd": 0}
	if not did.is_empty():
		actors["qing"]["did"] = did
	main._on_world_state({"tick": _tick, "minute": 960, "slot": 2, "ready": {}, "playing": false, "wait": 0, "rest": true,
		"actors": actors, "needs": {"qing": {"hunger": 70, "energy": 64, "mood": 80, "clean": 70}, "mei": {"hunger": 60, "energy": 70, "mood": 75, "clean": 66}},
		"money": _money.duplicate(), "event": null, "bond": _bond.duplicate(), "hints": [], "stats": _stats.duplicate(true), "eff": {"qing": 1.0, "mei": 1.0},
		"goals": {}, "tracks": {}})


func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.6)
	main = current_scene
	await _wait(0.8)
	main._start_preview()
	main.names = {"qing": "小满", "mei": "阿蘅"}
	for r in ["qing", "mei"]:
		main.world.actors[r].display_name = main.names[r]
	await _wait(1.6)
	main.offline_preview = false
	main._preview_minute = 960.0
	main.world.set_minute(960.0)
	main.life = {"phase": "life", "turn": 20}
	var me: Node2D = main.world.actors.qing
	var them: Node2D = main.world.actors.mei
	them.position = me.position + Vector2(220, 0)
	them.net_target = them.position
	main.guide.process_mode = Node.PROCESS_MODE_DISABLED
	_world({})
	await _wait(0.3)
	while main.fx.is_busy():
		await _wait(0.2)
	await _wait(0.6)

	# 1. 留下来帮老师收拾教室，第三回：还在攒
	_world({"qing": "class_help"})
	await _wait(1.0)
	_stats.qing.charm += 0.12
	_world({}, {"n": 11, "a": "class_help", "l": "帮老师收拾教室", "tg": false, "tp": [3, 6, "帮老师"]})
	await _wait(main.juice.DID_LEAD + 1.25)
	await _snap("c01_tp")
	await _wait(1.6)

	# 2. 第六回：老师记住你了
	_world({"qing": "class_help"})
	await _wait(1.0)
	_stats.qing.charm += 0.14
	_stats.qing.mind += 0.1
	_world({}, {"n": 12, "a": "class_help", "l": "帮老师收拾教室", "tg": false, "tie": {"f": "tie_teacher", "l": "老师记住你了"}})
	main._preview_minute = 960.0  # 离线预览自己会拨钟，拨回下午
	main.world.set_minute(960.0)
	await _wait(main.juice.DID_LEAD + 0.5)
	await _snap("c02_tags")
	await _wait(1.15)
	await _snap("c03_tie")
	await _wait(0.6)
	await _snap("c04_tie_hold")
	await _wait(2.0)
	quit()
