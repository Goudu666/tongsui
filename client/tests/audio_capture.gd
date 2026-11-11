extends SceneTree
## 把游戏里实际混出来的声音录成 WAV（不需要声卡）。调音量、查平衡用：
##   godot --headless --path client -s res://tests/audio_capture.gd -- --out=/tmp/mix.wav [--stage=old] [--seconds=120]
##     [--slot=早上|上午|下午|傍晚|晚上 或 --minute=1020]   钉在一天里的这个时候（不钉就照离线逛逛那样走钟）
##     [--weather=rain|snow|catkin|leaf]                     钉住天气（进了屋照样没有天气）
##     [--reveal=pass|top|miss]                              录一回关口揭晓：我那把尺子数分，起高光
##     [--grow]                                              录一回长大：从 --stage 长到下一个阶段
##     [--at=building|street|river]                         只录一件事时站在哪张图上（给了 --weather 默认 street，否则 building）
##     [--hushed]                                            揭晓前照真的流程先「关口到来」（音乐收住），听静场里的高光
##     [--trace]                                             每 0.25 秒打印配乐的状态（压了多少、哪段、哪些高光在响、总线低通）
## 默认流程：进「先逛逛」→ 从青家出门，经楼道下楼，到街上的早点铺、胡同，再到海河边，再回楼里梅家门口，
## 途中依次触发醒木、青的半句、梅的半句、共鸣、同框车铃、一天结束。
## 给了 --reveal 或 --grow 就只录那一件事：进河畔里，等配乐起了再放几秒，触发，录到余音和下一段起来。
## 事件在录音里的第几秒会打印出来（[capture] mark ...），分析时按它切。
## 不是自动化测试（文件名不以 unit_ 开头，CI 不跑它）。

const LifeTime := preload("res://scripts/ui/life_time.gd")
const Reveal := preload("res://scripts/ui/reveal.gd")
const P := preload("res://scripts/ui/palette.gd")
## 一天五段的中间（world_view.gd 的 SLOTS）
const SLOT_MINUTE := {"早上": 435.0, "上午": 600.0, "下午": 825.0, "傍晚": 1020.0, "晚上": 1215.0,
	"dawn": 435.0, "morning": 600.0, "afternoon": 825.0, "dusk": 1020.0, "night": 1215.0}
const INDOOR := ["building", "rental", "hospital"]  ## weather.gd 的 INDOOR：屋里没有天气

var _out := "user://mix.wav"
var _stage := "childhood"
var _seconds := 110.0
var _minute := -1.0
var _weather := ""
var _reveal := ""
var _grow := false
var _hushed := false
var _trace := false
var _at := ""
var _trace_t := 0.0
var _main: Node
var _rec: AudioEffectRecord
var _rec_at := 0.0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--stage="):
			_stage = arg.trim_prefix("--stage=")
		elif arg.begins_with("--seconds="):
			_seconds = float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--slot="):
			var slot := arg.trim_prefix("--slot=")
			if not SLOT_MINUTE.has(slot):
				printerr("[capture] 不认识的时段 %s（%s）" % [slot, "|".join(SLOT_MINUTE.keys())])
			_minute = float(SLOT_MINUTE.get(slot, -1.0))
		elif arg.begins_with("--minute="):
			_minute = float(arg.trim_prefix("--minute="))
		elif arg.begins_with("--weather="):
			_weather = arg.trim_prefix("--weather=")
		elif arg.begins_with("--reveal="):
			_reveal = arg.trim_prefix("--reveal=")
		elif arg == "--grow":
			_grow = true
		elif arg == "--hushed":
			_hushed = true
		elif arg.begins_with("--at="):
			_at = arg.trim_prefix("--at=")
		elif arg == "--trace":
			_trace = true
	# 文件名和 LifeTime 的名字都认
	_stage = {"child": "childhood"}.get(_stage, _stage)
	process_frame.connect(_run, CONNECT_ONE_SHOT)
	process_frame.connect(_pin)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0 - _rec_at


