extends SceneTree
## 实时 3D 的样片：从早到晚走过楼下这条街，几个年纪、季节各来一段。用 Godot 的 movie maker 按固定帧率出帧，软件渲染也不掉帧：
##   xvfb-run -a godot --path client --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 24 \
##     --write-movie /tmp/reel/f.png -s ../tools/shots/reel3d.gd
##   ffmpeg -framerate 24 -i /tmp/reel/f%08d.png -c:v libx264 -pix_fmt yuv420p -crf 20 reel.mp4
var main: Node
var w: Node

## [年纪, 季节, 回合（挑天气）, 从 x, 到 x（-1 原地）, 从几点, 到几点, 秒, 青做的事, 梅做的事]
const CUTS := [
	["childhood", "summer", 0, 420, 1700, 420, 560, 6.0, "", ""],
	["teen", "summer", 0, 1960, -1, 800, 820, 3.5, "chess", "chess"],
	["young", "autumn", 0, 2300, 3480, 1040, 1180, 6.0, "", ""],
	["middle", "winter", 0, 1500, 2100, 1230, 1300, 5.0, "", ""],
	["teen", "summer", 2, 2350, 2900, 1200, 1250, 4.0, "", ""],
	["old", "spring", 0, 1450, 1450, 450, 470, 3.5, "", "morning_walk"],
]

func _initialize() -> void:
	_run()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(3)
	main = current_scene
	main._start_preview()
	main.names = {"qing": "小满", "mei": "阿蘅"}
	w = main.world
	for r in ["qing", "mei"]:
		w.actors[r].display_name = main.names[r]
	main.hud.visible = false
	for c in CUTS:
		await _cut(c)
	quit()

func _cut(c: Array) -> void:
	var sc: Dictionary = w.scenes.street
	var y := float(sc.floors[0])
	var me: Node2D = w.me()
	var other: Node2D = w.actors.mei
	w.set_stage(str(c[0]))
	w.set_season(str(c[1]), int(c[2]))
	me.position = Vector2(float(c[3]), y)
	me.walk_target = me.position
	other.visible = true
	var gap := 120.0
	other.position = me.position + Vector2(-gap, 0)
	other.net_target = other.position
	other.walk_target = other.position
	for pair in [[me, str(c[8])], [other, str(c[9])]]:
		var a: Node2D = pair[0]
		var act: String = pair[1]
		a.doing = act
		a.action_label = ""
		a.together = act != "" and str(c[8]) == str(c[9])
	w._pair_faces(str(c[8]) != "" and c[8] == c[9])
	if str(c[8]) != "" and c[8] == c[9]:
		other.position = me.position + Vector2(110, 0)
		other.net_target = other.position
	for n in ["toast", "action_btn", "slot_btn", "goal_panel", "fill_btn", "menu_box"]:
		var cv = main.get(n)
		if cv is CanvasItem:
			cv.visible = false
	w.camera.reset_smoothing()
	var frames := int(float(c[7]) * 24.0)
	var to_x := float(c[4])
	var started := false
	for i in frames:
		var t := float(i) / float(frames)
		main._preview_minute = lerpf(float(c[5]), float(c[6]), t)
		# 走一小段：开头停半秒再起步
		if to_x >= 0.0 and to_x != float(c[3]) and t > 0.08 and not started:
			me.walk_target = Vector2(to_x, y)
			started = true
		if str(c[9]) == "" or c[8] != c[9]:
			var side := -1.0 if to_x >= float(c[3]) else 1.0
			if to_x < 0.0 or to_x == float(c[3]):
				side = 1.0
			other.net_target = Vector2(me.position.x + side * gap, y) if str(c[9]) == "" else other.position
			other.walk_target = other.net_target
		await process_frame
