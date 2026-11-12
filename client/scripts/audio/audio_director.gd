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
##   reveal_cue(cue, db, pitch)           关口揭晓那把尺子的声音：音效照放，再起高光（rise / pass / top / miss）
##   grow(stage)                          长大：放 grow_<阶段>，这一段配乐收掉，放完从新阶段开始
##   step(role, pos, moved, mine)         脚步
##
## 设计说明见 docs/AUDIO.md；素材由 tools/audio/build_audio.py 生成。

const MusicPlayer := preload("res://scripts/audio/music_player.gd")
const Soundscape := preload("res://scripts/audio/soundscape.gd")
const Observer := preload("res://scripts/audio/main_observer.gd")
## 三条总线和每个音效的音量（BUS_DB / CUE_DB）：改音量只改那一个文件
const Mix := preload("res://scripts/audio/mix_table.gd")

const SFX_DIR := "res://audio/sfx/"
const MANIFEST := "res://audio/manifest.json"
const SETTINGS := "user://audio.cfg"
const STAGE_FILE := {"childhood": "child", "teen": "teen", "young": "young", "middle": "middle", "old": "old"}
## 一步多长（像素）。小孩步子碎，老人步子慢
const STRIDE := {"child": 44.0, "teen": 54.0, "young": 60.0, "middle": 60.0, "old": 48.0}
const STEP_PITCH := {"child": 1.18, "teen": 1.06, "young": 1.0, "middle": 0.96, "old": 0.92}
## 没有专门音效的行动，借用相近的
const ACT_ALIAS := {"read": "study", "picture_book": "study", "walk_river": "play_river", "dine": "eat_out", "ball": "play_alley", "chat": "listen", "club_math": "study", "club_sport": "play_alley", "club_art": "perform",
	# 新地图上的去处（content/maps/）：先借近的声音，以后要专门的再加素材
	"chess": "study", "blackboard": "study", "broadcast": "perform", "rail_talk": "play_river", "window_shop": "eat_out", "dine_west": "eat_out", "read_store": "study", "night_snack": "eat_out", "cook": "eat", "balcony": "play_roof", "morning_walk": "play_river", "choir": "perform", "ground_write": "study", "accompany": "wash",
	# 家境（docs/MEANS.md）
	"piano": "perform", "tutor": "study", "help_out": "work", "factory_bath": "wash", "letter": "study",
	# 外地（content/maps/away.yaml）
	"club_campus": "perform",
	# 同一道关不同的冲法、各条路下了班的营生（docs/MEANS.md 第六节）
	"swim_class": "play_river", "lang_class": "study", "banquet": "eat_out", "night_class": "study",
	"side_tutor": "study", "side_fix": "work", "night_market": "eat_out", "overtime": "study", "night_shift": "work",
	"run_dawn": "play_river", "old_lessons": "study",
	# 点位菜单上后添的（content/map.yaml 末尾）
	"pancake": "eat_out", "tea_runner": "listen", "mall_clerk": "eat_out", "river_run": "play_river", "laps": "play_alley", "hopscotch": "play_alley",
	"sketch": "study", "coal": "work", "cards": "listen", "teach_chess": "study", "flowers": "play_roof", "boat": "play_river", "huqin": "perform",
	"tea_box": "listen",
	# 后半生押时间（content/events/later.yaml）
	"old_breakfast": "work", "old_bikes": "work", "mind_kids": "play_alley", "grandkid_park": "play_river",
	# 带孩子（docs/FAMILY.md）
	"kid_homework": "study", "kid_run": "play_river", "kid_listen": "listen", "kid_class": "study",
	"square_dance": "perform", "pair_cook": "eat", "gk_pickup": "play_alley",
	# 门外的世界（content/maps/{market,seaside,village}.yaml）：早市借早点铺的吆喝、海边和河沟借河边的水声、地里的活借干活
	"soy_milk": "eat_out", "stall_sell": "eat_out", "market_walk": "eat_out", "buy_veg": "eat_out", "haul_crate": "work", "scrap_sell": "work",
	"shell_buy": "eat_out", "sea_swim": "play_river", "sand_castle": "play_alley", "tide_dig": "fish", "ship_watch": "play_river",
	"feed_chicken": "play_alley", "farm_help": "work", "creek_fish": "fish", "star_night": "play_roof",
	"see_doctor": "listen", "ward_meal": "eat",
	# 家里的东西（content/home.yaml）
	"hm_tv": "listen", "hm_radio": "listen", "hm_console": "play_alley", "hm_books": "study", "hm_tape": "study",
	"hm_pc": "study", "hm_pc_game": "play_alley", "hm_milk": "eat", "hm_piece": "work",
	"buy_console": "work", "buy_tape": "work", "buy_pc": "work",
	# 人际圈子（content/circle.yaml）：攒门路的几样
	"class_help": "study", "help_neighbor": "work", "visit_kin": "listen", "treat": "eat_out"}