func _mark(what: String) -> void:
	print("[capture] mark %.2f %s" % [_now(), what])


func _go(world: Node, to: Vector2) -> void:
	var me: Node2D = world.me()
	me.walk_target = Vector2(to.x, me.position.y)  # 侧视：只左右走


## 换一张图（侧视的图一层一张，content.map.scenes 的 floors）：楼里 720、街上 2760、河边 4760
const FLOOR := {"building": 720.0, "street": 2760.0, "river": 4760.0}


func _hop(world: Node, scene: String, x: float) -> void:
	var me: Node2D = world.me()
	me.position = Vector2(x, float(FLOOR.get(scene, 720.0)))
	me.walk_target = me.position


## 每帧（在各节点 _process 之前）把钟点和天气钉住
func _pin() -> void:
	if _main == null or not is_instance_valid(_main) or _main.get("world") == null:
		return
	if _minute >= 0.0:
		_main._preview_minute = _minute
	var w: Variant = _main.world.get("weather")
	if _weather != "" and w is Object and is_instance_valid(w):
		w.kind = "" if str(w.get("_scene")) in INDOOR else _weather
	if _trace and _rec != null and _now() - _trace_t >= 0.25:
		_trace_t = _now()
		var m: Node = _main.get_node("Audio").music
		var hl := []
		for h in m._hl:
			if h.p.playing:
				hl.append("%s@%.1f(%.0fdB)" % [h.name, h.p.get_playback_position(), h.p.volume_db])
		for sp in m._stings:
			if sp.playing:
				hl.append("sting:" + sp.stream.resource_path.get_file().get_basename())
		print("[trace] %.2f %s piece=%s %s duck=%.1f stems=%.1f cut=%.0f wet=%.2f %s" % [_now(), m.stage, m.is_playing_piece(), m.variant(),
			m._duck_db, m._stems.volume_db, m._cut, m._wet, " ".join(hl)])


func _first_turn(stage: String) -> int:
	var turn := 0
	while LifeTime.at(turn).stage != stage and turn < 400:
		turn += 1
	return turn


func _start_rec() -> void:
	_rec = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, _rec)
	_rec.set_recording_active(true)
	_rec_at = Time.get_ticks_msec() / 1000.0


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _wait(0.2)
	var audio: Node = _main.get_node("Audio")
	var focused := _reveal != "" or _grow
	if not focused:
		_start_rec()
		await _wait(4.0)  # 标题音乐
	_main._start_preview()
	# 预览固定在 3 岁；想听别的阶段，就把回合拨到那个阶段的第一天
	_main.life = {"turn": _first_turn(_stage)}
	_main.world.set_stage(_stage)
	audio.music.rest_range = Vector2(6.0, 9.0)
	print("[capture] 阶段 %s  钟点 %s  天气 %s" % [_stage, "走着" if _minute < 0.0 else str(_minute), _weather if _weather != "" else "照季节"])
	if focused:
		await _focused(audio)
	else:
		await _walk(audio)
	var clip := _rec.get_recording()
	_rec.set_recording_active(false)
	var err := clip.save_to_wav(_out)
	print("[capture] %s（%.1f 秒，阶段 %s）→ %s" % ["已保存" if err == OK else "保存失败", clip.get_length(), _stage, _out])
	quit(0 if err == OK else 1)


