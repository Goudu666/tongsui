extends Node
## 《同岁》的声音导演：配乐、环境音、音效三样都归它管。
##
## 游戏代码不需要知道它的存在。它挂在主场景下面，自己带一个观察者（main_observer.gd）
## 去看主场景的状态和联机信号，再翻译成下面这几个接口。以后主场景重构了，
## 只要换掉观察者，或者直接调这些接口：
##   set_scene(name)                      title / roll / life / ending
##   set_life(...)                        每帧：人在哪儿、几点、哪个阶段、两人多近、默契多少
##   cue(name) / act(action_id)           界面音、行动音
##   sting(kind)                          默契乐句
##   step(role, pos, moved, mine)         脚步
##
## 设计说明见 docs/AUDIO.md；素材由 tools/audio/build_audio.py 生成。

const MusicPlayer := preload("res://scripts/audio/music_player.gd")
const Soundscape := preload("res://scripts/audio/soundscape.gd")
const Observer := preload("res://scripts/audio/main_observer.gd")
const P := preload("res://scripts/ui/palette.gd")

const SFX_DIR := "res://audio/sfx/"
const MANIFEST := "res://audio/manifest.json"
const SETTINGS := "user://audio.cfg"
const STAGE_FILE := {"childhood": "child", "teen": "teen", "young": "young", "middle": "middle", "old": "old"}
const BUS_DB := {"Music": 2.0, "Ambience": 1.0, "Sfx": -1.0}
## 单个音效的音量微调（dB）。没列出来的是 -6
const CUE_DB := {"tap": -7.0, "page": -9.0, "toast": -9.0, "type": -12.0, "xingmu": -3.0, "stamp": -4.0,
	"birth": -3.0, "day_end": -3.0, "death": -2.0, "shake": -4.0, "bell_duet": -7.0, "door_open": -9.0, "door_close": -9.0}
## 一步多长（像素）。小孩步子碎，老人步子慢
const STRIDE := {"child": 44.0, "teen": 54.0, "young": 60.0, "middle": 60.0, "old": 48.0}
const STEP_PITCH := {"child": 1.18, "teen": 1.06, "young": 1.0, "middle": 0.96, "old": 0.92}
## 没有专门音效的行动，借用相近的
const ACT_ALIAS := {"read": "study", "walk_river": "play_river", "dine": "eat_out", "ball": "play_alley"}
## 设置按钮的三档：全开 → 只关音乐 → 静音
const LEVELS := ["乐", "响", "静"]

var music: MusicPlayer
var scape: Soundscape
var level := 0

var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _steps: Array[AudioStreamPlayer] = []
var _step_i := 0
var _cache: Dictionary = {}
var _walked := {}
var _stage := "child"
var _button: Button
var _focus := 0.0


func _ready() -> void:
	_make_buses()
	music = MusicPlayer.new()
	scape = Soundscape.new()
	add_child(music)
	add_child(scape)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) if FileAccess.file_exists(MANIFEST) else null
	music.manifest = parsed if parsed is Dictionary else {}
	for i in 10:
		_pool.append(_player("Sfx"))
	for i in 4:
		_steps.append(_player("Steps"))
	_load_settings()
	_make_button()
	_apply_level()
	var host := get_parent()
	if host != null and host.get_script() != null and "modal_body" in host:
		var ob := Observer.new()
		ob.name = "Observer"
		add_child(ob)
		ob.attach(host, self)


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


# ---------------------------------------------------------------- 总线 ----

func _make_buses() -> void:
	for bus_name in BUS_DB:
		_bus(bus_name, "Master")
	var steps := _bus("Steps", "Sfx")
	if AudioServer.get_bus_effect_count(steps) == 0:
		var rv := AudioEffectReverb.new()  # 楼道里的脚步有回声，出了楼道就关掉
		rv.room_size = 0.55
		rv.damping = 0.6
		rv.wet = 0.28
		rv.dry = 1.0
		AudioServer.add_bus_effect(steps, rv)
		AudioServer.set_bus_effect_enabled(steps, 0, false)
	if AudioServer.get_bus_effect_count(0) == 0:
		var lim: AudioEffect = ClassDB.instantiate("AudioEffectHardLimiter") if ClassDB.class_exists("AudioEffectHardLimiter") else AudioEffectLimiter.new()
		AudioServer.add_bus_effect(0, lim)


func _bus(bus_name: String, send: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, send)
	return i


# ---------------------------------------------------------------- 设置 ----

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		level = clampi(int(cfg.get_value("audio", "level", 0)), 0, LEVELS.size() - 1)