## 揭晓：名次章的音高（reveal.gd 砸横章那一下），认它来起 top
const TOP_PITCH := 1.12
## 揭晓的声音隔这么久没来，下一颗算盘珠就算新的一回揭晓
const REVEAL_GAP := 4.0
## 三条总线的音量（0~1），玩家在菜单（ui/system_menu.gd）里拖。乘在混音表的总线音量上，存在 SETTINGS 里
const VOLUME_BUSES := ["Music", "Ambience", "Sfx"]

var music: MusicPlayer
var scape: Soundscape
var volume := {"Music": 1.0, "Ambience": 1.0, "Sfx": 1.0}

var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _steps: Array[AudioStreamPlayer] = []
var _step_i := 0
var _cache: Dictionary = {}
var _walked := {}
var _stage := "child"
var _look := "child"  ## 声景按哪个年代（STAGE_FILE 的值）：era.look，没有就是 _stage
var _map: Dictionary = {}
var _focus := 0.0
var _reveal_at := -100.0  ## 上一下揭晓的声音是什么时候（秒）
var _rose := false        ## 这一回揭晓的 rise 起过了
var _took_over_at := -100.0  ## 上一回揭晓的高光真响起来是什么时候


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
	_apply_volume()
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
	for bus_name in Mix.BUS_DB:  # 总线的音量也照表（原来只有 Ambience 在 set_life 里设了，Music / Sfx 一直是 0）
		AudioServer.set_bus_volume_db(_bus(bus_name, "Master"), float(Mix.BUS_DB[bus_name]))
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
	if cfg.load(SETTINGS) != OK:
		return
	# 以前右上角是一颗三档的按钮（乐 → 响 → 静）：老存档换算成三条音量
	var old := int(cfg.get_value("audio", "level", 0))
	for bus in VOLUME_BUSES:
		var muted: bool = old >= 2 or (old >= 1 and bus == "Music")
		volume[bus] = clampf(float(cfg.get_value("audio", bus.to_lower(), 0.0 if muted else 1.0)), 0.0, 1.0)


## 菜单里拖音量：v 是 0~1。save = 松手了才写盘（拖的时候每帧都写太勤）
func set_volume(bus: String, v: float, save := true) -> void:
	if not volume.has(bus):
		return
	volume[bus] = clampf(v, 0.0, 1.0)
	_apply_volume()
	if save:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS)
		for b in VOLUME_BUSES:
			cfg.set_value("audio", b.to_lower(), volume[b])
		if cfg.has_section_key("audio", "level"):
			cfg.erase_section_key("audio", "level")
		cfg.save(SETTINGS)


## 拖到底就是关掉（静音），不然按耳朵的感觉换成分贝：上半截变化细，下半截一下子小下去
func _user_db(bus: String) -> float:
	return linear_to_db(maxf(float(volume[bus]), 0.001))


func _apply_volume() -> void:
	for bus in VOLUME_BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		AudioServer.set_bus_mute(i, float(volume[bus]) <= 0.01)
		AudioServer.set_bus_volume_db(i, float(Mix.BUS_DB[bus]) + _user_db(bus) - (6.0 * _focus if bus == "Ambience" else 0.0))


# ---------------------------------------------------------------- 接口 ----

func set_scene(scene: String) -> void:
	music.set_mode(scene)
	scape.active = scene == "life"


## 河畔里每帧的状态。weather：rain / snow / catkin / leaf / ""（world.weather.kind，屋里的图没有天气）
func set_life(map: Dictionary, my_role: String, me_pos: Vector2, other_pos: Variant, partner_live: bool,
		turn: int, stage: String, season: String, minute: float, school_day: bool, sync: float, focus: bool,
		weather := "", look := "") -> void:
	if not scape.is_setup or not is_same(map, _map):  # 内容热更新后地图会换一份（比如多了茶馆）
		_map = map
		scape.setup(map)
	_stage = STAGE_FILE.get(stage, "child")
	music.set_stage(_stage)
	var near := 0.0
	if other_pos is Vector2:
		near = 1.0 - smoothstep(260.0, 1300.0, me_pos.distance_to(other_pos))
	music.set_mix(my_role, near, partner_live, sync, minute, weather)
	# 声景（街上的叫卖、车、广播）跟着年代走：服务器给了 era.look 用它，不然跟着人生阶段（音乐、脚步还是跟着岁数）
	_look = STAGE_FILE.get(look, _stage) if look != "" else _stage
	scape.update(get_process_delta_time(), me_pos, minute, _look, season, school_day, weather)
	# 弹窗（事件、一天结束）出来的时候，把环境音让一让
	_focus = move_toward(_focus, 1.0 if focus else 0.0, get_process_delta_time() * 2.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), Mix.BUS_DB.Ambience + _user_db("Ambience") - 6.0 * _focus)
	AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("Steps"), 0, scape.zone_at(me_pos) == "hallway")


