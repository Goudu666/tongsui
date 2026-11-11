extends Node
## 河畔里的环境音。读 res://audio/soundscape.json（声景表），按「人在哪儿、几点钟、哪个年代、什么季节」
## 决定每个声音响不响、多响。两类：
##   beds   铺底的循环：空气、河水、鏊子、蝉、话匣子……人往哪儿走，哪儿的声音就近
##   shots  隔一阵响一下的：车铃、鸽哨、锅铲、船笛、快板……
## 声景表里每个声音都有五个人生阶段的密度：童年的声音密，老年的声音稀。
## 天气（weather.gd 的 kind：rain / snow / catkin / leaf，屋里的图是 ""）：
##   "weather": [...]      只在这些天气响（雨声、雪天的风）
##   "not_weather": [...]  这些天气不响（下雨没有蝉、没有鸽哨）
##   "weather_gain": {天气: 倍数}  这个天气少一点（单发既更少也更轻）
##   表顶上的 "weather_db": {天气: dB}  这个天气整体多响（下雪 -3.5：世界静了），天气自己的声音不算在内
##   "sway": [秒, 最低]  一阵大一阵小（雨）：音量在「最低」和 1 之间慢慢起落，一个来回大约这么多秒

const DIR := "res://audio/amb/"
const TABLE := "res://audio/soundscape.json"
const BUS := "Ambience"
const SILENT := -60.0
const STAGES := ["child", "teen", "young", "middle", "old"]

var table: Dictionary = {}
var active := false
var is_setup := false

var _zones: Array = []          ## [{id, rect}]
var _indoor: Array = []
var _reach := 420.0
var _beds: Array = []           ## [{cfg, player, db}]
var _shots: Array = []          ## [{cfg, wait, last}]
var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _cache: Dictionary = {}
var _minute := -1.0
var _clock := 0.0
var _zw: Dictionary = {}        ## 这一帧里按 reach 缓存的地点分量（听的人这一帧只在一个地方）
var _weather := ""
var _weather_db: Dictionary = {}


func setup(map: Dictionary) -> void:
	is_setup = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE)) if FileAccess.file_exists(TABLE) else null
	table = parsed if parsed is Dictionary else {}
	_indoor = table.get("indoor", [])
	_reach = float(table.get("reach", 420.0))
	_weather_db = table.get("weather_db", {})
	_zones.clear()
	for z in map.get("zones", []):
		_zones.append({"id": str(z.id), "rect": Rect2(z.rect[0], z.rect[1], z.rect[2], z.rect[3])})
	if _beds.is_empty():
		for cfg in table.get("beds", []):
			var p := AudioStreamPlayer.new()
			p.bus = BUS
			p.volume_db = SILENT
			add_child(p)
			_beds.append({"cfg": cfg, "player": p, "db": SILENT, "phase": randf() * TAU})
		for cfg in table.get("shots", []):
			var every: Array = cfg.get("every", [20, 40])
			_shots.append({"cfg": cfg, "wait": randf_range(0.3, 1.0) * float(every[1]), "last": -99.0})
		for i in 6:
			var p := AudioStreamPlayer.new()
			p.bus = BUS
			add_child(p)
			_pool.append(p)


func _load(file: String, loop := false) -> AudioStream:
	if _cache.has(file):
		return _cache[file]
	var path := DIR + file + ".ogg"
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	if s is AudioStreamOggVorbis:
		s.loop = loop
	_cache[file] = s
	return s


## 人在 pos 时，各个地点的分量：在里面是 1，出去之后按 reach 衰减
func zone_weights(pos: Vector2, reach: float) -> Dictionary:
	var w := {}
	var inside := 0.0
	for z in _zones:
		var r: Rect2 = z.rect
		var d := Vector2(maxf(maxf(r.position.x - pos.x, pos.x - r.end.x), 0.0), maxf(maxf(r.position.y - pos.y, pos.y - r.end.y), 0.0)).length()
		var v := clampf(1.0 - d / reach, 0.0, 1.0)
		w[z.id] = v * v
		if z.id in _indoor:
			inside = maxf(inside, clampf(1.0 - d / 90.0, 0.0, 1.0))
	w["in"] = inside
	w["out"] = 1.0 - inside
	return w


func zone_at(pos: Vector2) -> String:
	for z in _zones:
		if (z.rect as Rect2).has_point(pos):
			return z.id
	return ""


func is_indoor(pos: Vector2) -> bool:
	return zone_at(pos) in _indoor


static func _hours(cfg: Dictionary, minute: float) -> float:
	if not cfg.has("hours"):
		return 1.0
	var best := 0.0
	for win in cfg.hours:
		best = maxf(best, clampf(minf(minute - float(win[0]), float(win[1]) - minute) / 20.0 + 0.25, 0.0, 1.0))
	return best


