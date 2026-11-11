extends SceneTree
## 成家和下一代的截图（docs/FAMILY.md）：有孩子的 HUD、带孩子的事飘「孩子 心智 +3」飞进孩子那张牌、孩子的关口揭晓。
##   xvfb-run -a godot --path client --rendering-driver opengl3 --resolution 1920x1080 --script res://../tools/shots/family.gd -- --out=<目录>
## 不联网：往 main.gd 里喂和服务器一样结构的 WORLD / LOG（actors[role].kid、did.k，见 docs/FAMILY.md 第五节）。
## 内容里的带孩子的事、孩子的关口在另一路写；这里先往 world.actions / events_by_id 里塞一份同样形状的。

var out_dir := "user://shots_family"
var main: Node

var _stats := {"qing": {"body": 5.6, "mind": 6.1, "charm": 5.2, "luck": 5.0}, "mei": {"body": 5.4, "mind": 5.8, "charm": 6.4, "luck": 4.0}}
var _kid := {"name": "石头", "age": 9, "stats": {"body": 3.6, "mind": 4.4, "charm": 3.9}, "shared": true}
var _money := {"qing": 46, "mei": 52}
var _bond := {"close": 72, "sync": 58}
var _tick := 0
var _turn := 0

## 带孩子的事：长的是孩子（行动的 kid 字段），自己照样累
const KID_ACT := {"id": "kid_homework", "label": "陪孩子写作业", "minutes": 90, "needs": {"energy": -8, "mood": -2},
	"kid": {"mind": 0.4}, "requires": {"kidAge": [6, 17]}}
## 孩子的关口：小升初（kid_gates.yaml 那边的形状：milestone 多一个 kidAge）
const KID_GATE := {"id": "k_mid", "title": "孩子小升初", "kidAge": 12, "options": [
	{"id": "key", "text": "托人进重点初中", "min": 6.2}, {"id": "near", "text": "就近上初中"}]}


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
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name)


func _turn_of(age: int) -> int:
	var LifeTime := load("res://scripts/ui/life_time.gd")
	for t in 400:
		if int(LifeTime.at(t).age) >= age:
			return t
	return 0


func _world(acts: Dictionary, tg := false, did: Dictionary = {}) -> void:
	_tick += 2
	var actors := {}
	for r in ["qing", "mei"]:
		var a: Node2D = main.world.actors[r]
		actors[r] = {"x": a.position.x, "y": a.position.y, "act": acts.get(r), "spot": null, "sleep": false, "seq": 0, "tg": tg and acts.get(r) != null, "fr": 1, "rd": 0, "sp": 0}
		actors[r]["kid"] = _kid.duplicate(true)  # 两口子共用一个孩子：两个人身上发的是同一个
	if not did.is_empty():
		actors["qing"]["did"] = did
	main._on_world_state({"tick": _tick, "minute": 600, "slot": 1, "ready": {}, "playing": false, "wait": 0, "rest": true,
		"actors": actors, "needs": {"qing": {"hunger": 72, "energy": 58, "mood": 76}, "mei": {"hunger": 66, "energy": 61, "mood": 80}},
		"money": _money.duplicate(), "event": null, "bond": _bond.duplicate(), "hints": [], "stats": _stats.duplicate(true), "eff": {"qing": 1.0, "mei": 1.0},
		"goals": {"qing": _goal(), "mei": _goal()}, "tracks": {}})


## 纸带上是孩子的下一道关（服务器 lifeGoal 一样的形状，分是孩子的心智）
func _goal() -> Dictionary:
	var have := int(floor(float(_kid.stats.mind) * 10.0 + 0.001))
	return {"id": "k_mid", "title": "孩子小升初", "age": 42, "turns": 1, "lines": [
		{"id": "key", "text": "托人进重点初中", "by": "孩子心智", "unit": "分", "have": have, "need": 62, "ok": have >= 62}]}


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
	main._preview_minute = 600.0
	main.world.set_minute(600.0)
	_turn = _turn_of(39)
	main.life = {"phase": "life", "turn": _turn}
	main.guide.process_mode = Node.PROCESS_MODE_DISABLED
	var me: Node2D = main.world.actors.qing
	var them: Node2D = main.world.actors.mei
	them.position = me.position + Vector2(120, 0)
	them.net_target = them.position
	# 跟前那个点位换成「陪孩子写作业」：看行动按钮上的字
	var spot: Dictionary = main.world.nearest_spot()
	if not spot.is_empty():
		var ids: Array = spot.get("actions", [])
		if ids.is_empty() and spot.has("action"):
			ids = [spot.action]
		for id in ids:
			var act: Dictionary = KID_ACT.duplicate(true)
			act["id"] = id
			main.world.actions[id] = act
	_world({})
	await _wait(0.3)
	while main.fx.is_busy():
		await _wait(0.2)
	await _wait(0.6)
	main.juice.on_snapshot({"lifelineId": "", "life": {"phase": "life", "turn": _turn, "persons": {
		"qing": {"alive": true, "stats": _stats.qing, "money": 46}, "mei": {"alive": true, "stats": _stats.mei, "money": 52}}, "bond": _bond}})
	_world({})
	await _wait(0.5)
	await _snap("f01_kid_hud")

	# 两口子一起陪孩子写作业：搭伴的印，「孩子 心智 +4」飞进孩子那张牌
	_world({"qing": "kid_homework", "mei": "kid_homework"}, true)
	await _wait(1.0)
	_kid.stats.mind += 0.4
	_world({}, false, {"n": 11, "a": "kid_homework", "l": "陪孩子写作业", "tg": true, "b": 1.5, "k": {"mind": 0.4}})
	await _wait(0.2 + main.juice.DID_LEAD + 0.62 + 0.5)
	await _snap("f02_kid_tag")
	await _wait(0.4)
	await _snap("f03_kid_fly")
	await _wait(1.2)
	await _snap("f04_kid_landed")
	await _wait(0.8)

	# 孩子的关口揭晓：孩子十二岁，小升初，分是孩子的心智；两口子选的一样
	_turn = _turn_of(42)
	main.life = {"phase": "life", "turn": _turn}
	_kid.age = 12
	_kid.stats.mind = 6.5
	_world({})
	main.events_by_id[KID_GATE.id] = KID_GATE
	main._on_log_entries({"entries": [{"kind": "milestone", "label": "42 岁那几年", "age": 42, "events": {"qing": "k_mid", "mei": "k_mid"},
		"choices": {"qing": "key", "mei": "key"}, "shadow": [], "resonance": true,
		"text": "开学那天两个人都请了假。校门口人多，石头头也没回就进去了。",
		"results": {
			"qing": {"score": 65, "scored": true, "unit": "分", "grade": null, "option": "key", "track": "", "line": 62, "luck": 1, "steady": 2},
			"mei": {"score": 65, "scored": true, "unit": "分", "grade": null, "option": "key", "track": "", "line": 62, "luck": 1}}}]})
	await _wait(3.4)
	await _snap("f05_kid_gate")
	await _wait(0.5)
	main._close_modal()
	await _wait(0.3)
	quit()
