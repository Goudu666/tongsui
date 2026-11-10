extends SceneTree
## 开局一小时的截图：章首卡、头几天的小纸条、主线路标、长大和进新一章并成的那张卡。
##   node tools/shots/opening_dump.mjs <json>   先从真服务器取几帧状态
##   godot --path client --rendering-driver opengl3 --resolution 1920x1080 --script ../tools/shots/opening.gd -- --out=<目录> --frames=<json>
## 不联网：把取来的 SNAPSHOT / WORLD 原样喂给 main.gd。

var out_dir := "user://shots"
var frames_path := ""
var main: Node
var frames: Dictionary = {}
var _feed: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		if a.begins_with("--frames="):
			frames_path = a.trim_prefix("--frames=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	DirAccess.remove_absolute("user://guide.cfg")  # 小纸条从头出
	frames = JSON.parse_string(FileAccess.get_file_as_string(frames_path))
	_run()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name, " ", img.get_size())


## 服务器一秒发五回 WORLD：这里也一直喂着，guide 和 HUD 才会动
func _pump() -> void:
	while true:
		await create_timer(0.2).timeout
		if not _feed.is_empty() and main.world != null:
			var w: Dictionary = _feed.duplicate(true)
			main._on_world_state(w)


func _frame(name: String) -> void:
	var f: Dictionary = frames[name]
	main._on_snapshot(f.snapshot)
	_feed = f.world


func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.6)
	main = current_scene
	await _wait(1.0)
	_pump()
	# 头一天：一进来是第一章的章首卡
	_frame("day0_morning")
	await _wait(1.3)
	await _snap("o01_chapter1")
	await _wait(3.6)
	print("tip ", main.guide._tip_id, " ", main.guide._tip.size, " ", main.guide._tip_label.size, " ", main.guide._tip_label.text.left(10), " vis=", main.guide._tip_label.visible, " mod=", main.guide._tip.modulate)
	await _snap("o02_tip_walk")
	main.guide._hide_tip()
	await _wait(2.8)
	await _snap("o03_tip_story")
	main.guide._hide_tip()
	await _wait(2.8)
	await _snap("o04_tip_slot")
	main.guide._hide_tip()
	# 下了楼：主线在楼道里，路标指着「上楼」
	_frame("day0_street")
	await _wait(1.6)
	await _snap("o05_route")
	# 6 岁：第二章（没赶上长大，单放一张章首卡）
	_frame("day12")
	await _wait(1.5)
	await _snap("o06_chapter2")
	await _wait(4.5)
	# 12 岁：长大成少年那张卡上也写着第三章
	_frame("day36")
	await _wait(1.6)
	await _snap("o07_stage_chapter3")
	await _wait(4.0)
	await _snap("o08_teen")
	quit()
