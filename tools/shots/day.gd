extends SceneTree
## 一天的行动循环截图：按钮写着花多久累多少、TA 刚在这儿写过（搭伴）、做完一回钟拨过去、一天收工的小结卡。
##   node tools/shots/day_dump.mjs <json>   先从真服务器取几帧状态
##   xvfb-run -a godot --path client --rendering-driver opengl3 --resolution 1920x1080 --script res://../tools/shots/day.gd -- --out=<目录> --frames=<json>
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
	frames = JSON.parse_string(FileAccess.get_file_as_string(frames_path))
	_run()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name, " ", img.get_size())


func _pump() -> void:
	while true:
		await create_timer(0.2).timeout
		if not _feed.is_empty() and main.world != null:
			main._on_world_state(_feed.duplicate(true))


func _frame(name: String, snap := true) -> void:
	var f: Dictionary = frames[name]
	if snap:
		main._on_snapshot(f.snapshot)
	_feed = f.world
	main._on_world_state(_feed.duplicate(true))


func _run() -> void:
	# 小纸条都当看过了，别挡着按钮
	var cfg := ConfigFile.new()
	for k in ["walk", "story", "slot", "wait", "together", "gate", "need", "night", "day", "goal"]:
		cfg.set_value("tips", k, true)
	cfg.save("user://guide.cfg")
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.6)
	main = current_scene
	await _wait(1.0)
	_pump()
	_frame("am_open")
	await _wait(2.0)
	if main.guide != null and main.guide.has_method("_hide_tip"):
		main.guide._hide_tip()
	await _wait(1.0)
	await _snap("d01_button")
	_frame("am_partner", false)
	await _wait(1.2)
	await _snap("d02_partner_here")
	_frame("am_did", false)
	await _wait(0.45)
	await _snap("d03_clock_sweep")
	await _wait(1.2)
	await _snap("d04_did")
	_frame("am_did2", false)
	await _wait(1.6)
	await _snap("d05_second")
	main._on_log_entries({"entries": [frames.day_end.entry]})
	await _wait(1.2)
	await _snap("d06_day_card")
	quit()