## 天气对这个声音的倍数：0 是不响
func _weather_gain(cfg: Dictionary) -> float:
	if cfg.has("weather") and not _weather in cfg.weather:
		return 0.0
	if cfg.has("not_weather") and _weather in cfg.not_weather:
		return 0.0
	var g: Variant = cfg.get("weather_gain", {})
	return float(g.get(_weather, 1.0)) if g is Dictionary else 1.0


## 这个天气整体压多少 dB。天气自己的声音（写了 weather 的）不压
func _hush(cfg: Dictionary) -> float:
	return 0.0 if cfg.has("weather") else float(_weather_db.get(_weather, 0.0))


func _weight(cfg: Dictionary, pos: Vector2, minute: float, stage_i: int, season: String) -> float:
	if cfg.has("seasons") and not season in cfg.seasons:
		return 0.0
	var stages: Array = cfg.get("stages", [1, 1, 1, 1, 1])
	var f := float(stages[clampi(stage_i, 0, stages.size() - 1)]) * _hours(cfg, minute) * _weather_gain(cfg)
	if f <= 0.0:
		return 0.0
	var reach := float(cfg.get("reach", _reach))
	if not _zw.has(reach):
		_zw[reach] = zone_weights(pos, reach)
	var zw: Dictionary = _zw[reach]
	var best := 0.0
	for zid in cfg.get("zones", {}):
		best = maxf(best, float(cfg.zones[zid]) * float(zw.get(zid, 0.0)))
	return f * best


## 每帧调用。pos：听的人在哪儿；minute：游戏时间；stage：人生阶段；season：spring/summer/autumn/winter；
## weather：rain / snow / catkin / leaf / ""（屋里的图没有天气）
func update(delta: float, pos: Vector2, minute: float, stage: String, season: String, school_day: bool, weather := "") -> void:
	var stage_i := maxi(0, STAGES.find(stage))
	_weather = weather
	var prev := _minute
	_minute = minute
	_clock += delta
	_zw.clear()
	for b in _beds:
		var w := _weight(b.cfg, pos, minute, stage_i, season) if active else 0.0
		if w > 0.0 and b.cfg.has("sway"):
			w *= _sway(b.cfg.sway, b.phase)
		var want := float(b.cfg.get("db", 0.0)) + _hush(b.cfg) + linear_to_db(w) if w > 0.003 else SILENT
		b.db = move_toward(b.db, want, 22.0 * delta)
		var p: AudioStreamPlayer = b.player
		if b.db <= SILENT + 0.5:
			if p.playing:
				p.stop()
			continue
		if not p.playing:
			p.stream = _load(str(b.cfg.file), true)
			if p.stream == null:
				continue
			p.play(randf() * p.stream.get_length())
		p.volume_db = b.db
	if not active:
		return
	for s in _shots:
		var cfg: Dictionary = s.cfg
		if cfg.has("at"):
			if cfg.get("school_day", false) and not school_day:
				continue
			for at in cfg.at:
				if prev >= 0.0 and prev < float(at) and minute >= float(at) and _clock - s.last > 6.0:
					_fire(s, _weight(cfg, pos, float(at), stage_i, season))
			continue
		s.wait -= delta
		if s.wait > 0.0:
			continue
		var every: Array = cfg.get("every", [20, 40])
		s.wait = randf_range(float(every[0]), float(every[1]))
		var w := _weight(cfg, pos, minute, stage_i, season)
		if w > 0.02 and randf() < sqrt(w):
			_fire(s, w)


## 一阵大一阵小：两个不成整数比的慢正弦叠起来，听不出周期
func _sway(spec: Array, phase: float) -> float:
	var period := maxf(float(spec[0]), 1.0)
	var low := clampf(float(spec[1]) if spec.size() > 1 else 0.3, 0.0, 1.0)
	var u := 0.5 + 0.3 * sin(TAU * _clock / period + phase) + 0.2 * sin(TAU * _clock / (period * 0.37) + phase * 2.3)
	return lerpf(low, 1.0, clampf(u, 0.0, 1.0))


func _fire(s: Dictionary, w: float) -> void:
	if w <= 0.02:
		return
	var files: Array = s.cfg.files
	var stream := _load(str(files[randi() % files.size()]))
	if stream == null:
		return
	var p := _pool[_pool_i]
	for i in _pool.size():  # 找一个空闲的；都在响就顶掉最早的
		var q := _pool[(_pool_i + i) % _pool.size()]
		if not q.playing:
			p = q
			break
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = stream
	p.volume_db = float(s.cfg.get("db", -12.0)) + _hush(s.cfg) + linear_to_db(clampf(w, 0.05, 1.0))
	p.pitch_scale = randf_range(0.97, 1.03)
	p.play()
	s.last = _clock


func silence() -> void:
	active = false
