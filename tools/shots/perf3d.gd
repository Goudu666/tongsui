extends SceneTree
## 实时 3D 的性能探针：同一条街、同几个钟点，3D 开着和关着（走 2D）各量 120 帧，比相对值。
##   xvfb-run -a godot --path client --rendering-driver opengl3 --resolution 1920x1080 -s ../tools/shots/perf3d.gd
## 云容器里是软件渲染（llvmpipe），绝对毫秒数没意义，只看 3D/2D 的倍数、draw call 和显存。
const Stage3D := preload("res://scripts/world3d/stage3d.gd")
var main: Node
const SHOTS := [
	["street_day", "street", 1600, 0, 700, "teen", "summer", 0],
	["street_night", "street", 2400, 0, 1290, "young", "winter", 0],
	["street_rain", "street", 2900, 0, 1240, "young", "summer", 2],
]

func _initialize() -> void:
	_run()

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(1.4)
	main = current_scene
	main._start_preview()
	await _wait(2.2)
	var w: Node = main.world
	for on in [false, true]:
		Stage3D.enabled = on
		w.scene = {}
		for s in SHOTS:
			var sc: Dictionary = w.scenes.get(str(s[1]), {})
			var y := float(sc.floors[int(s[3])])
			var me: Node2D = w.me()
			me.position = Vector2(float(s[2]), y)
			me.walk_target = me.position + Vector2(400, 0)
			w._enter_scene(sc)
			w.set_stage(str(s[5]))
			w.set_season(str(s[6]), int(s[7]))
			main._preview_minute = float(s[4])
			await _wait(1.0)
			var p_sum := 0.0
			var dc_sum := 0.0
			var n := 0
			var t0 := Time.get_ticks_usec()
			for i in 60:
				main._preview_minute = float(s[4])
				await process_frame
				p_sum += Performance.get_monitor(Performance.TIME_PROCESS)
				dc_sum += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
				n += 1
			var dt := (Time.get_ticks_usec() - t0) / 1000.0 / n
			print("PERF %s %s frame_ms=%.1f process_ms=%.2f draw_calls=%.0f vram_tex_MB=%.1f vram_total_MB=%.1f" % ["3D" if on else "2D", s[0], dt, p_sum / n * 1000.0, dc_sum / n, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	quit()