## 没进河畔里的时候（菜单页）也要每帧调一次，让环境音淡出去
func idle() -> void:
	if scape.is_setup:
		scape.update(get_process_delta_time(), Vector2.ZERO, 720.0, _look, "spring", false)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), Mix.BUS_DB.Ambience + _user_db("Ambience"))


func cue(cue_name: String, db := 0.0, pitch := 1.0) -> void:
	var s := _load(cue_name)
	if s == null:
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = s
	p.volume_db = float(Mix.CUE_DB.get(cue_name, -6.0)) + db
	p.pitch_scale = pitch
	p.play()


## 开始做一件事（吃饭、写作业、放鸽子……）。mine=false 是对方在做，轻一点
func act(action_id: String, mine := true, near := 1.0) -> void:
	var cue_name := act_cue(action_id, _stage)
	if mine:
		cue(cue_name, -4.0)
	elif near > 0.15:
		cue(cue_name, -10.0 + linear_to_db(near))


## 一个行动在这个阶段（STAGE_FILE 的值）用哪条音效。还没有自己声音的行动借一条近的（ACT_ALIAS）。
## 单测按这张映射查素材（tests/unit_audio.gd），所以新加行动要么有 sfx/act_<id>.ogg，要么在这里有去处
static func act_cue(action_id: String, stage_file: String) -> String:
	if action_id == "duty":  # 「该干的事」：小时候是上学，长大了是上班
		action_id = "school" if stage_file in ["child", "teen"] else "work"
	return "act_" + str(ACT_ALIAS.get(action_id, action_id))


func sting(kind: String, db := 0.0) -> void:
	music.sting(kind, db)


func hush(rest_seconds := 6.0) -> void:
	music.hush(rest_seconds)


## 关口揭晓：我那把尺子（ui/reveal.gd）的声音从这里过。音效照放，再按这一下是什么起高光：
##   第一颗算盘珠 → <阶段>_rise（一次揭晓只起一回）；够线 pass → _pass；差一点 miss → _miss；
##   名次章（seal，音高 1.12）→ _top。对方那把尺子仍然走 cue，不起高光
func reveal_cue(cue_name: String, db := 0.0, pitch := 1.0) -> void:
	cue(cue_name, db, pitch)
	var now := Time.get_ticks_msec() / 1000.0
	if now - _reveal_at > REVEAL_GAP:
		_rose = false  # 隔了这么久，是新的一回揭晓了
	_reveal_at = now
	var hl := ""
	match cue_name:
		"bead":
			if not _rose:
				_rose = true
				hl = _stage + "_rise"
		"pass", "miss":
			hl = "%s_%s" % [_stage, cue_name]
		"seal":
			if absf(pitch - TOP_PITCH) < 0.02:
				hl = _stage + "_top"
	# 只有结果（够线 / 差一点 / 名次）真响起来才算接管：走的路没有线时尺子只数珠子、不出结果，
	# 那就还让观察者补上日志里那句乐句，rise 由 end_reveal 收掉
	if hl != "" and music.highlight(hl) and cue_name != "bead":
		_took_over_at = now


## 这一回揭晓没有结果音（走的路没有线）：悬着的 rise 收掉，别断在半空
func end_reveal() -> void:
	music.fade_highlights(["rise"], 0.4)


## 刚才几秒里揭晓的高光有没有真响起来（观察者用：接管了，日志里「关口」那句乐句就不再叠一遍；
## 老素材没有高光文件，就还是那句乐句）
func reveal_active(within := REVEAL_GAP) -> bool:
	return Time.get_ticks_msec() / 1000.0 - _took_over_at < within


## 长大了：stage 是 LifeTime 的阶段名（childhood / teen ...）或者文件名（child / teen ...）都行
func grow(stage: String) -> void:
	var s: String = STAGE_FILE.get(stage, stage)
	_stage = s
	music.grow(s)


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
