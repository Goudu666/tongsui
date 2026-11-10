extends SceneTree
## 把游戏里实际混出来的声音录成 WAV（不需要声卡）。调音量、查平衡用：
##   godot --headless --path client -s res://tests/audio_capture.gd -- --out=/tmp/mix.wav [--stage=old] [--seconds=120]
## 流程：进「先逛逛」→ 从青家出门，经楼道、楼下、早点铺走到海河边，再走回梅身边，
## 途中依次触发醒木、青的半句、梅的半句、共鸣、同框车铃、一天结束。
## 不是自动化测试（文件名不以 unit_ 开头，CI 不跑它）。

const LifeTime := preload("res://scripts/ui/life_time.gd")

var _out := "user://mix.wav"
var _stage := "childhood"
var _seconds := 110.0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--stage="):
			_stage = arg.trim_prefix("--stage=")
		elif arg.begins_with("--seconds="):
			_seconds = float(arg.trim_prefix("--seconds="))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _go(world: Node, to: Vector2) -> void:
	var me: Node2D = world.me()
	if world.nav.ready():
		me.set_path(world.nav.path(me.position, world.nav.snap(to)))
	else:
		me.walk_target = to


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(0.2)
	var audio: Node = main.get_node("Audio")
	var rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	rec.set_recording_active(true)
	await _wait(4.0)  # 标题音乐
	main._start_preview()
	# 预览固定在 3 岁；想听别的阶段，就把回合拨到那个阶段的第一天
	var turn := 0
	while LifeTime.at(turn).stage != _stage and turn < 200:
		turn += 1
	main.life = {"turn": turn}
	main.world.set_stage(_stage)
	audio.music.rest_range = Vector2(6.0, 9.0)
	var world: Node = main.world
	var unit := _seconds / 110.0
	await _wait(8.0 * unit)
	_go(world, Vector2(740, 470))      # 楼道
	await _wait(8.0 * unit)
	_go(world, Vector2(1260, 880))     # 楼下
	await _wait(12.0 * unit)
	_go(world, Vector2(1630, 520))     # 早点铺
	await _wait(12.0 * unit)
	_go(world, Vector2(2140, 820))     # 海河边
	await _wait(16.0 * unit)
	audio.cue("xingmu")
	await _wait(2.0)
	audio.cue("stamp")
	audio.sting("call_qing")
	await _wait(4.0)
	audio.sting("call_mei", -7.0)
	await _wait(4.0)
	audio.sting("resonance")
	await _wait(9.0)
	_go(world, Vector2(1180, 620))     # 回到梅身边
	await _wait(18.0 * unit)
	audio.cue("bell_duet")
	await _wait(6.0 * unit)
	audio.sting("mismatch")
	await _wait(9.0)
	audio.hush(7.0)
	audio.cue("day_end")
	await _wait(6.0)
	var clip := rec.get_recording()
	rec.set_recording_active(false)
	var err := clip.save_to_wav(_out)
	print("[capture] %s（%.1f 秒，阶段 %s）→ %s" % ["已保存" if err == OK else "保存失败", clip.get_length(), _stage, _out])
	quit(0 if err == OK else 1)