func _walk(audio: Node) -> void:
	var world: Node = _main.world
	var unit := _seconds / 110.0
	await _wait(8.0 * unit)
	_go(world, Vector2(1500, 0))       # 楼道
	await _wait(8.0 * unit)
	_hop(world, "street", 300.0)       # 下楼，到街上
	_go(world, Vector2(520, 0))        # 早点铺
	await _wait(12.0 * unit)
	_go(world, Vector2(1800, 0))       # 胡同
	await _wait(12.0 * unit)
	_hop(world, "river", 900.0)        # 海河边
	_go(world, Vector2(1400, 0))
	await _wait(16.0 * unit)
	_mark("xingmu")
	audio.cue("xingmu")
	await _wait(2.0)
	audio.cue("stamp")
	audio.sting("call_qing")
	await _wait(4.0)
	audio.sting("call_mei", -7.0)
	await _wait(4.0)
	_mark("resonance")
	audio.sting("resonance")
	await _wait(9.0)
	_hop(world, "building", 1900.0)    # 回楼里，梅家门口
	_go(world, Vector2(2700, 0))
	await _wait(18.0 * unit)
	audio.cue("bell_duet")
	await _wait(6.0 * unit)
	_mark("mismatch")
	audio.sting("mismatch")
	await _wait(9.0)
	_mark("day_end")
	audio.hush(7.0)
	audio.cue("day_end")
	await _wait(6.0)


## 只录一件事：揭晓或长大
func _focused(audio: Node) -> void:
	var music: Node = audio.music
	var at := _at if _at != "" else ("street" if _weather != "" else "building")
	if at != "building":
		_hop(_main.world, at, 1200.0)
	var waited := 0.0
	while not music.is_playing_piece() and waited < 20.0:  # 等配乐起来
		await _wait(0.25)
		waited += 0.25
	_start_rec()
	await _wait(6.0)
	if _reveal != "":
		await _do_reveal(audio)
	if _grow:
		await _do_grow(audio)


## 一回关口揭晓：照 main.gd 的 _show_milestone_result 搭一把我的尺子，声音走导演的 reveal_cue（真的那条路）
func _do_reveal(audio: Node) -> void:
	var ob: Node = audio.get_node_or_null("Observer")
	if _hushed and ob != null:  # 关口到来：音乐收住（观察者的 _on_event_started）
		_mark("milestone_started")
		ob._on_event_started({"event": {"kind": "milestone", "roles": ["qing"]}})
		await _wait(8.0)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var rv: Control = Reveal.new()
	rv.who = "青"
	rv.color = P.QING
	rv.line = 60
	rv.delay = 0.45
	rv.custom_minimum_size.x = 740.0
	match _reveal:
		"pass":
			rv.score = 78
		"top":
			rv.score = 93
			rv.rank = "年级前十"
		"miss":
			rv.score = 57
			rv.miss = {"need": 60, "have": 57, "text": "差一点"}
		_:
			printerr("[capture] 不认识的揭晓 %s（pass|top|miss）" % _reveal)
	rv.sound = audio.reveal_cue if audio.has_method("reveal_cue") else audio.cue
	rv.finished.connect(func(ok: bool): _mark("reveal_done passed=%s" % ok))
	# 日志里的关口揭晓和弹窗同一刻到：观察者要自己认出尺子接管了，不再叠「关口」那句
	if ob != null:
		ob._on_log_entries({"entries": [{"kind": "milestone", "resonance": true}]})
	_mark("reveal_" + _reveal)
	layer.add_child(rv)
	await _wait(14.0)


## 一回长大：回合拨到下一个阶段的第一天，观察者看见阶段变了自己去调 grow；画面上照 main 盖墨卡
func _do_grow(_audio: Node) -> void:
	var order := ["childhood", "teen", "young", "middle", "old"]
	var i := order.find(_stage)
	if i < 0 or i >= order.size() - 1:
		printerr("[capture] %s 之后没有下一个阶段了" % _stage)
		return
	var next: String = order[i + 1]
	var turn := _first_turn(next)
	_mark("grow_" + next)
	_main.life = {"turn": turn}
	if _main.has_method("_grow_up"):
		_main._grow_up(LifeTime.at(turn))
	else:
		_main.world.set_stage(next)
	await _wait(22.0)  # 长大那段（约 6.5 秒）+ 新阶段的第一段起来
