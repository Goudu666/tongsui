extends SceneTree
## 街坊会不会被人挤走：主角在楼下从小卖部走过剃头的、磨剪子的，再回小卖部柜台帮忙，做完走开。
##   godot --path client --rendering-driver opengl3 --resolution 1280x720 --write-movie x.avi --fixed-fps 30 \
##     --script res://../tools/shots/folk_bump.gd -- [--zoom=2]
## 看两件事：走过去时街坊站着不动（前后错身过去）；在柜台停下来做事，阿姨等一下再往旁边让一步，人走了再回去。

var main: Node
var zoom := 2.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	_run()


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
	if main.get("guide") is Node:
		main.guide.process_mode = Node.PROCESS_MODE_DISABLED
		if main.guide is CanvasItem:
			main.guide.visible = false
	var sc: Dictionary = w.scenes.street
	var y := float(sc.floors[-1])
	w.set_stage("childhood")
	w.set_season("autumn")
	main._preview_minute = 560.0
	var me: Node2D = w.me()
	var other: Node2D = w.actors.mei
	other.visible = false
	other.position = Vector2(3600, y)
	other.net_target = other.position
	other.snap_remote = true
	me.visible = true
	me.doing = ""
	me.action_label = ""
	me.position = Vector2(760, y)
	me.walk_target = me.position
	w._enter_scene(w.scene_at(y))
	await _wait(0.6)
	# 一、从小卖部门口一路走过剃头的、磨剪子的
	await _go(w, me, Vector2(2000, y), 5.0)
	await _hold(w, me, 0.8)
	# 二、回到小卖部柜台，停下来帮忙
	await _go(w, me, Vector2(1080, y), 4.0)
	me.doing = "help_out"
	me.at_spot = "shop_counter"
	me.action_label = w._doing_label("qing", "help_out")
	await _hold(w, me, 4.0)
	# 三、做完走开
	me.doing = ""
	me.action_label = ""
	me.at_spot = ""
	await _hold(w, me, 0.4)
	await _go(w, me, Vector2(1500, y), 2.5)
	await _hold(w, me, 2.0)
	quit()


func _go(w: Node, me: Node2D, to: Vector2, limit: float) -> void:
	me.walk_target = to
	var t := 0.0
	while t < limit and me.position.distance_to(to) > 2.0:
		await process_frame
		t += 1.0 / 30.0
		_cam(w, me)


func _hold(w: Node, me: Node2D, sec: float) -> void:
	var t := 0.0
	while t < sec:
		await process_frame
		t += 1.0 / 30.0
		_cam(w, me)


func _cam(w: Node, me: Node2D) -> void:
	w.set_process(false)
	w.camera.position = Vector2(me.position.x, me.position.y - 120.0)
	w.camera.zoom = Vector2.ONE * get_root().get_visible_rect().size.y / float(w.camera.limit_bottom - w.camera.limit_top) * zoom