func _apply_level() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), level >= 1)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Ambience"), level >= 2)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Sfx"), level >= 2)
	if _button != null:
		_button.text = LEVELS[level]
		_button.modulate.a = 0.85 if level == 0 else 0.5


func _make_button() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_button = Button.new()
	_button.focus_mode = Control.FOCUS_NONE
	_button.anchor_left = 1.0
	_button.anchor_right = 1.0
	_button.offset_left = -136
	_button.offset_right = -48
	_button.offset_top = 76
	_button.offset_bottom = 164
	_button.add_theme_font_override("font", P.font())
	_button.add_theme_font_size_override("font_size", 40)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(P.PAPER, 0.9)
	sb.border_color = P.INK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(44)
	for st in ["normal", "hover", "pressed", "focus"]:
		_button.add_theme_stylebox_override(st, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_button.add_theme_color_override(c, P.INK)
	_button.pressed.connect(func():
		level = (level + 1) % LEVELS.size()
		_apply_level()
		cue("tap", 0.0, 1.12)
		var cfg := ConfigFile.new()
		cfg.set_value("audio", "level", level)
		cfg.save(SETTINGS))
	layer.add_child(_button)


# ---------------------------------------------------------------- 接口 ----

func set_scene(scene: String) -> void:
	music.set_mode(scene)
	scape.active = scene == "life"


## 河畔里每帧的状态
func set_life(map: Dictionary, my_role: String, me_pos: Vector2, other_pos: Variant, partner_live: bool,
		turn: int, stage: String, season: String, minute: float, school_day: bool, sync: float, focus: bool) -> void:
	if not scape.is_setup:
		scape.setup(map)
	_stage = STAGE_FILE.get(stage, "child")
	music.set_stage(_stage)
	var near := 0.0
	if other_pos is Vector2:
		near = 1.0 - smoothstep(260.0, 1300.0, me_pos.distance_to(other_pos))
	music.set_mix(my_role, near, partner_live, sync, minute)
	scape.update(get_process_delta_time(), me_pos, minute, _stage, season, school_day)
	# 弹窗（事件、一天结束）出来的时候，把环境音让一让
	_focus = move_toward(_focus, 1.0 if focus else 0.0, get_process_delta_time() * 2.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), BUS_DB.Ambience - 6.0 * _focus)
	AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("Steps"), 0, scape.zone_at(me_pos) == "hallway")


## 没进河畔里的时候（菜单页）也要每帧调一次，让环境音淡出去
func idle() -> void:
	if scape.is_setup:
		scape.update(get_process_delta_time(), Vector2.ZERO, 720.0, _stage, "spring", false)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), BUS_DB.Ambience)


func cue(cue_name: String, db := 0.0, pitch := 1.0) -> void:
	var s := _load(cue_name)
	if s == null:
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = s
	p.volume_db = float(CUE_DB.get(cue_name, -6.0)) + db
	p.pitch_scale = pitch
	p.play()


## 开始做一件事（吃饭、写作业、放鸽子……）。mine=false 是对方在做，轻一点
func act(action_id: String, mine := true, near := 1.0) -> void:
	if action_id == "duty":  # 「该干的事」：小时候是上学，长大了是上班
		action_id = "school" if _stage in ["child", "teen"] else "work"
	action_id = ACT_ALIAS.get(action_id, action_id)
	if mine:
		cue("act_" + action_id, -4.0)
	elif near > 0.15:
		cue("act_" + action_id, -10.0 + linear_to_db(near))


func sting(kind: String, db := 0.0) -> void:
	music.sting(kind, db)


func hush(rest_seconds := 6.0) -> void:
	music.hush(rest_seconds)


## 脚步。moved：这一帧走了多远；gain 0~1：离听的人多近
func step(role: String, pos: Vector2, moved: float, mine: bool, gain := 1.0) -> void:
	_walked[role] = float(_walked.get(role, 0.0)) + moved
	if _walked[role] < float(STRIDE[_stage]):
		return
	_walked[role] = 0.0
	if gain < 0.08:
		return
	var s := _load("step_%s_%d" % ["indoor" if scape.is_indoor(pos) else "outdoor", randi() % 4])
	if s == null:
		return
	var p := _steps[_step_i]
	_step_i = (_step_i + 1) % _steps.size()
	p.stream = s
	p.volume_db = (-9.0 if mine else -13.0) + linear_to_db(gain)
	p.pitch_scale = float(STEP_PITCH[_stage]) * randf_range(0.93, 1.07)
	p.play()


func _load(cue_name: String) -> AudioStream:
	if _cache.has(cue_name):
		return _cache[cue_name]
	var path := SFX_DIR + cue_name + ".ogg"
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_cache[cue_name] = s
	return s
